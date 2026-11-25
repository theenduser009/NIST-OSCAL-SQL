-- Step 5. Compare Archer package and standard assignments with saved SSPs.
-- Run the complete read-only block from the same DEV curated worksheet as Query 1.
-- Read-only DEV. Compares all raw package IDs to saved Source One SSP roots,
-- then independent allocation/Standard assignments to Josh's saved requirement references.
-- Both matching and differing IDs are returned. The SUMMARY rows come first.
-- Owner = first item of the allocation's AUTHORIZATION_PACKAGE array. This follows
-- the mapper's scalar/enriched-scalar rule. A later owner item never substitutes for it.
-- A raw assignment below requires readable source records, an existing raw package
-- and Standard, and a DPF member with a compatible declared domain, if present.
-- Raw assignments intentionally include rows lacking CONTROL_NUMBER/ALLOCATED_CONTROL_ID:
-- these are source associations even if the mapper cannot emit a usable requirement.
EXECUTE IMMEDIATE $$
DECLARE
    raw_ns VARCHAR;
    inventory_id VARCHAR;
    scope_error EXCEPTION (-20031, 'Expected one visible DEV Archer RAW schema with all required tables. Check worksheet role and DEV access.');
    tbl_authorization_package_raw VARCHAR;
    tbl_allocated_controls_control_raw VARCHAR;
    tbl_control_standards_raw VARCHAR;
    rows_out RESULTSET;
BEGIN
    SHOW TERSE OBJECTS IN ACCOUNT STARTS WITH 'ARCHER_';
    inventory_id := SQLID;
    SELECT IFF(COUNT(*) = 1, MIN(qualified_namespace), NULL) INTO :raw_ns
    FROM (
        SELECT '"' || REPLACE("database_name", '"', '""') || '"."' || REPLACE("schema_name", '"', '""') || '"' AS qualified_namespace
        FROM TABLE(RESULT_SCAN(:inventory_id))
        WHERE "kind" IN ('TABLE', 'VIEW') AND ENDSWITH(UPPER("database_name"), '_DEV')
          AND "name" IN (
              'ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW',
              'ARCHER_CONTENT_ALLOCATED_CONTROLS_CONTROL_RAW',
              'ARCHER_CONTENT_CONTROL_STANDARDS_RAW'
          )
        GROUP BY "database_name", "schema_name"
        HAVING COUNT(DISTINCT "name") = 3
    ) candidates;
    IF (raw_ns IS NULL) THEN
        RAISE scope_error;
    END IF;
    tbl_authorization_package_raw := raw_ns || '.ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW';
    tbl_allocated_controls_control_raw := raw_ns || '.ARCHER_CONTENT_ALLOCATED_CONTROLS_CONTROL_RAW';
    tbl_control_standards_raw := raw_ns || '.ARCHER_CONTENT_CONTROL_STANDARDS_RAW';
    rows_out := (
        WITH input_rows AS (
            SELECT 'PACKAGE' AS kind, CONTENT_ID::VARCHAR AS id,
                   TRY_PARSE_JSON(CURATED_JSON::VARCHAR) AS doc
            FROM IDENTIFIER(:tbl_authorization_package_raw)
            UNION ALL
            SELECT 'ALLOCATION', CONTENT_ID::VARCHAR, TRY_PARSE_JSON(CURATED_JSON::VARCHAR)
            FROM IDENTIFIER(:tbl_allocated_controls_control_raw)
            UNION ALL
            SELECT 'STANDARD', CONTENT_ID::VARCHAR, TRY_PARSE_JSON(CURATED_JSON::VARCHAR)
            FROM IDENTIFIER(:tbl_control_standards_raw)
        ), raw_ids AS (
            SELECT kind, id, COUNT(*) AS stored_rows, COUNT(DISTINCT TO_JSON(doc)) AS versions,
                   COUNT_IF(NOT COALESCE(IS_OBJECT(doc), FALSE) OR TO_JSON(doc) = '{}') AS invalid_docs,
                   MIN(TO_JSON(doc)) AS json_text
            FROM input_rows GROUP BY kind, id
        ), records AS (
            SELECT kind, id, stored_rows,
                   CASE WHEN id IS NULL OR NOT REGEXP_LIKE(id,'[1-9][0-9]*') THEN 'INVALID_ID'
                        WHEN invalid_docs > 0 THEN 'UNREADABLE_JSON'
                        WHEN versions <> 1 THEN 'CONFLICTING_VERSIONS'
                        ELSE 'OK' END AS record_status,
                   IFF(versions = 1 AND COALESCE(invalid_docs,0) = 0, TRY_PARSE_JSON(json_text), NULL) AS doc
            FROM raw_ids
        ), allocation_fields AS (
            SELECT id AS allocation_id, record_status, doc:AUTHORIZATION_PACKAGE AS owners,
                   GET(AS_ARRAY(doc:AUTHORIZATION_PACKAGE),0) AS first_owner,
                   doc:DIGITAL_POLICY_FRAMEWORK_DPF_REFERENCE AS dpf,
                   IFF(IS_NULL_VALUE(doc:CONTROL_NUMBER),NULL,NULLIF(TRIM(doc:CONTROL_NUMBER::VARCHAR),'')) AS control_number,
                   IFF(IS_NULL_VALUE(doc:ALLOCATED_CONTROL_ID),NULL,NULLIF(TRIM(doc:ALLOCATED_CONTROL_ID::VARCHAR),'')) AS instance_key
            FROM records WHERE kind = 'ALLOCATION'
        ), owner_keys AS (
            SELECT a.*, AS_OBJECT(first_owner) AS obj,
                   GET(ARRAY_EXCEPT(OBJECT_KEYS(AS_OBJECT(first_owner)),ARRAY_CONSTRUCT('ContentId')),0)::VARCHAR AS display_key
            FROM allocation_fields a
        ), owner_projection AS (
            SELECT a.*, GET(obj,display_key) AS display_value,
                   IFF(ARRAY_SIZE(OBJECT_KEYS(obj)) = 2
                       AND TYPEOF(GET(obj,'ContentId')) IN ('INTEGER','DECIMAL')
                       AND REGEXP_LIKE(GET(obj,'ContentId')::VARCHAR,'[1-9][0-9]*')
                       AND REGEXP_LIKE(display_key,'[A-Z][A-Z0-9_]{0,127}')
                       AND display_key NOT IN ('CONTENTID','LEVELID','CONTENT_ID','LEVEL_ID')
                       AND NOT STARTSWITH(display_key,'OSCAL_')
                       AND TYPEOF(display_value) IN ('VARCHAR','INTEGER','DECIMAL','DOUBLE','BOOLEAN','DATE','TIMESTAMP_NTZ')
                       AND OCTET_LENGTH(display_value::VARCHAR) <= 512
                       AND REGEXP_LIKE(display_value::VARCHAR,'.*[^[:space:]].*','s'),
                       GET(obj,'ContentId')::VARCHAR, first_owner::VARCHAR) AS package_id
            FROM owner_keys a
        ), allocations AS (
            SELECT a.*, CASE
                WHEN a.record_status <> 'OK' THEN a.record_status
                WHEN a.owners IS NULL OR IS_NULL_VALUE(a.owners) THEN 'OWNER_MISSING_OR_NULL'
                WHEN NOT IS_ARRAY(a.owners) THEN 'OWNER_NOT_ARRAY'
                WHEN ARRAY_SIZE(AS_ARRAY(a.owners)) = 0 THEN 'OWNER_EMPTY_ARRAY'
                WHEN a.package_id IS NULL OR NOT REGEXP_LIKE(a.package_id,'[1-9][0-9]*') THEN 'OWNER_FIRST_ITEM_UNUSABLE'
                WHEN p.id IS NULL THEN 'PACKAGE_ID_NOT_IN_RAW'
                WHEN p.record_status <> 'OK' THEN 'PACKAGE_' || p.record_status
                ELSE 'OWNER_MATCHED' END AS owner_status
            FROM owner_projection a LEFT JOIN records p ON p.kind = 'PACKAGE' AND p.id = a.package_id
        ), members AS (
            SELECT a.*, f.value AS member,
                   IFF(IS_OBJECT(f.value), GET(AS_OBJECT(f.value),'ContentId'), f.value) AS target,
                   GET(AS_OBJECT(f.value),'LevelId') AS declared_level,
                   GET(AS_OBJECT(f.value),'ModuleId') AS declared_module
            FROM allocations a,
                 LATERAL FLATTEN(INPUT => TO_ARRAY(a.dpf), OUTER => TRUE) f
        ), targets AS (
            SELECT m.*, IFF(TYPEOF(target) IN ('INTEGER','DECIMAL','VARCHAR')
                         AND REGEXP_LIKE(target::VARCHAR,'[1-9][0-9]*'),target::VARCHAR,NULL) AS standard_id
            FROM members m
        ), raw_links AS (
            SELECT t.*, CASE
                WHEN t.record_status <> 'OK' THEN t.record_status
                WHEN t.dpf IS NULL OR IS_NULL_VALUE(t.dpf) THEN 'DPF_MISSING_OR_NULL'
                WHEN IS_ARRAY(t.dpf) AND ARRAY_SIZE(AS_ARRAY(t.dpf)) = 0 THEN 'DPF_EMPTY_ARRAY'
                WHEN t.standard_id IS NULL THEN 'DPF_MEMBER_ID_UNUSABLE'
                WHEN t.declared_level IS NOT NULL AND t.declared_level::VARCHAR IS DISTINCT FROM '41' THEN 'DPF_LEVEL_CONFLICT'
                WHEN t.declared_module IS NOT NULL AND t.declared_module::VARCHAR IS DISTINCT FROM '66' THEN 'DPF_MODULE_CONFLICT'
                WHEN s.id IS NULL THEN 'STANDARD_ID_NOT_IN_RAW'
                WHEN s.record_status <> 'OK' THEN 'STANDARD_' || s.record_status
                ELSE 'STANDARD_MATCHED' END AS standard_status
            FROM targets t LEFT JOIN records s ON s.kind = 'STANDARD' AND s.id = t.standard_id
        ), saved_ssp AS (
            SELECT SOURCE_RECORD_ID::VARCHAR AS package_id, ELEMENT_TYPE, TRY_PARSE_JSON(METADATA_JSON::VARCHAR) AS doc
            FROM DIM_OSCAL_SSP_ELEMENT
            WHERE ELEMENT_TYPE IN ('system-security-plan','implemented-requirements')
              AND SOURCE_SYSTEM_NAME = 'ARCHER' AND SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW'
        ), saved_refs AS (
            SELECT s.package_id, p.value:name::VARCHAR AS property_name,
                   TRY_PARSE_JSON(p.value:value::VARCHAR) AS refs
            FROM saved_ssp s, LATERAL FLATTEN(INPUT => s.doc:props, OUTER => TRUE) p
            WHERE s.ELEMENT_TYPE = 'implemented-requirements'
        ), saved_pairs AS (
            SELECT DISTINCT s.package_id, f.value:ContentId::VARCHAR AS standard_id
            FROM saved_refs s, LATERAL FLATTEN(INPUT => s.refs) f
            WHERE s.property_name = 'archer-control-standard-reference' AND f.value:ContentId::VARCHAR IS NOT NULL
        ), raw_pairs AS (
            SELECT DISTINCT package_id, standard_id FROM raw_links
            WHERE owner_status = 'OWNER_MATCHED' AND standard_status = 'STANDARD_MATCHED'
        ), memberships AS (
            SELECT 'PACKAGE_ID' AS grain, id AS package_id, NULL::VARCHAR AS standard_id, 'RAW' AS side
            FROM records WHERE kind = 'PACKAGE' AND id IS NOT NULL
            UNION ALL SELECT DISTINCT 'PACKAGE_ID', package_id, NULL, 'SAVED'
            FROM saved_ssp WHERE ELEMENT_TYPE = 'system-security-plan' AND package_id IS NOT NULL
            UNION ALL SELECT DISTINCT 'STANDARD_ID', NULL, standard_id, 'RAW' FROM raw_pairs
            UNION ALL SELECT DISTINCT 'STANDARD_ID', NULL, standard_id, 'SAVED' FROM saved_pairs
            UNION ALL SELECT 'PACKAGE_STANDARD_PAIR', package_id, standard_id, 'RAW' FROM raw_pairs
            UNION ALL SELECT 'PACKAGE_STANDARD_PAIR', package_id, standard_id, 'SAVED' FROM saved_pairs
        ), compared AS (
            SELECT grain, package_id, standard_id, CASE WHEN COUNT(DISTINCT side) = 2 THEN 'BOTH'
                   WHEN MIN(side) = 'RAW' THEN 'RAW_ONLY' ELSE 'SAVED_ONLY' END AS status
            FROM memberships GROUP BY grain, package_id, standard_id
        ), reported_counts AS (
            SELECT g.grain, x.status, COUNT(c.status) AS row_count
            FROM (SELECT column1 AS grain FROM VALUES ('PACKAGE_ID'),('STANDARD_ID'),('PACKAGE_STANDARD_PAIR')) g
            CROSS JOIN (SELECT column1 AS status FROM VALUES ('BOTH'),('RAW_ONLY'),('SAVED_ONLY')) x
            LEFT JOIN compared c ON c.grain = g.grain AND c.status = x.status GROUP BY g.grain,x.status
        ), report AS (
            SELECT '01_COMPARISON_COUNTS' AS section, grain AS item, status,
                   NULL::VARCHAR AS package_id, NULL::VARCHAR AS allocation_id, NULL::VARCHAR AS standard_id,
                   row_count, NULL::VARIANT AS detail FROM reported_counts
            UNION ALL
            SELECT '02_RAW_INPUTS', kind, record_status, NULL,NULL,NULL,COUNT(*),
                   OBJECT_CONSTRUCT('physical_rows',SUM(stored_rows),'non_null_unique_ids',COUNT(id))
            FROM records GROUP BY kind,record_status
            UNION ALL
            SELECT '02_RAW_INPUTS','PACKAGE_FORWARD_FIELDS','POPULATED_SOURCE_FIELDS',NULL,NULL,NULL,COUNT(*),
                   OBJECT_CONSTRUCT('packages_with_control_standards',
                       COUNT(IFF(doc:CONTROL_STANDARDS IS NOT NULL AND NOT IS_NULL_VALUE(doc:CONTROL_STANDARDS)
                                 AND COALESCE(ARRAY_SIZE(AS_ARRAY(doc:CONTROL_STANDARDS)),1) > 0,1,NULL)),
                       'packages_with_allocated_controls',
                       COUNT(IFF(doc:ALLOCATED_CONTROLS IS NOT NULL AND NOT IS_NULL_VALUE(doc:ALLOCATED_CONTROLS)
                                 AND COALESCE(ARRAY_SIZE(AS_ARRAY(doc:ALLOCATED_CONTROLS)),1) > 0,1,NULL)))
            FROM records WHERE kind = 'PACKAGE' AND record_status = 'OK'
            UNION ALL
            SELECT '03_ALLOCATION_FIELDS','ALL_ALLOCATIONS','PROFILE',NULL,NULL,NULL,COUNT(*),
                   OBJECT_CONSTRUCT('readable_unique_allocations',COALESCE(COUNT_IF(record_status = 'OK'),0),
                   'populated_owner_arrays',COALESCE(COUNT_IF(ARRAY_SIZE(AS_ARRAY(owners)) > 0),0),
                   'owner_first_scalar',COALESCE(COUNT_IF(TYPEOF(first_owner) IN ('INTEGER','DECIMAL','VARCHAR')),0),
                   'owner_first_object',COALESCE(COUNT_IF(IS_OBJECT(first_owner)),0),
                   'multiple_owner_members',COALESCE(COUNT_IF(ARRAY_SIZE(AS_ARRAY(owners)) > 1),0),
                   'raw_owners_matched',COALESCE(COUNT_IF(owner_status = 'OWNER_MATCHED'),0),
                   'raw_owners_matched_if_object_ContentId_only',COALESCE(COUNT_IF(owner_status = 'OWNER_MATCHED' AND GET(obj,'ContentId')::VARCHAR = package_id),0),
                   'populated_DPF_fields',COALESCE(COUNT_IF(dpf IS NOT NULL AND NOT IS_NULL_VALUE(dpf) AND COALESCE(ARRAY_SIZE(AS_ARRAY(dpf)),1) > 0),0),
                   'DPF_with_matched_owner',COALESCE(COUNT_IF(owner_status = 'OWNER_MATCHED' AND dpf IS NOT NULL AND NOT IS_NULL_VALUE(dpf) AND COALESCE(ARRAY_SIZE(AS_ARRAY(dpf)),1) > 0),0))
            FROM allocations
            UNION ALL
            SELECT '04_FIELD_SHAPES','OWNER_FIRST_AND_DPF','BY_ALLOCATION',NULL,NULL,NULL,COUNT(*),
                   OBJECT_CONSTRUCT_KEEP_NULL('owner_field_type',TYPEOF(owners),'owner_first_type',TYPEOF(first_owner),'dpf_field_type',TYPEOF(dpf))
            FROM allocations GROUP BY TYPEOF(owners),TYPEOF(first_owner),TYPEOF(dpf)
            UNION ALL
            SELECT '05_RAW_LINK_STATUS',owner_status,standard_status,NULL,NULL,NULL,COUNT(*),
                   OBJECT_CONSTRUCT('distinct_allocations',COUNT(DISTINCT allocation_id),
                   'without_control_number',COUNT(DISTINCT IFF(control_number IS NULL,allocation_id,NULL)),
                   'without_allocated_control_id',COUNT(DISTINCT IFF(instance_key IS NULL,allocation_id,NULL)))
            FROM raw_links GROUP BY owner_status,standard_status
            UNION ALL
            SELECT '06_SAVED_INPUTS','SOURCE_ONE_SSP',ELEMENT_TYPE,NULL,NULL,NULL,COUNT(*),
                   OBJECT_CONSTRUCT('distinct_packages',COUNT(DISTINCT package_id),
                   'unreadable_or_empty_doc',COALESCE(COUNT_IF(NOT COALESCE(IS_OBJECT(doc),FALSE) OR TO_JSON(doc)='{}'),0))
            FROM saved_ssp GROUP BY ELEMENT_TYPE
            UNION ALL
            SELECT '06_SAVED_INPUTS','DPF_PROPERTY','MATCHED_PROPERTY',NULL,NULL,NULL,COUNT(*),
                   OBJECT_CONSTRUCT('field_missing_or_unparseable',COALESCE(COUNT_IF(refs IS NULL OR IS_NULL_VALUE(refs)),0),
                   'field_is_array',COALESCE(COUNT_IF(IS_ARRAY(refs)),0))
            FROM saved_refs WHERE property_name = 'archer-control-standard-reference'
            UNION ALL
            SELECT DISTINCT '07_RAW_EXCEPTIONS',owner_status,standard_status,
                   IFF(REGEXP_LIKE(package_id,'[1-9][0-9]*'),package_id,NULL),allocation_id,standard_id,NULL,
                   OBJECT_CONSTRUCT_KEEP_NULL('owner_first_type',TYPEOF(first_owner),'DPF_member_type',TYPEOF(member),
                      'control_number_present',control_number IS NOT NULL,'allocation_instance_key_present',instance_key IS NOT NULL)
            FROM raw_links
            WHERE owner_status NOT IN ('OWNER_MATCHED','OWNER_MISSING_OR_NULL','OWNER_EMPTY_ARRAY')
               OR standard_status NOT IN ('STANDARD_MATCHED','DPF_MISSING_OR_NULL','DPF_EMPTY_ARRAY')
               OR (owner_status = 'OWNER_MATCHED' AND standard_status = 'STANDARD_MATCHED'
                   AND (control_number IS NULL OR instance_key IS NULL))
            UNION ALL
            SELECT '08_IDS',grain,status,package_id,NULL,standard_id,NULL,NULL FROM compared
        )
        SELECT section, item, status, package_id, allocation_id, standard_id, row_count, detail
        FROM report
        ORDER BY section,item,status,package_id,allocation_id,standard_id
    );
    RETURN TABLE(rows_out);
END;
$$;

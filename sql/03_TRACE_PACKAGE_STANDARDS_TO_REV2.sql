-- Step 3. Run the entire block from the same DEV curated worksheet as Steps 1 and 2.
-- This read-only block locates the DEV Archer RAW schema and checks the exact publication title.
-- Read the first SUMMARY row for the full SSP population. Counts of standards and
-- counts of distinct standard/subsection pairs answer different questions. Incomplete
-- paths and missing metadata remain visible in STANDARD and REFERENCE rows.
EXECUTE IMMEDIATE $$
DECLARE
    raw_namespace VARCHAR;
    inventory_id VARCHAR;
    selection_error EXCEPTION (-20031, 'Expected one visible DEV schema with all required Archer RAW tables. Check your DEV role and database access.');
    field_table VARCHAR;
    control_standards_raw_table VARCHAR;
    sub_section_raw_table VARCHAR;
    section_raw_table VARCHAR;
    topic_raw_table VARCHAR;
    source_raw_table VARCHAR;
    content_table VARCHAR;
    level_table VARCHAR;
    report_rows RESULTSET;
BEGIN
    SHOW TERSE OBJECTS IN ACCOUNT STARTS WITH 'ARCHER_';
    inventory_id := SQLID;
    SELECT IFF(COUNT(*) = 1, MIN(qualified_namespace), NULL) INTO :raw_namespace
    FROM (
        SELECT '"' || REPLACE("database_name", '"', '""') || '"."' ||
               REPLACE("schema_name", '"', '""') || '"' AS qualified_namespace
        FROM TABLE(RESULT_SCAN(:inventory_id))
        WHERE "kind" IN ('TABLE', 'VIEW') AND ENDSWITH(UPPER("database_name"), '_DEV')
          AND "name" IN (
              'ARCHER_META_FIELD',
              'ARCHER_CONTENT_CONTROL_STANDARDS_RAW',
              'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SUB_SECTION_RAW',
              'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SECTION_RAW',
              'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_TOPIC_RAW',
              'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW',
              'ARCHER_META_CONTENT',
              'ARCHER_META_LEVEL'
          )
        GROUP BY "database_name", "schema_name"
        HAVING COUNT(DISTINCT "name") = 8
    ) AS matching_schemas;
    IF (raw_namespace IS NULL) THEN
        RAISE selection_error;
    END IF;
    field_table := raw_namespace || '.ARCHER_META_FIELD';
    control_standards_raw_table := raw_namespace || '.ARCHER_CONTENT_CONTROL_STANDARDS_RAW';
    sub_section_raw_table := raw_namespace || '.ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SUB_SECTION_RAW';
    section_raw_table := raw_namespace || '.ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SECTION_RAW';
    topic_raw_table := raw_namespace || '.ARCHER_CONTENT_AUTHORITATIVE_SOURCES_TOPIC_RAW';
    source_raw_table := raw_namespace || '.ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW';
    content_table := raw_namespace || '.ARCHER_META_CONTENT';
    level_table := raw_namespace || '.ARCHER_META_LEVEL';
    report_rows := (
        WITH package_standards AS (
            SELECT DISTINCT ref.value:ContentId::VARCHAR AS standard_id
            FROM DIM_OSCAL_SSP_ELEMENT ssp,
                 LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(ssp.METADATA_JSON::VARCHAR):props) prop,
                 LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(prop.value:value::VARCHAR)) ref
            WHERE ssp.ELEMENT_TYPE = 'implemented-requirements'
              AND prop.value:name::VARCHAR = 'archer-control-standard-reference'
              AND ref.value:ContentId::VARCHAR IS NOT NULL
        ), field_specs (child_level, child_module, field_name, expected_field_id, parent_level, parent_module) AS (
            SELECT * FROM VALUES
                (41, 66, 'AUTHORITATIVE_SOURCES', 89, 9, 67),
                (9, 67, 'SECTION_REFERENCES', NULL, 8, 67),
                (8, 67, 'TOPIC_REFERENCES', NULL, 7, 67),
                (7, 67, 'SOURCE_REFERENCES', NULL, 6, 67)
        ), field_metadata AS (
            SELECT s.*, COUNT(f.LEVEL_ID) AS field_matches, MIN(f.FIELD_ID) AS field_id,
                   MIN(f.MODULE_ID) AS field_module, MIN(f.FIELD_TYPE_ID) AS field_type,
                   MIN(f.SQL_FIELD_NAME) AS metadata_name
            FROM field_specs s
            LEFT JOIN IDENTIFIER(:field_table) f ON f.LEVEL_ID = s.child_level
               AND (f.SQL_FIELD_NAME = s.field_name OR f.FIELD_ID = s.expected_field_id)
            GROUP BY s.child_level, s.child_module, s.field_name, s.expected_field_id, s.parent_level, s.parent_module
        ), field_checks AS (
            SELECT *, CASE WHEN field_matches = 0 THEN 'FIELD_METADATA_MISSING'
                           WHEN field_matches <> 1 THEN 'FIELD_METADATA_AMBIGUOUS'
                           WHEN metadata_name IS DISTINCT FROM field_name OR field_id IS NULL
                             OR (expected_field_id IS NOT NULL AND field_id <> expected_field_id)
                             THEN 'FIELD_ID_OR_NAME_MISMATCH'
                           WHEN field_module IS DISTINCT FROM child_module THEN 'FIELD_MODULE_MISMATCH'
                           WHEN field_type IS NULL OR field_type NOT IN (9, 23)
                             OR (child_level = 41 AND field_type <> 9) THEN 'FIELD_TYPE_MISMATCH'
                           ELSE 'FIELD_VERIFIED' END AS field_status
            FROM field_metadata
        ), raw_inputs AS (
            SELECT 41 AS raw_level, 66 AS raw_module, CONTENT_ID::VARCHAR AS content_id, CURATED_JSON AS value
            FROM IDENTIFIER(:control_standards_raw_table)
            UNION ALL
            SELECT 9, 67, CONTENT_ID::VARCHAR, CURATED_JSON
            FROM IDENTIFIER(:sub_section_raw_table)
            UNION ALL
            SELECT 8, 67, CONTENT_ID::VARCHAR, CURATED_JSON
            FROM IDENTIFIER(:section_raw_table)
            UNION ALL
            SELECT 7, 67, CONTENT_ID::VARCHAR, CURATED_JSON
            FROM IDENTIFIER(:topic_raw_table)
            UNION ALL
            SELECT 6, 67, CONTENT_ID::VARCHAR, CURATED_JSON
            FROM IDENTIFIER(:source_raw_table)
        ), raw_rows AS (
            SELECT raw_level, raw_module, content_id,
                   IFF(IS_OBJECT(value), value, TRY_PARSE_JSON(value::VARCHAR)) AS doc
            FROM raw_inputs
        ), raw_by_id AS (
            SELECT raw_level, raw_module, content_id, COUNT(*) AS raw_matches,
                   IFF(COUNT(*) = 1, ANY_VALUE(doc), NULL) AS doc
            FROM raw_rows GROUP BY raw_level, raw_module, content_id
        ), content_metadata AS (
            SELECT CONTENT_ID::VARCHAR AS content_id, COUNT(*) AS metadata_matches,
                   IFF(COUNT(*) = 1, MIN(LEVEL_ID), NULL) AS metadata_level
            FROM IDENTIFIER(:content_table) GROUP BY CONTENT_ID::VARCHAR
        ), level_metadata AS (
            SELECT LEVEL_ID AS level_id, COUNT(*) AS level_matches, MIN(MODULE_ID) AS module_id
            FROM IDENTIFIER(:level_table) GROUP BY LEVEL_ID
        ), records AS (
            SELECT r.*, CASE
                WHEN NOT COALESCE(REGEXP_LIKE(r.content_id, '[1-9][0-9]*'), FALSE) THEN 'INVALID_RAW_ID'
                WHEN r.raw_matches <> 1 THEN 'RAW_ROWS_AMBIGUOUS'
                WHEN NOT COALESCE(IS_OBJECT(r.doc), FALSE) THEN 'RAW_OBJECT_MISSING'
                WHEN c.metadata_matches IS NULL THEN 'CONTENT_METADATA_MISSING'
                WHEN c.metadata_matches <> 1 THEN 'CONTENT_METADATA_AMBIGUOUS'
                WHEN c.metadata_level IS DISTINCT FROM r.raw_level THEN 'CONTENT_LEVEL_MISMATCH'
                WHEN l.level_matches IS NULL THEN 'LEVEL_METADATA_MISSING'
                WHEN l.level_matches <> 1 THEN 'LEVEL_METADATA_AMBIGUOUS'
                WHEN l.module_id IS DISTINCT FROM r.raw_module THEN 'LEVEL_MODULE_MISMATCH'
                ELSE 'RECORD_VERIFIED' END AS record_status
            FROM raw_by_id r
            LEFT JOIN content_metadata c ON c.content_id = r.content_id
            LEFT JOIN level_metadata l ON l.level_id = r.raw_level
        ), root_check AS (
            SELECT MAX(content_id) AS rev2_id,
                   IFF(COUNT(*) = 1 AND MAX(IFF(record_status = 'RECORD_VERIFIED', 1, 0)) = 1, 1, 0) AS verified
            FROM records WHERE raw_level = 6
              AND TRIM(REGEXP_REPLACE(UPPER(doc:SOURCE_NAME::VARCHAR), '[[:space:]]+', ' '))
                  = 'NIST SP 800-171 REVISION 2 (FEBRUARY 2020)'
        ), standards AS (
            SELECT p.standard_id, r.doc:CONTROL_STANDARD_NAME::VARCHAR AS standard_name,
                   COALESCE(r.record_status, 'STANDARD_MISSING_IN_RAW') AS record_status,
                   CASE WHEN r.record_status = 'RECORD_VERIFIED' THEN
                       CONTAINS(UPPER(COALESCE(r.doc:STANDARD_ID::VARCHAR, '')), 'ATCS')
                       OR CONTAINS(UPPER(COALESCE(r.doc:CONTROL_STANDARD_NAME::VARCHAR, '')), 'ATCS')
                   END AS atcs_in_id_or_name
            FROM package_standards p LEFT JOIN records r
              ON r.raw_level = 41 AND r.content_id = p.standard_id
        ), source_fields AS (
            SELECT f.*, r.content_id AS child_id, GET(AS_OBJECT(r.doc), f.field_name) AS refs
            FROM field_checks f JOIN records r ON r.raw_level = f.child_level
            WHERE r.record_status = 'RECORD_VERIFIED'
              AND (f.child_level <> 41 OR r.content_id IN (SELECT standard_id FROM package_standards))
        ), field_values AS (
            SELECT *, CASE WHEN field_status <> 'FIELD_VERIFIED' THEN field_status
                WHEN refs IS NULL OR IS_NULL_VALUE(refs) THEN 'FIELD_ABSENT_OR_NULL'
                WHEN child_level = 41 AND IS_OBJECT(refs) THEN 'MEMBERS_READY'
                WHEN NOT COALESCE(IS_ARRAY(refs), FALSE) THEN 'FIELD_NOT_ARRAY'
                WHEN ARRAY_SIZE(AS_ARRAY(refs)) = 0 THEN 'FIELD_EMPTY_ARRAY'
                WHEN child_level <> 41 AND ARRAY_SIZE(AS_ARRAY(refs)) <> 1 THEN 'PARENT_ARRAY_NOT_SINGLETON'
                ELSE 'MEMBERS_READY' END AS value_status
            FROM source_fields
        ), ref_values AS (
            SELECT v.*, IFF(IS_OBJECT(a.value), GET(AS_OBJECT(a.value), 'ContentId'), a.value) AS id_value,
                   GET(AS_OBJECT(a.value), 'LevelId') AS level_value,
                   GET(AS_OBJECT(a.value), 'ModuleId') AS module_value
            FROM field_values v, LATERAL FLATTEN(INPUT => IFF(v.value_status = 'MEMBERS_READY', TO_ARRAY(v.refs), NULL), OUTER => TRUE) a
        ), refs AS (
            SELECT *, IFF(TYPEOF(id_value) IN ('INTEGER', 'VARCHAR') AND REGEXP_LIKE(TRIM(id_value::VARCHAR), '[1-9][0-9]*'),
                           TRIM(id_value::VARCHAR), NULL) AS parent_id,
                   IFF(TYPEOF(level_value) IN ('INTEGER', 'VARCHAR') AND REGEXP_LIKE(TRIM(level_value::VARCHAR), '[1-9][0-9]*'),
                           TRY_TO_NUMBER(TRIM(level_value::VARCHAR)), NULL) AS declared_level,
                   IFF(TYPEOF(module_value) IN ('INTEGER', 'VARCHAR') AND REGEXP_LIKE(TRIM(module_value::VARCHAR), '[1-9][0-9]*'),
                           TRY_TO_NUMBER(TRIM(module_value::VARCHAR)), NULL) AS declared_module
            FROM ref_values
        ), ref_checks AS (
            SELECT a.child_level, a.child_id, a.field_name, a.parent_id, a.value_status, CASE
                WHEN a.value_status <> 'MEMBERS_READY' THEN a.value_status
                WHEN a.parent_id IS NULL THEN 'INVALID_REFERENCE_ID'
                WHEN a.level_value IS NOT NULL AND a.declared_level IS NULL THEN 'INVALID_DECLARED_LEVEL'
                WHEN a.module_value IS NOT NULL AND a.declared_module IS NULL THEN 'INVALID_DECLARED_MODULE'
                WHEN c.metadata_matches IS NULL THEN 'TARGET_CONTENT_METADATA_MISSING'
                WHEN c.metadata_matches <> 1 THEN 'TARGET_CONTENT_METADATA_AMBIGUOUS'
                WHEN c.metadata_level IS NULL OR c.metadata_level <= 0 THEN 'TARGET_CONTENT_LEVEL_INVALID'
                WHEN a.declared_level IS NOT NULL AND a.declared_level <> c.metadata_level THEN 'DECLARED_LEVEL_MISMATCH'
                WHEN l.level_matches IS NULL THEN 'TARGET_LEVEL_METADATA_MISSING'
                WHEN l.level_matches <> 1 THEN 'TARGET_LEVEL_METADATA_AMBIGUOUS'
                WHEN l.module_id IS NULL OR l.module_id <= 0 THEN 'TARGET_MODULE_INVALID'
                WHEN a.declared_module IS NOT NULL AND a.declared_module <> l.module_id THEN 'DECLARED_MODULE_MISMATCH'
                WHEN c.metadata_level <> a.parent_level AND a.child_level = 41 THEN 'OUTSIDE_SUBSECTION_LEVEL'
                WHEN c.metadata_level <> a.parent_level THEN 'PARENT_LEVEL_MISMATCH'
                WHEN l.module_id <> a.parent_module THEN 'TARGET_MODULE_MISMATCH'
                WHEN r.content_id IS NULL THEN 'TARGET_RAW_ROW_MISSING'
                WHEN r.record_status <> 'RECORD_VERIFIED' THEN r.record_status
                ELSE 'REFERENCE_VERIFIED' END AS reference_status
            FROM refs a
            LEFT JOIN content_metadata c ON c.content_id = a.parent_id
            LEFT JOIN level_metadata l ON l.level_id = c.metadata_level
            LEFT JOIN records r ON r.raw_level = a.parent_level AND r.content_id = a.parent_id
        ), standard_links AS (
            SELECT child_id AS standard_id, parent_id AS subsection_id,
                   COALESCE(COUNT_IF(value_status = 'MEMBERS_READY'), 0) AS link_rows,
                   IFF(COUNT(DISTINCT reference_status) = 1, MIN(reference_status), 'CONFLICTING_REFERENCE_MEMBERS') AS link_status
            FROM ref_checks WHERE child_level = 41 GROUP BY child_id, parent_id
        ), paths AS (
            SELECT s.standard_id, s.standard_name, s.atcs_in_id_or_name, d.subsection_id,
                   sec.parent_id AS section_id, top.parent_id AS topic_id, pub.parent_id AS source_id,
                   CASE WHEN s.record_status <> 'RECORD_VERIFIED' THEN s.record_status
                        WHEN d.link_status IN ('FIELD_ABSENT_OR_NULL', 'FIELD_EMPTY_ARRAY') THEN 'NO_AUTHORITY_REFERENCE'
                        WHEN d.link_status IS DISTINCT FROM 'REFERENCE_VERIFIED'
                            THEN COALESCE(d.link_status, 'STANDARD_TO_SUBSECTION_UNRESOLVED')
                        WHEN sec.reference_status IS DISTINCT FROM 'REFERENCE_VERIFIED'
                            THEN 'SUBSECTION_TO_SECTION_' || COALESCE(sec.reference_status, 'UNRESOLVED')
                        WHEN top.reference_status IS DISTINCT FROM 'REFERENCE_VERIFIED'
                            THEN 'SECTION_TO_TOPIC_' || COALESCE(top.reference_status, 'UNRESOLVED')
                        WHEN pub.reference_status IS DISTINCT FROM 'REFERENCE_VERIFIED'
                            THEN 'TOPIC_TO_SOURCE_' || COALESCE(pub.reference_status, 'UNRESOLVED')
                        WHEN rc.verified = 0 THEN 'REV2_ROOT_UNVERIFIED'
                        WHEN pub.parent_id = rc.rev2_id THEN 'REV2_SUBSECTION'
                        ELSE 'OTHER_VERIFIED_SOURCE' END AS path_status
            FROM standards s CROSS JOIN root_check rc
            LEFT JOIN standard_links d ON s.standard_id = d.standard_id
            LEFT JOIN ref_checks sec ON d.link_status = 'REFERENCE_VERIFIED'
                 AND sec.child_level = 9 AND sec.child_id = d.subsection_id
            LEFT JOIN ref_checks top ON sec.reference_status = 'REFERENCE_VERIFIED'
                 AND top.child_level = 8 AND top.child_id = sec.parent_id
            LEFT JOIN ref_checks pub ON top.reference_status = 'REFERENCE_VERIFIED'
                 AND pub.child_level = 7 AND pub.child_id = top.parent_id
        ), per_standard AS (
            SELECT standard_id, standard_name, atcs_in_id_or_name,
                   COUNT(DISTINCT IFF(path_status = 'REV2_SUBSECTION', subsection_id, NULL)) AS rev2_pairs,
                   COALESCE(COUNT_IF(path_status NOT IN ('REV2_SUBSECTION','OTHER_VERIFIED_SOURCE','NO_AUTHORITY_REFERENCE')), 0) > 0 AS has_unresolved,
                   MAX(IFF(path_status = 'NO_AUTHORITY_REFERENCE', 1, 0)) AS no_reference
            FROM paths GROUP BY standard_id, standard_name, atcs_in_id_or_name
        ), verdicts AS (
            SELECT *, CASE WHEN rev2_pairs > 0 THEN 'CONFIRMED_REV2'
                           WHEN has_unresolved THEN 'UNRESOLVED'
                           WHEN no_reference = 1 THEN 'NO_AUTHORITY_REFERENCE'
                           ELSE 'OTHER_SOURCES_ONLY' END AS verdict
            FROM per_standard
        ), scopes AS (
            SELECT column1 AS scope FROM VALUES ('01_ALL_PACKAGE_STANDARDS'), ('02_EXCLUDE_ATCS_IN_STANDARD_ID_OR_NAME')
        ), report AS (
            SELECT 'SUMMARY' AS row_type, s.scope AS result, NULL::VARCHAR AS standard_id,
                   NULL::VARCHAR AS standard_name, NULL::VARCHAR AS subsection_id, NULL::VARCHAR AS section_id,
                   NULL::VARCHAR AS topic_id, NULL::VARCHAR AS source_id, NULL::BOOLEAN AS atcs_in_id_or_name,
                   COUNT(v.standard_id) AS distinct_standards,
                   COALESCE(COUNT_IF(v.rev2_pairs > 0), 0) AS confirmed_rev2_standards,
                   COALESCE(SUM(v.rev2_pairs), 0) AS confirmed_rev2_pairs,
                   COALESCE(COUNT_IF(v.verdict = 'NO_AUTHORITY_REFERENCE'), 0) AS no_authority_reference,
                   COALESCE(COUNT_IF(v.verdict = 'OTHER_SOURCES_ONLY'), 0) AS other_sources_only,
                   COALESCE(COUNT_IF(v.verdict = 'UNRESOLVED'), 0) AS unresolved_without_match,
                   COALESCE(COUNT_IF(v.has_unresolved AND v.rev2_pairs > 0), 0) AS matched_with_an_unresolved_path,
                   rc.verified = 1 AS rev2_root_verified
            FROM scopes s CROSS JOIN root_check rc LEFT JOIN verdicts v
              ON s.scope = '01_ALL_PACKAGE_STANDARDS' OR v.atcs_in_id_or_name = FALSE
            GROUP BY s.scope, rc.verified
            UNION ALL
            SELECT 'STANDARD', verdict, standard_id, standard_name, NULL, NULL, NULL, NULL, atcs_in_id_or_name,
                   NULL, NULL, rev2_pairs, NULL, NULL, NULL, NULL, NULL FROM verdicts
            UNION ALL
            SELECT 'REFERENCE', path_status, standard_id, standard_name, subsection_id, section_id,
                   topic_id, source_id, atcs_in_id_or_name, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL FROM paths
        )
        SELECT * FROM report
        ORDER BY CASE row_type WHEN 'SUMMARY' THEN 0 WHEN 'STANDARD' THEN 1 ELSE 2 END,
                 IFF(row_type = 'SUMMARY', result, NULL), standard_id, subsection_id, source_id
    );
    RETURN TABLE(report_rows);
END;
$$;

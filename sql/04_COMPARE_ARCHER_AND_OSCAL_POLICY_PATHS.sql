-- Step 4. One row for Josh's 98 package standards with no saved Level 3 policy path.
-- Run the complete block in the same DEV curated worksheet as Query 1.
-- RAW_L2 counts standards with a direct Level 2 policy in Archer RAW.
-- CHANGED_L2 counts standards where the raw and saved Level 2 policy IDs differ.
-- RAW_L3 counts standards reaching Level 3 directly or through one referring standard.
-- SOURCE_CHECK flags a changed population, incomplete coverage, or another Level 3 reference.
EXECUTE IMMEDIATE $$
DECLARE
    raw_ns VARCHAR;
    inventory_id VARCHAR;
    scope_error EXCEPTION (-20031, 'Expected one visible DEV Archer RAW schema with all required tables. Check worksheet role and DEV access.');
    tbl_control_standards_raw VARCHAR;
    tbl_policies_policy_level_1_raw VARCHAR;
    tbl_policies_policy_level_2_raw VARCHAR;
    tbl_policies_policy_level_3_raw VARCHAR;
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
              'ARCHER_CONTENT_CONTROL_STANDARDS_RAW',
              'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_1_RAW',
              'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW',
              'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW'
          )
        GROUP BY "database_name", "schema_name"
        HAVING COUNT(DISTINCT "name") = 4
    ) candidates;
    IF (raw_ns IS NULL) THEN
        RAISE scope_error;
    END IF;
    tbl_control_standards_raw := raw_ns || '.ARCHER_CONTENT_CONTROL_STANDARDS_RAW';
    tbl_policies_policy_level_1_raw := raw_ns || '.ARCHER_CONTENT_POLICIES_POLICY_LEVEL_1_RAW';
    tbl_policies_policy_level_2_raw := raw_ns || '.ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW';
    tbl_policies_policy_level_3_raw := raw_ns || '.ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW';
    rows_out := (
        WITH package_standards AS (
            SELECT DISTINCT r.value:ContentId::VARCHAR AS standard_id
            FROM DIM_OSCAL_SSP_ELEMENT s,
                 LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(s.metadata_json::VARCHAR):props) p,
                 LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(p.value:value::VARCHAR)) r
            WHERE s.element_type = 'implemented-requirements'
              AND p.value:name::VARCHAR = 'archer-control-standard-reference'
              AND r.value:ContentId::VARCHAR IS NOT NULL
        ), saved_controls AS (
            SELECT source_table_name, source_record_id::VARCHAR AS root_id,
                   TRY_PARSE_JSON(metadata_json::VARCHAR) AS doc
            FROM DIM_OSCAL_CATALOG_ELEMENT
            WHERE element_type = 'controls'
        ), identified AS (
            SELECT c.*, p.value:value::VARCHAR AS standard_id
            FROM saved_controls c, LATERAL FLATTEN(INPUT => c.doc:props) p
            WHERE p.value:name::VARCHAR = 'archer-content-id'
        ), saved_edge_properties AS (
            SELECT c.standard_id AS via_id, TRY_PARSE_JSON(p.value:value::VARCHAR) AS refs
            FROM identified c, LATERAL FLATTEN(INPUT => c.doc:props) p
            WHERE p.value:name::VARCHAR = 'control-standards-related-control-requirements'
        ), saved_edges AS (
            -- Reproduce Step 2 exactly, including its JSON member selection and edge direction.
            SELECT DISTINCT r.value:ContentId::VARCHAR AS standard_id, c.via_id
            FROM saved_edge_properties c, LATERAL FLATTEN(INPUT => c.refs) r
            WHERE c.via_id <> r.value:ContentId::VARCHAR
        ), saved_normalized_members AS (
            SELECT c.via_id, IFF(IS_OBJECT(r.value), GET(AS_OBJECT(r.value),'ContentId'), r.value)::VARCHAR AS target_id
            FROM saved_edge_properties c, LATERAL FLATTEN(INPUT => TO_ARRAY(c.refs)) r
            WHERE COALESCE(GET(AS_OBJECT(r.value),'LevelId')::VARCHAR, '41') = '41'
              AND COALESCE(GET(AS_OBJECT(r.value),'ModuleId')::VARCHAR, '66') = '66'
        ), saved_additional_edges AS (
            -- If this finds a RAW-only edge, it is present in the saved property in a shape
            -- Step 2 did not extract. Exclude self-links just as Step 2 does.
            SELECT n.target_id AS standard_id, ARRAY_AGG(DISTINCT n.via_id) AS other_shapes
            FROM saved_normalized_members n LEFT JOIN saved_edges e ON e.standard_id = n.target_id AND e.via_id = n.via_id
            WHERE REGEXP_LIKE(n.target_id, '[1-9][0-9]*') AND n.target_id <> n.via_id AND e.via_id IS NULL
            GROUP BY n.target_id
        ), source_rows AS (
            SELECT 'STANDARD' AS kind, content_id::VARCHAR AS id, TRY_PARSE_JSON(curated_json::VARCHAR) AS doc
            FROM IDENTIFIER(:tbl_control_standards_raw)
            UNION ALL
            SELECT 'L1', content_id::VARCHAR, TRY_PARSE_JSON(curated_json::VARCHAR)
            FROM IDENTIFIER(:tbl_policies_policy_level_1_raw)
            UNION ALL
            SELECT 'L2', content_id::VARCHAR, TRY_PARSE_JSON(curated_json::VARCHAR)
            FROM IDENTIFIER(:tbl_policies_policy_level_2_raw)
            UNION ALL
            SELECT 'L3', content_id::VARCHAR, TRY_PARSE_JSON(curated_json::VARCHAR)
            FROM IDENTIFIER(:tbl_policies_policy_level_3_raw)
        ), source_records AS (
            -- Different stored documents for an ID are ambiguous. Never guess the latest version.
            SELECT kind, id, COUNT(*) AS raw_rows,
                   COUNT_IF(IS_OBJECT(doc) AND TO_JSON(doc) <> '{}') AS readable_rows, COUNT(DISTINCT TO_JSON(doc)) AS versions,
                   ANY_VALUE(doc) AS doc
            FROM source_rows GROUP BY kind, id
        ), readable AS (
            SELECT kind, id, doc FROM source_records
            WHERE id IS NOT NULL AND readable_rows = raw_rows AND versions = 1
        ), aa_parent AS (
            SELECT COUNT(*) AS name_matches, IFF(COUNT(*) = 1, MIN(id), NULL) AS id
            FROM readable
            WHERE kind = 'L2' AND REGEXP_REPLACE(UPPER(doc:POLICY_LEVEL_2_NAME::VARCHAR), '[^A-Z0-9]', '')
                  IN ('AACONTROLSTANDARDS', 'AANDACONTROLSTANDARDS')
        ), field_specs (kind, field_name, meaning, target_level, target_module) AS (
            -- These three policy routes create native controls at their own Catalog root/group.
            -- The Level 3 route uses only CONTROL_STANDARD_REQUIREMENTS for native membership.
            SELECT * FROM VALUES
              ('L1', 'CONTROL_STANDARDS',                        'POLICY_OWNER', 41, 66),
              ('L2', 'CONTROL_STANDARDS',                        'POLICY_OWNER', 41, 66),
              ('L2', 'CONTROL_STANDARD_REQUIREMENTS',            'POLICY_OWNER', 41, 66),
              ('L3', 'CONTROL_STANDARD_REQUIREMENTS',            'POLICY_OWNER', 41, 66),
              ('STANDARD', 'CONTROL_STANDARDS_RELATED_CONTROL_REQUIREMENTS', 'REFERS_TO', 41, 66),
              ('STANDARD', 'POLICY_HIERARCHY_LEVEL_1_2_3',       'EXPLICIT_POLICY', 5, 65)
        ), source_fields AS (
            SELECT r.kind, r.id, s.meaning, s.field_name, s.target_level, s.target_module,
                   GET(r.doc, s.field_name) AS refs
            FROM readable r JOIN field_specs s ON s.kind = r.kind
        ), members AS (
            SELECT f.*, m.value AS member,
                   IFF(IS_OBJECT(m.value), GET(AS_OBJECT(m.value), 'ContentId'), m.value)::VARCHAR AS target_id,
                   GET(AS_OBJECT(m.value), 'LevelId')::VARCHAR AS declared_level,
                   GET(AS_OBJECT(m.value), 'ModuleId')::VARCHAR AS declared_module,
                   ARRAY_EXCEPT(OBJECT_KEYS(AS_OBJECT(m.value)), ARRAY_CONSTRUCT('ContentId','LevelId')) AS extra_keys
            FROM source_fields f, LATERAL FLATTEN(INPUT => TO_ARRAY(f.refs)) m
        ), member_shapes AS (
            SELECT m.*, GET(extra_keys,0)::VARCHAR AS extra_key,
                   GET(AS_OBJECT(member), GET(extra_keys,0)::VARCHAR) AS display_value
            FROM members m
        ), checked_members AS (
            SELECT m.*,
                   COALESCE(REGEXP_LIKE(target_id, '[1-9][0-9]*')
                     AND (declared_level IS NULL OR declared_level = target_level::VARCHAR)
                     AND (declared_module IS NULL OR declared_module = target_module::VARCHAR)
                     AND (meaning <> 'POLICY_OWNER' OR (IS_ARRAY(refs) AND (
                           TYPEOF(member) = 'INTEGER'
                           OR (TYPEOF(GET(AS_OBJECT(member),'ContentId')) IN ('INTEGER','DECIMAL')
                               AND (declared_level IS NULL OR TYPEOF(GET(AS_OBJECT(member),'LevelId')) IN ('INTEGER','DECIMAL'))
                               AND ((ARRAY_SIZE(extra_keys) = 0 AND declared_level IS NOT NULL)
                                   OR (ARRAY_SIZE(extra_keys) = 1 AND REGEXP_LIKE(extra_key,'[A-Z][A-Z0-9_]{0,127}')
                                       AND extra_key NOT IN ('CONTENTID','LEVELID','CONTENT_ID','LEVEL_ID')
                                       AND NOT STARTSWITH(extra_key,'OSCAL_')
                                       AND TYPEOF(display_value) IN ('VARCHAR','BOOLEAN','INTEGER','DECIMAL','DOUBLE')
                                       AND TRIM(display_value::VARCHAR) <> '' AND OCTET_LENGTH(display_value::VARCHAR) <= 512)))
                     ))), FALSE) AS supported
            FROM member_shapes m
        ), usable_targets AS (
            SELECT id FROM readable
            WHERE kind = 'STANDARD' AND TYPEOF(doc:CONTROL_STANDARD_NAME) = 'VARCHAR'
              AND TRIM(doc:CONTROL_STANDARD_NAME::VARCHAR) <> ''
        ), edges AS (
            SELECT 'SAVED' AS side, standard_id, via_id FROM saved_edges
            UNION ALL
            SELECT DISTINCT 'RAW', target_id, id FROM checked_members
            WHERE meaning = 'REFERS_TO' AND supported AND target_id <> id
        ), placements AS (
            SELECT DISTINCT 'SAVED' AS side, standard_id, root_id,
                   CASE source_table_name
                     WHEN 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_1_RAW' THEN 'L1'
                     WHEN 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW' THEN 'L2'
                     WHEN 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW' THEN 'L3' END AS policy_level
            FROM identified
            WHERE source_table_name IN ('ARCHER_CONTENT_POLICIES_POLICY_LEVEL_1_RAW',
                  'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW', 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW')
            UNION ALL
            SELECT DISTINCT 'RAW', m.target_id, m.id, m.kind
            FROM checked_members m JOIN usable_targets t ON t.id = m.target_id
            WHERE m.meaning = 'POLICY_OWNER' AND m.supported
        ), routes AS (
            SELECT x.side, s.standard_id, 'DIRECT' AS route, s.standard_id AS lookup_id
            FROM package_standards s CROSS JOIN (SELECT 'SAVED' AS side UNION ALL SELECT 'RAW') x
            UNION ALL
            SELECT e.side, s.standard_id, 'VIA', e.via_id
            FROM package_standards s JOIN edges e ON e.standard_id = s.standard_id
        ), path_sets AS (
            SELECT r.standard_id, r.side,
                   ARRAY_AGG(DISTINCT IFF(r.route = 'DIRECT' AND p.root_id IS NOT NULL,
                       p.policy_level || ':' || p.root_id, NULL)) AS direct_roots,
                   ARRAY_AGG(DISTINCT IFF(r.route = 'DIRECT' AND p.policy_level = 'L2', p.root_id, NULL)) AS direct_l2,
                   ARRAY_AGG(DISTINCT IFF(r.route = 'DIRECT' AND p.policy_level = 'L3', p.root_id, NULL)) AS direct_l3,
                   ARRAY_AGG(DISTINCT IFF(r.route = 'VIA', r.lookup_id, NULL)) AS referring_ids,
                   ARRAY_AGG(DISTINCT IFF(r.route = 'VIA' AND p.policy_level = 'L3',
                       r.lookup_id || ' -> ' || p.root_id, NULL)) AS via_l3,
                   ARRAY_AGG(DISTINCT IFF(r.route = 'VIA' AND p.policy_level = 'L3' AND TRY_TO_NUMBER(p.root_id) >= 7250000,
                       r.lookup_id || ' -> ' || p.root_id, NULL)) AS cutoff_paths
            FROM routes r
            LEFT JOIN placements p ON p.side = r.side AND p.standard_id = r.lookup_id
            GROUP BY r.standard_id, r.side
        ), explicit_source_l3 AS (
            -- A Standard's explicit policy reference is an independent clue. Confirm the endpoint
            -- in the L3 source table, particularly when the reference has no declared LevelId.
            -- Never treat this reverse-direction field as a native policy-ownership field.
            SELECT m.id AS standard_id, ARRAY_AGG(DISTINCT m.target_id) AS policies
            FROM checked_members m JOIN readable p ON p.kind = 'L3' AND p.id = m.target_id
            WHERE m.meaning = 'EXPLICIT_POLICY' AND m.supported
            GROUP BY m.id
        ), coverage AS (
            SELECT
              (SELECT 4 - COUNT(DISTINCT kind) FROM readable) AS missing_readable_source_tables,
              (SELECT COUNT(*) FROM source_fields WHERE kind = 'L3' AND IS_ARRAY(refs)) AS l3_roots_with_membership_array,
              (SELECT COUNT(*) FROM source_records WHERE id IS NULL OR COALESCE(readable_rows, 0) <> raw_rows OR versions <> 1)
                  AS unreadable_or_ambiguous_raw_records,
              (SELECT COUNT(*) FROM checked_members WHERE NOT supported AND meaning IN ('REFERS_TO','POLICY_OWNER')
                   AND NOT COALESCE(IS_NULL_VALUE(refs), TRUE))
                  AS unsupported_raw_reference_members,
              (SELECT COUNT(DISTINCT m.target_id) FROM checked_members m LEFT JOIN usable_targets t
                   ON t.id = m.target_id
                   WHERE m.meaning = 'POLICY_OWNER' AND m.supported AND t.id IS NULL)
                  AS unresolved_owner_standard_ids
        ), compared AS (
            SELECT s.standard_id,
                   CASE WHEN ARRAY_SIZE(s.direct_l3) = 0 AND ARRAY_SIZE(s.referring_ids) = 0 THEN 'JOSH ORIGINAL GAP'
                        WHEN ARRAY_SIZE(s.cutoff_paths) > 0 THEN 'JOSH UCF RANGE CANDIDATE'
                        ELSE 'OTHER PACKAGE STANDARD' END AS review_scope,
                   CASE WHEN src.id IS NULL THEN 'NO RAW STANDARD ROW'
                        WHEN COALESCE(src.readable_rows, 0) <> src.raw_rows OR src.versions <> 1 THEN 'RAW STANDARD UNVERIFIED'
                        ELSE 'RAW STANDARD READABLE' END AS source_status,
                   s.direct_l3 AS saved_direct_l3, r.direct_l3 AS raw_direct_l3,
                   s.via_l3 AS saved_via_l3, r.via_l3 AS raw_via_l3,
                   s.cutoff_paths AS saved_cutoff_paths, r.cutoff_paths AS raw_cutoff_paths,
                   ARRAY_EXCEPT(r.direct_l3, s.direct_l3) AS raw_only_direct_l3,
                   ARRAY_EXCEPT(s.direct_l3, r.direct_l3) AS saved_only_direct_l3,
                   ARRAY_EXCEPT(r.via_l3, s.via_l3) AS raw_only_via_l3,
                   ARRAY_EXCEPT(s.via_l3, r.via_l3) AS saved_only_via_l3,
                   ARRAY_EXCEPT(r.referring_ids, s.referring_ids) AS raw_only_referring_ids,
                   ARRAY_EXCEPT(s.referring_ids, r.referring_ids) AS saved_only_referring_ids,
                   ARRAY_INTERSECTION(r.referring_ids, COALESCE(a.other_shapes, ARRAY_CONSTRUCT())) AS raw_edges_also_saved_in_other_shapes,
                   s.direct_roots AS saved_direct_policy_roots, r.direct_roots AS raw_direct_policy_roots,
                   s.direct_l2 AS saved_direct_l2, r.direct_l2 AS raw_direct_l2,
                   ARRAY_SIZE(ARRAY_EXCEPT(r.direct_l2,s.direct_l2)) + ARRAY_SIZE(ARRAY_EXCEPT(s.direct_l2,r.direct_l2)) = 0 AS same_observed_l2_ids,
                   aa.name_matches AS aa_parent_name_matches,
                   IFF(aa.id IS NULL, NULL, ARRAY_SIZE(s.direct_roots) = 1 AND ARRAY_CONTAINS(TO_VARIANT('L2:' || aa.id),s.direct_roots)) AS saved_aa_only,
                   IFF(aa.id IS NULL, NULL, ARRAY_SIZE(r.direct_roots) = 1 AND ARRAY_CONTAINS(TO_VARIANT('L2:' || aa.id),r.direct_roots)) AS raw_aa_only_observed,
                   COALESCE(h.policies, ARRAY_CONSTRUCT()) AS explicit_l3_ids_on_raw_standard
            FROM path_sets s JOIN path_sets r ON r.standard_id = s.standard_id AND r.side = 'RAW'
            CROSS JOIN aa_parent aa
            LEFT JOIN source_records src ON src.kind = 'STANDARD' AND src.id = s.standard_id
            LEFT JOIN explicit_source_l3 h ON h.standard_id = s.standard_id
            LEFT JOIN saved_additional_edges a ON a.standard_id = s.standard_id
            WHERE s.side = 'SAVED'
        ), counts AS (
            SELECT COUNT(*) AS package_standards,
                   COALESCE(COUNT_IF(is_gap), 0) AS saved_gaps,
                   COALESCE(COUNT_IF(is_gap AND ARRAY_SIZE(raw_direct_l2) > 0), 0) AS raw_l2,
                   COALESCE(COUNT_IF(is_gap AND NOT same_observed_l2_ids), 0) AS changed_l2,
                   COALESCE(COUNT_IF(is_gap AND ARRAY_SIZE(raw_direct_l3) + ARRAY_SIZE(raw_via_l3) > 0), 0) AS raw_l3,
                   COALESCE(COUNT_IF(is_gap AND source_status <> 'RAW STANDARD READABLE'), 0) AS unreadable_gaps,
                   COALESCE(COUNT_IF(is_gap AND ARRAY_SIZE(explicit_l3_ids_on_raw_standard) > 0), 0) AS explicit_l3
            FROM (
                SELECT c.*, review_scope = 'JOSH ORIGINAL GAP' AS is_gap FROM compared c
            ) scoped
        )
        SELECT raw_l2, changed_l2, raw_l3,
               CASE WHEN package_standards <> 324 OR saved_gaps <> 98
                        THEN 'Scope changed (' || package_standards || ' standards, ' || saved_gaps || ' gaps)'
                    WHEN raw_l2 <> saved_gaps OR changed_l2 > 0 OR raw_l3 > 0 THEN 'Observed paths differ'
                    ELSE 'Observed paths agree' END
               || IFF(unreadable_gaps > 0 OR q.l3_roots_with_membership_array = 0
                      OR q.missing_readable_source_tables + q.unreadable_or_ambiguous_raw_records
                         + q.unsupported_raw_reference_members + q.unresolved_owner_standard_ids > 0,
                      ' / incomplete source coverage', '')
               || IFF(explicit_l3 > 0, ' / additional Level 3 reference to review', '') AS source_check
        FROM counts CROSS JOIN coverage q
    );
    RETURN TABLE(rows_out);
END;
$$;

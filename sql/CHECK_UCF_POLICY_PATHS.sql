-- Snowflake. Set these session variables in your worksheet, then run the SELECT.
--   ucf_ssp_dim                fully qualified SSP element table
--   ucf_catalog_dim            fully qualified Catalog element table
--   ucf_standard_source        fully qualified Archer Control Standards RAW table
--   ucf_policy_l3_source       fully qualified Archer Policy Level 3 RAW table
--   ucf_aa_l2_id                Archer Content ID of the selected A&A Level 2 Policy
--   ucf_rev2_catalog_id         Archer Content ID of the selected Rev 2 Catalog
--   ucf_candidate_min_id        numeric threshold from the original query
-- To count confirmed UCF matches, replace '[]' in settings with a JSON array of
-- owner-confirmed L3 Policy Content IDs. An empty list gives NULL confirmed counts.
--
-- SUMMARY reports counts. STANDARD accounts for every starting Standard.
-- LEVEL_3_PATH retains the exact (starting Standard, referring Standard, Policy) tuple.
-- Catalog placement here has the same DIM meaning as the original query.
-- RAW values are evidence from stored versions. No current version is inferred.
WITH settings AS (
    SELECT $ucf_aa_l2_id::VARCHAR AS aa_policy_id,
           $ucf_rev2_catalog_id::VARCHAR AS rev2_catalog_id,
           $ucf_candidate_min_id::NUMBER AS candidate_min_policy_id,
           PARSE_JSON('[]') AS verified_policy_ids
), verified_policies AS (
    SELECT DISTINCT m.value::VARCHAR AS policy_id
    FROM settings s, LATERAL FLATTEN(INPUT => AS_ARRAY(s.verified_policy_ids)) m
    WHERE REGEXP_LIKE(m.value::VARCHAR, '[1-9][0-9]*')
), ssp AS (
    SELECT SOURCE_RECORD_ID::VARCHAR AS package_id,
           SOURCE_SYSTEM_NAME,
           SOURCE_TABLE_NAME,
           TRY_PARSE_JSON(METADATA_JSON::VARCHAR) AS doc
    FROM IDENTIFIER($ucf_ssp_dim)
    WHERE ELEMENT_TYPE = 'implemented-requirements'
), dpf AS (
    SELECT s.package_id, s.SOURCE_SYSTEM_NAME, s.SOURCE_TABLE_NAME,
           p.value:ns::VARCHAR AS property_namespace,
           TRY_PARSE_JSON(p.value:value::VARCHAR) AS refs
    FROM ssp s, LATERAL FLATTEN(INPUT => s.doc:props) p
    WHERE p.value:name::VARCHAR = 'archer-control-standard-reference'
), package_standards AS (
    -- Reproduce the original population. Keep a flag for the expected Archer route.
    SELECT m.value:ContentId::VARCHAR AS standard_id,
           COUNT(DISTINCT d.package_id) AS package_count,
           MAX(IFF(d.SOURCE_SYSTEM_NAME = 'ARCHER'
               AND d.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW'
               AND d.property_namespace = 'urn:archer:source:v1'
               AND REGEXP_LIKE(m.value:ContentId::VARCHAR, '[1-9][0-9]*')
               AND COALESCE(NULLIF(m.value:LevelId::VARCHAR, 'null'), '41') = '41'
               AND COALESCE(NULLIF(m.value:ModuleId::VARCHAR, 'null'), '66') = '66', 1, 0))
               AS seen_on_expected_archer_route
    FROM dpf d, LATERAL FLATTEN(INPUT => d.refs) m
    WHERE m.value:ContentId::VARCHAR IS NOT NULL
    GROUP BY standard_id
), catalog AS (
    SELECT SOURCE_RECORD_ID::VARCHAR AS root_id, SOURCE_TABLE_NAME AS source_name,
           TRY_PARSE_JSON(METADATA_JSON::VARCHAR) AS doc
    FROM IDENTIFIER($ucf_catalog_dim)
    WHERE ELEMENT_TYPE = 'controls'
), placements AS (
    SELECT DISTINCT p.value:value::VARCHAR AS standard_id, c.root_id, c.source_name
    FROM catalog c, LATERAL FLATTEN(INPUT => c.doc:props) p
    WHERE p.value:name::VARCHAR = 'archer-content-id'
), incoming_edges AS (
    -- Archer stores the reference on the referring Standard. The search goes in reverse.
    SELECT DISTINCT a.value:value::VARCHAR AS via_standard_id,
           m.value:ContentId::VARCHAR AS standard_id
    FROM catalog c,
         LATERAL FLATTEN(INPUT => c.doc:props) a,
         LATERAL FLATTEN(INPUT => c.doc:props) p,
         LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(p.value:value::VARCHAR)) m
    WHERE a.value:name::VARCHAR = 'archer-content-id'
      AND p.value:name::VARCHAR = 'control-standards-related-control-requirements'
      AND a.value:value::VARCHAR <> m.value:ContentId::VARCHAR
), incoming AS (
    SELECT e.*
    FROM incoming_edges e JOIN package_standards s ON s.standard_id = e.standard_id
), paths AS (
    SELECT 'DIRECT' AS path_type, s.standard_id, NULL::VARCHAR AS via_standard_id,
           p.root_id, p.source_name
    FROM package_standards s JOIN placements p ON p.standard_id = s.standard_id
    UNION ALL
    SELECT 'ONE_INCOMING_HOP', i.standard_id, i.via_standard_id, p.root_id, p.source_name
    FROM incoming i JOIN placements p ON p.standard_id = i.via_standard_id
), placement_counts AS (
    SELECT p.standard_id,
           MAX(IFF(path_type = 'DIRECT' AND source_name = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW', 1, 0)) AS direct_l3,
           MAX(IFF(path_type = 'ONE_INCOMING_HOP' AND source_name = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW', 1, 0)) AS via_l3,
           MAX(IFF(path_type = 'DIRECT' AND source_name = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW'
                   AND root_id = s.aa_policy_id, 1, 0)) AS direct_aa_l2,
           COUNT(DISTINCT IFF(path_type = 'DIRECT' AND source_name IN (
                 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_1_RAW',
                 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW',
                 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW'), source_name || ':' || root_id, NULL)) AS direct_policy_roots,
           ARRAY_AGG(DISTINCT IFF(path_type = 'DIRECT'
                   AND source_name = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW', root_id, NULL)) AS direct_l2_ids,
           MAX(IFF(path_type = 'DIRECT' AND source_name = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW'
                   AND root_id = s.rev2_catalog_id, 1, 0)) AS direct_rev2,
           MAX(IFF(path_type = 'ONE_INCOMING_HOP' AND source_name = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW'
                   AND root_id = s.rev2_catalog_id, 1, 0)) AS via_rev2,
           MAX(IFF(path_type = 'ONE_INCOMING_HOP' AND root_id = s.rev2_catalog_id, 1, 0)) AS via_rev2_original_test
    FROM paths p CROSS JOIN settings s
    GROUP BY p.standard_id
), incoming_ids AS (
    SELECT standard_id, ARRAY_AGG(DISTINCT via_standard_id) AS referring_standard_ids
    FROM incoming GROUP BY standard_id
), l3_paths AS (
    SELECT p.path_type, p.standard_id, p.via_standard_id, p.root_id AS policy_id,
           COALESCE(TRY_TO_NUMBER(p.root_id) >= s.candidate_min_policy_id, FALSE) AS passes_id_cutoff,
           v.policy_id IS NOT NULL AS matches_verified_list
    FROM paths p CROSS JOIN settings s
    LEFT JOIN verified_policies v ON v.policy_id = p.root_id
    WHERE p.source_name = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW'
), standard_raw AS (
    SELECT CONTENT_ID::VARCHAR AS standard_id, TRY_PARSE_JSON(CURATED_JSON::VARCHAR) AS doc
    FROM IDENTIFIER($ucf_standard_source)
    WHERE CONTENT_ID::VARCHAR IN (
        SELECT standard_id FROM package_standards
        UNION
        SELECT via_standard_id FROM incoming
    )
), raw_hierarchy_candidates AS (
    SELECT DISTINCT r.standard_id, m.value:ContentId::VARCHAR AS policy_id
    FROM standard_raw r, LATERAL FLATTEN(INPUT => TO_ARRAY(r.doc:POLICY_HIERARCHY_LEVEL_1_2_3)) m
    WHERE REGEXP_LIKE(m.value:ContentId::VARCHAR, '[1-9][0-9]*')
      AND COALESCE(NULLIF(m.value:LevelId::VARCHAR, 'null'), '5') = '5'
      AND COALESCE(NULLIF(m.value:ModuleId::VARCHAR, 'null'), '65') = '65'
), policy_raw AS (
    SELECT CONTENT_ID::VARCHAR AS policy_id, TRY_PARSE_JSON(CURATED_JSON::VARCHAR) AS doc
    FROM IDENTIFIER($ucf_policy_l3_source)
    WHERE CONTENT_ID::VARCHAR IN (
        SELECT policy_id FROM l3_paths
        UNION
        SELECT policy_id FROM raw_hierarchy_candidates
    )
), policies AS (
    SELECT policy_id, COUNT(*) AS raw_rows,
           COUNT(DISTINCT TO_JSON(doc)) AS json_versions,
           ARRAY_AGG(DISTINCT doc:POLICY_LEVEL_3_NAME::VARCHAR) AS policy_names,
           ARRAY_AGG(DISTINCT TO_JSON(doc:POLICY_LEVEL_3_TRACKING_ID)) AS tracking_ids,
           ARRAY_AGG(DISTINCT TO_JSON(doc:POLICY_LEVEL_2_REFERENCE)) AS level_2_references,
           ARRAY_AGG(DISTINCT TO_JSON(doc:AUTHORITATIVE_SOURCES)) AS authoritative_references
    FROM policy_raw GROUP BY policy_id
), raw_hierarchy_l3 AS (
    SELECT r.standard_id, ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(
               'policy_id', r.policy_id, 'policy_names', p.policy_names,
               'policy_tracking_ids', p.tracking_ids)) AS raw_hierarchy_level_3_records
    FROM raw_hierarchy_candidates r JOIN policies p ON p.policy_id = r.policy_id
    GROUP BY r.standard_id
), standard_evidence AS (
    SELECT standard_id, COUNT(*) AS raw_rows,
           COUNT(DISTINCT TO_JSON(doc)) AS json_versions,
           ARRAY_AGG(DISTINCT doc:CONTROL_STANDARD_NAME::VARCHAR) AS standard_names,
           ARRAY_AGG(DISTINCT TO_JSON(doc:UCF_ID)) AS standard_ucf_values,
           ARRAY_AGG(DISTINCT TO_JSON(doc:POLICY_HIERARCHY_LEVEL_1_2_3)) AS raw_policy_hierarchy
    FROM standard_raw GROUP BY standard_id
), standard_results AS (
    SELECT s.*, COALESCE(i.referring_standard_ids, ARRAY_CONSTRUCT()) AS referring_standard_ids,
           COALESCE(p.direct_l2_ids, ARRAY_CONSTRUCT()) AS direct_l2_ids,
           COALESCE(p.direct_l3, 0) AS direct_l3,
           COALESCE(p.via_l3, 0) AS via_l3,
           COALESCE(p.direct_aa_l2, 0) AS direct_aa_l2,
           COALESCE(p.direct_aa_l2 = 1 AND p.direct_policy_roots = 1, FALSE) AS aa_is_only_direct_policy_root,
           COALESCE(p.direct_rev2, 0) AS direct_rev2,
           COALESCE(p.via_rev2, 0) AS via_rev2,
           COALESCE(p.via_rev2_original_test, 0) AS via_rev2_original_test,
           CASE WHEN p.direct_l3 = 1 AND p.via_l3 = 1 THEN 'BOTH_L3_PATHS'
                WHEN p.direct_l3 = 1 THEN 'DIRECT_L3_ONLY'
                WHEN p.via_l3 = 1 THEN 'INCOMING_L3_ONLY'
                WHEN i.standard_id IS NOT NULL THEN 'INCOMING_WITHOUT_L3'
                ELSE 'NO_DIRECT_L3_OR_INCOMING' END AS path_group
    FROM package_standards s
    LEFT JOIN placement_counts p ON p.standard_id = s.standard_id
    LEFT JOIN incoming_ids i ON i.standard_id = s.standard_id
), standard_totals AS (
    SELECT COUNT(*) AS package_standards,
           COALESCE(SUM(seen_on_expected_archer_route), 0) AS on_expected_archer_route,
           COALESCE(SUM(direct_l3), 0) AS direct_l3,
           COALESCE(SUM(via_l3), 0) AS via_l3,
           COALESCE(COUNT_IF(ARRAY_SIZE(referring_standard_ids) > 0), 0) AS any_incoming,
           COALESCE(COUNT_IF(path_group = 'BOTH_L3_PATHS'), 0) AS both_l3_paths,
           COALESCE(COUNT_IF(path_group = 'DIRECT_L3_ONLY'), 0) AS direct_l3_only,
           COALESCE(COUNT_IF(path_group = 'INCOMING_L3_ONLY'), 0) AS incoming_l3_only,
           COALESCE(COUNT_IF(path_group = 'INCOMING_WITHOUT_L3'), 0) AS incoming_without_l3,
           COALESCE(COUNT_IF(path_group = 'NO_DIRECT_L3_OR_INCOMING'), 0) AS original_no_policy_path,
           COALESCE(COUNT_IF(path_group = 'NO_DIRECT_L3_OR_INCOMING'
                             AND aa_is_only_direct_policy_root), 0) AS original_gap_aa_only_policy_root,
           COALESCE(SUM(direct_rev2), 0) AS direct_rev2,
           COALESCE(SUM(via_rev2), 0) AS via_rev2,
           COALESCE(SUM(via_rev2_original_test), 0) AS via_rev2_original_test
    FROM standard_results
), ucf_totals AS (
    SELECT COUNT(DISTINCT IFF(path_type = 'ONE_INCOMING_HOP' AND passes_id_cutoff, standard_id, NULL)) AS incoming_candidate_standards,
           COUNT(DISTINCT IFF(path_type = 'ONE_INCOMING_HOP' AND passes_id_cutoff, policy_id, NULL)) AS incoming_candidate_policies,
           COUNT(DISTINCT IFF(matches_verified_list, standard_id, NULL)) AS standards_reaching_verified_policy,
           COUNT(DISTINCT IFF(matches_verified_list, policy_id, NULL)) AS distinct_verified_policies
    FROM l3_paths
), verified_list_count AS (
    SELECT COUNT(*) AS ids_supplied FROM verified_policies
), report AS (
    SELECT 'SUMMARY' AS row_type, NULL::VARCHAR AS standard_id,
           NULL::VARCHAR AS referring_standard_id, NULL::VARCHAR AS policy_id,
           NULL::VARCHAR AS path, OBJECT_CONSTRUCT_KEEP_NULL(
               'package_standards', s.package_standards,
               'on_expected_archer_route', s.on_expected_archer_route,
               'direct_l3', s.direct_l3, 'via_l3', s.via_l3, 'any_incoming', s.any_incoming,
               'both_l3_paths', s.both_l3_paths, 'direct_l3_only', s.direct_l3_only,
               'incoming_l3_only', s.incoming_l3_only, 'incoming_without_l3', s.incoming_without_l3,
               'original_no_policy_path', s.original_no_policy_path,
               'original_gap_aa_only_policy_root', s.original_gap_aa_only_policy_root,
               'direct_rev2', s.direct_rev2, 'via_rev2', s.via_rev2,
               'via_rev2_original_test', s.via_rev2_original_test,
               'incoming_cutoff_standards', u.incoming_candidate_standards,
               'incoming_cutoff_distinct_policies', u.incoming_candidate_policies,
               'verified_list_size', v.ids_supplied,
               'standards_reaching_listed_ucf_policy', IFF(v.ids_supplied = 0, NULL, u.standards_reaching_verified_policy),
               'distinct_listed_ucf_policies_reached', IFF(v.ids_supplied = 0, NULL, u.distinct_verified_policies)) AS evidence
    FROM standard_totals s CROSS JOIN ucf_totals u CROSS JOIN verified_list_count v
    UNION ALL
    SELECT 'STANDARD', r.standard_id, NULL, NULL, r.path_group,
           OBJECT_CONSTRUCT_KEEP_NULL('package_count', r.package_count,
               'on_expected_archer_route', r.seen_on_expected_archer_route,
               'level_2_policy_ids', r.direct_l2_ids, 'aa_is_only_direct_policy_root', r.aa_is_only_direct_policy_root,
               'referring_standard_ids', r.referring_standard_ids, 'direct_rev2', r.direct_rev2,
               'via_rev2', r.via_rev2, 'raw_rows', raw.raw_rows, 'raw_versions', raw.json_versions,
               'standard_names', raw.standard_names, 'standard_ucf_values', raw.standard_ucf_values,
               'raw_policy_hierarchy', raw.raw_policy_hierarchy,
               'raw_hierarchy_level_3_records', h.raw_hierarchy_level_3_records)
    FROM standard_results r
    LEFT JOIN standard_evidence raw ON raw.standard_id = r.standard_id
    LEFT JOIN raw_hierarchy_l3 h ON h.standard_id = r.standard_id
    UNION ALL
    SELECT 'LEVEL_3_PATH', p.standard_id, p.via_standard_id, p.policy_id, p.path_type,
           OBJECT_CONSTRUCT_KEEP_NULL('policy_names', l.policy_names, 'policy_tracking_ids', l.tracking_ids,
               'policy_raw_rows', l.raw_rows, 'policy_raw_versions', l.json_versions,
               'level_2_references', l.level_2_references, 'authoritative_source_references', l.authoritative_references,
               'passes_id_cutoff', p.passes_id_cutoff,
               'matches_verified_list', IFF(v.ids_supplied = 0, NULL, p.matches_verified_list),
               'referring_standard_names', raw.standard_names, 'referring_standard_ucf_values', raw.standard_ucf_values,
               'referring_standard_raw_policy_hierarchy', raw.raw_policy_hierarchy,
               'referring_standard_raw_l3_records', h.raw_hierarchy_level_3_records)
    FROM l3_paths p CROSS JOIN verified_list_count v
    LEFT JOIN policies l ON l.policy_id = p.policy_id
    LEFT JOIN standard_evidence raw ON raw.standard_id = p.via_standard_id
    LEFT JOIN raw_hierarchy_l3 h ON h.standard_id = p.via_standard_id
)
SELECT * FROM report
ORDER BY DECODE(row_type, 'SUMMARY', 0, 'STANDARD', 1, 2),
         TRY_TO_NUMBER(standard_id), standard_id, path, policy_id, referring_standard_id;

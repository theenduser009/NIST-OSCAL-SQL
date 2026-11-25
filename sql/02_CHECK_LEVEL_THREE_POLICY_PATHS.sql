-- Step 2. Run in the same curated worksheet. The first nine columns are totals; the remaining
-- columns are the evidence for one distinct starting Standard. The gap is scoped
-- to Josh's two tested routes. An ID-range hit is only a UCF candidate.
WITH package_standards AS (
    SELECT DISTINCT r.value:ContentId::VARCHAR AS standard_id
    FROM DIM_OSCAL_SSP_ELEMENT s,
         LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(s.metadata_json::VARCHAR):props) p,
         LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(p.value:value::VARCHAR)) r
    WHERE s.element_type = 'implemented-requirements'
      AND p.value:name::VARCHAR = 'archer-control-standard-reference'
      AND r.value:ContentId::VARCHAR IS NOT NULL
),
controls AS (
    SELECT source_table_name, source_record_id::VARCHAR AS root_id,
           TRY_PARSE_JSON(metadata_json::VARCHAR) AS doc
    FROM DIM_OSCAL_CATALOG_ELEMENT
    WHERE element_type = 'controls'
),
identified AS (
    SELECT c.*, p.value:value::VARCHAR AS standard_id
    FROM controls c, LATERAL FLATTEN(INPUT => c.doc:props) p
    WHERE p.value:name::VARCHAR = 'archer-content-id'
),
incoming AS (
    SELECT DISTINCT r.value:ContentId::VARCHAR AS standard_id, c.standard_id AS via_id
    FROM identified c, LATERAL FLATTEN(INPUT => c.doc:props) p,
         LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(p.value:value::VARCHAR)) r
    WHERE p.value:name::VARCHAR = 'control-standards-related-control-requirements'
      AND c.standard_id <> r.value:ContentId::VARCHAR
),
routes AS (
    SELECT s.standard_id, 'DIRECT' AS route, s.standard_id AS lookup_id
    FROM package_standards s
    UNION ALL
    SELECT s.standard_id, 'VIA' AS route, i.via_id AS lookup_id
    FROM package_standards s JOIN incoming i ON i.standard_id = s.standard_id
),
placements AS (
    SELECT DISTINCT standard_id, source_table_name, root_id FROM identified
),
paths AS (
    SELECT r.*, p.root_id,
           p.source_table_name = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW' AS is_l2,
           p.source_table_name = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW' AS is_l3
    FROM routes r LEFT JOIN placements p ON p.standard_id = r.lookup_id
),
per_standard AS (
    SELECT standard_id,
           MAX(IFF(route = 'DIRECT' AND is_l3, 1, 0)) AS direct_l3,
           MAX(IFF(route = 'VIA' AND is_l3, 1, 0)) AS via_l3,
           MAX(IFF(route = 'VIA', 1, 0)) AS has_incoming,
           MAX(IFF(route = 'DIRECT' AND is_l2, 1, 0)) AS direct_l2,
           MAX(IFF(route = 'VIA' AND is_l3 AND TRY_TO_NUMBER(root_id) >= 7250000, 1, 0)) AS ucf_range_hit,
           ARRAY_AGG(DISTINCT IFF(route = 'DIRECT' AND is_l2, root_id, NULL)) AS direct_l2_ids,
           ARRAY_AGG(DISTINCT IFF(route = 'DIRECT' AND is_l3, root_id, NULL)) AS direct_l3_ids,
           ARRAY_AGG(DISTINCT IFF(route = 'VIA', lookup_id, NULL)) AS referring_standard_ids,
           ARRAY_AGG(DISTINCT IFF(route = 'VIA' AND is_l3, lookup_id || ' -> ' || root_id, NULL)) AS via_standard_to_l3,
           ARRAY_AGG(DISTINCT IFF(route = 'VIA' AND is_l3 AND TRY_TO_NUMBER(root_id) >= 7250000,
                                  root_id, NULL)) AS candidate_policy_ids
    FROM paths GROUP BY standard_id
)
SELECT COUNT(*) OVER () AS package_standards,
       SUM(direct_l3) OVER () AS any_direct_l3, SUM(via_l3) OVER () AS any_via_l3,
       SUM(IFF(direct_l3 = 1 AND via_l3 = 1, 1, 0)) OVER () AS both_routes,
       SUM(IFF(direct_l3 = 0 AND has_incoming = 0, 1, 0)) OVER () AS joshs_no_path,
       SUM(IFF(direct_l3 = 0 AND via_l3 = 0, 1, 0)) OVER () AS no_l3_on_either_route,
       SUM(IFF(direct_l3 = 0 AND via_l3 = 0 AND has_incoming = 1, 1, 0)) OVER () AS extra_gaps,
       SUM(IFF(direct_l3 = 0 AND has_incoming = 0, direct_l2, 0)) OVER () AS joshs_gaps_with_l2,
       SUM(ucf_range_hit) OVER () AS candidate_standards,
       standard_id, direct_l2_ids, direct_l3_ids, referring_standard_ids, via_standard_to_l3, candidate_policy_ids,
       CASE WHEN direct_l3 = 1 AND via_l3 = 1 THEN 'BOTH'
            WHEN direct_l3 = 1 THEN 'DIRECT ONLY'
            WHEN via_l3 = 1 THEN 'VIA ONLY'
            WHEN has_incoming = 1 THEN 'RELATED STANDARD FOUND, NO LEVEL 3'
            ELSE 'NO DIRECT LEVEL 3 OR REFERRING STANDARD' END AS path_result
FROM per_standard
ORDER BY IFF(direct_l3 = 0 AND via_l3 = 0 AND has_incoming = 1, 0, 1), standard_id;

-- Snowflake DEV. Compare Policy Level 3 Control Standard Content IDs and names.
-- Raw Value preserves the Archer reference. Saved Value shows the saved ID and title.
-- An ID-only source reference gets its expected name from the Archer Control Standard record.
-- The two deferred fields still show their raw values for review.
WITH raw_policies AS (
    SELECT CONTENT_ID::VARCHAR AS content_id,
           ANY_VALUE(CURATED_JSON) AS doc,
           COUNT(*) AS raw_rows
    FROM RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW
    WHERE CONTENT_ID IS NOT NULL
    GROUP BY CONTENT_ID
),
nodes AS (
    SELECT SOURCE_RECORD_ID::VARCHAR AS content_id,
           PK_DIM_OSCAL_CATALOG_ELEMENT_HASH AS node_key,
           ELEMENT_TYPE AS kind,
           METADATA_JSON AS doc
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.DIM_OSCAL_CATALOG_ELEMENT
    WHERE SOURCE_SYSTEM_NAME = 'ARCHER'
      AND SOURCE_TABLE_NAME = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW'
      AND ELEMENT_TYPE IN ('catalog', 'groups', 'controls')
      AND SOURCE_RECORD_ID IS NOT NULL
),
policy_ids AS (
    SELECT content_id FROM raw_policies
    UNION
    SELECT content_id FROM nodes WHERE kind = 'catalog'
),
fields AS (
    SELECT column1 AS field_name
    FROM VALUES
        ('CONTROL_REQUIREMENTS_CONTROL_STANDARD_POLICY'),
        ('CONTROL_REQUIREMENTS_FUNCTIONAL_CORPORATE_POLICIES'),
        ('CONTROL_STANDARD_REQUIREMENTS')
),
raw_values AS (
    SELECT i.content_id, f.field_name, p.raw_rows,
           GET(AS_OBJECT(p.doc), f.field_name) AS raw_value
    FROM policy_ids i
    CROSS JOIN fields f
    LEFT JOIN raw_policies p ON p.content_id = i.content_id
),
raw_items AS (
    SELECT r.content_id,
           IFF(IS_OBJECT(f.value), f.value:ContentId, f.value)::VARCHAR AS standard_id,
           IFF(IS_OBJECT(f.value), f.value:LevelId::VARCHAR, NULL) AS level_id,
           OBJECT_DELETE(AS_OBJECT(f.value), 'ContentId', 'LevelId') AS display_fields
    FROM raw_values r, LATERAL FLATTEN(INPUT => AS_ARRAY(r.raw_value)) f
    WHERE r.field_name = 'CONTROL_STANDARD_REQUIREMENTS' AND r.raw_rows = 1
),
raw_members AS (
    SELECT content_id, standard_id, level_id,
           COALESCE(
               AS_VARCHAR(GET(display_fields, 'CONTROL_STANDARD_NAME')),
               AS_VARCHAR(GET(display_fields, 'Name')),
               CASE WHEN ARRAY_SIZE(OBJECT_KEYS(display_fields)) = 1
                    THEN AS_VARCHAR(GET(display_fields, GET(OBJECT_KEYS(display_fields), 0)::VARCHAR))
               END
           ) AS reference_name
    FROM raw_items
),
raw_ids AS (
    SELECT content_id,
           ARRAY_AGG(DISTINCT standard_id) WITHIN GROUP (ORDER BY standard_id) AS ids,
           COUNT_IF(standard_id IS NULL
                    OR NOT REGEXP_LIKE(standard_id, '[1-9][0-9]*')
                    OR (level_id IS NOT NULL AND level_id <> '41')) AS invalid_ids
    FROM raw_members
    GROUP BY content_id
),
raw_names AS (
    SELECT content_id, standard_id,
           MAX(CASE WHEN NULLIF(TRIM(reference_name), '') IS NOT NULL THEN reference_name END) AS reference_name,
           COUNT(DISTINCT CASE WHEN NULLIF(TRIM(reference_name), '') IS NOT NULL THEN reference_name END) AS name_count
    FROM raw_members
    WHERE REGEXP_LIKE(standard_id, '[1-9][0-9]*')
    GROUP BY content_id, standard_id
),
lookup_names AS (
    SELECT t.CONTENT_ID::VARCHAR AS standard_id,
           MAX(AS_VARCHAR(t.CURATED_JSON:CONTROL_STANDARD_NAME)) AS standard_name,
           COUNT(*) AS source_rows
    FROM RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_CONTROL_STANDARDS_RAW t
    JOIN (SELECT DISTINCT standard_id FROM raw_names WHERE reference_name IS NULL) r
      ON t.CONTENT_ID::VARCHAR = r.standard_id
    GROUP BY t.CONTENT_ID
),
policy_groups AS (
    SELECT DISTINCT g.content_id, g.node_key, g.doc
    FROM nodes c
    JOIN RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.FACT_OSCAL_CATALOG_DEPENDENCY e
      ON e.FK_SOURCE_ELEMENT_HASH = c.node_key AND e.DEPENDENCY_TYPE = 'CONTAINS'
    JOIN nodes g
      ON g.node_key = e.FK_TARGET_ELEMENT_HASH AND g.content_id = c.content_id
    WHERE c.kind = 'catalog' AND g.kind = 'groups'
),
saved_links AS (
    SELECT DISTINCT g.content_id, l.value:href::VARCHAR AS href
    FROM policy_groups g, LATERAL FLATTEN(INPUT => g.doc:links) l
    WHERE l.value:rel::VARCHAR = 'related'
),
saved_controls AS (
    SELECT n.content_id, n.node_key,
           '#' || ARRAY_TO_STRING(TRANSFORM(
               REGEXP_SUBSTR_ALL(n.doc:id::VARCHAR, '.'), ch ->
               IFF(REGEXP_LIKE(ch::VARCHAR, '[A-Za-z0-9_.~-]'), ch::VARCHAR,
                   REGEXP_REPLACE(HEX_ENCODE(ch::VARCHAR), '(..)', '%\\1'))), '') AS href,
           p.value:value::VARCHAR AS standard_id,
           AS_VARCHAR(n.doc:title) AS standard_name
    FROM nodes n, LATERAL FLATTEN(INPUT => n.doc:props) p
    WHERE n.kind = 'controls'
      AND p.value:name::VARCHAR = 'archer-content-id'
      AND REGEXP_LIKE(p.value:value::VARCHAR, '[1-9][0-9]*')
),
linked_controls AS (
    SELECT DISTINCT l.content_id, c.node_key, c.standard_id, c.standard_name
    FROM saved_links l
    JOIN saved_controls c ON c.content_id = l.content_id AND c.href = l.href
),
saved_ids AS (
    SELECT content_id,
           ARRAY_AGG(DISTINCT standard_id) WITHIN GROUP (ORDER BY standard_id) AS ids,
           ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL('ContentId', standard_id, 'Name', standard_name))
               WITHIN GROUP (ORDER BY standard_id, node_key) AS control_values
    FROM linked_controls
    GROUP BY content_id
),
name_pairs AS (
    SELECT r.content_id, r.standard_id, s.node_key, s.standard_name AS saved_name,
           COALESCE(r.reference_name, CASE WHEN l.source_rows = 1 THEN l.standard_name END) AS expected_name,
           r.name_count > 1 OR (r.reference_name IS NULL AND COALESCE(l.source_rows, 0) > 1) AS ambiguous_name
    FROM raw_names r
    JOIN linked_controls s ON s.content_id = r.content_id AND s.standard_id = r.standard_id
    LEFT JOIN lookup_names l ON l.standard_id = r.standard_id
),
name_checks AS (
    SELECT content_id,
           COUNT(*) > COUNT(DISTINCT standard_id) AS duplicate_saved_id,
           COUNT_IF(ambiguous_name) AS ambiguous_names,
           COUNT_IF(NULLIF(TRIM(expected_name), '') IS NULL) AS missing_raw_names,
           COUNT_IF(NULLIF(TRIM(saved_name), '') IS NULL) AS missing_saved_names,
           COUNT_IF(expected_name <> saved_name) AS name_mismatches
    FROM name_pairs
    GROUP BY content_id
)
SELECT r.content_id, r.field_name, r.raw_value, s.control_values AS saved_value,
       CASE
           WHEN r.raw_rows IS NULL THEN 'RAW_ROW_MISSING'
           WHEN r.raw_rows > 1 THEN 'DUPLICATE_RAW_CONTENT_ID'
           WHEN r.field_name <> 'CONTROL_STANDARD_REQUIREMENTS' THEN 'NO_SAVED_MAPPING_TO_COMPARE'
           WHEN r.raw_value IS NOT NULL AND NOT IS_NULL_VALUE(r.raw_value)
                AND NOT IS_ARRAY(r.raw_value) THEN 'RAW_NOT_AN_ARRAY'
           WHEN COALESCE(a.invalid_ids, 0) > 0 THEN 'INVALID_RAW_REFERENCE'
           WHEN COALESCE(ARRAY_SIZE(a.ids), 0) = 0 AND s.ids IS NULL THEN 'BOTH_EMPTY'
           WHEN COALESCE(ARRAY_SIZE(a.ids), 0) = 0 THEN 'RAW_EMPTY_SAVED_PRESENT'
           WHEN s.ids IS NULL THEN 'NO_SAVED_CONTROL_IDS'
           WHEN TO_JSON(a.ids) IS DISTINCT FROM TO_JSON(s.ids) THEN 'VALUE_MISMATCH'
           WHEN n.duplicate_saved_id THEN 'DUPLICATE_SAVED_CONTROL_ID'
           WHEN COALESCE(n.ambiguous_names, 0) > 0 THEN 'AMBIGUOUS_RAW_NAME'
           WHEN COALESCE(n.missing_saved_names, 0) > 0 THEN 'SAVED_NAME_MISSING'
           WHEN COALESCE(n.missing_raw_names, 0) > 0 THEN 'RAW_NAME_UNAVAILABLE'
           WHEN COALESCE(n.name_mismatches, 0) > 0 THEN 'NAME_MISMATCH'
           ELSE 'MATCH'
       END AS q_result
FROM raw_values r
LEFT JOIN raw_ids a
  ON a.content_id = r.content_id AND r.field_name = 'CONTROL_STANDARD_REQUIREMENTS'
LEFT JOIN saved_ids s
  ON s.content_id = r.content_id AND r.field_name = 'CONTROL_STANDARD_REQUIREMENTS'
LEFT JOIN name_checks n
  ON n.content_id = r.content_id AND r.field_name = 'CONTROL_STANDARD_REQUIREMENTS'
ORDER BY CASE q_result
             WHEN 'VALUE_MISMATCH' THEN 0
             WHEN 'NAME_MISMATCH' THEN 0
             WHEN 'RAW_EMPTY_SAVED_PRESENT' THEN 0
             WHEN 'NO_SAVED_CONTROL_IDS' THEN 1
             WHEN 'MATCH' THEN 3
             WHEN 'BOTH_EMPTY' THEN 4
             WHEN 'NO_SAVED_MAPPING_TO_COMPARE' THEN 5
             ELSE 2
         END,
         r.content_id, r.field_name;

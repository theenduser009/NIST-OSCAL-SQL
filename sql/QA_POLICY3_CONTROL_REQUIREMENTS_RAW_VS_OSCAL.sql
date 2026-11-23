-- Snowflake DEV. Run the whole statement to compare all Policy Level 3 records.
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
raw_members AS (
    SELECT r.content_id,
           IFF(IS_OBJECT(f.value), f.value:ContentId, f.value)::VARCHAR AS standard_id,
           IFF(IS_OBJECT(f.value), f.value:LevelId::VARCHAR, NULL) AS level_id
    FROM raw_values r, LATERAL FLATTEN(INPUT => AS_ARRAY(r.raw_value)) f
    WHERE r.field_name = 'CONTROL_STANDARD_REQUIREMENTS' AND r.raw_rows = 1
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
    SELECT n.content_id,
           '#' || ARRAY_TO_STRING(TRANSFORM(
               REGEXP_SUBSTR_ALL(n.doc:id::VARCHAR, '.'), ch ->
               IFF(REGEXP_LIKE(ch::VARCHAR, '[A-Za-z0-9_.~-]'), ch::VARCHAR,
                   REGEXP_REPLACE(HEX_ENCODE(ch::VARCHAR), '(..)', '%\\1'))), '') AS href,
           p.value:value::VARCHAR AS standard_id
    FROM nodes n, LATERAL FLATTEN(INPUT => n.doc:props) p
    WHERE n.kind = 'controls'
      AND p.value:name::VARCHAR = 'archer-content-id'
      AND REGEXP_LIKE(p.value:value::VARCHAR, '[1-9][0-9]*')
),
saved_ids AS (
    SELECT l.content_id,
           ARRAY_AGG(DISTINCT c.standard_id)
               WITHIN GROUP (ORDER BY c.standard_id) AS ids
    FROM saved_links l
    JOIN saved_controls c ON c.content_id = l.content_id AND c.href = l.href
    GROUP BY l.content_id
)
SELECT r.content_id, r.field_name, r.raw_value, s.ids AS saved_value,
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
           WHEN TO_JSON(a.ids) = TO_JSON(s.ids) THEN 'MATCH'
           ELSE 'VALUE_MISMATCH'
       END AS q_result
FROM raw_values r
LEFT JOIN raw_ids a
  ON a.content_id = r.content_id AND r.field_name = 'CONTROL_STANDARD_REQUIREMENTS'
LEFT JOIN saved_ids s
  ON s.content_id = r.content_id AND r.field_name = 'CONTROL_STANDARD_REQUIREMENTS'
ORDER BY CASE q_result
             WHEN 'VALUE_MISMATCH' THEN 0
             WHEN 'RAW_EMPTY_SAVED_PRESENT' THEN 0
             WHEN 'NO_SAVED_CONTROL_IDS' THEN 1
             WHEN 'MATCH' THEN 3
             WHEN 'BOTH_EMPTY' THEN 4
             WHEN 'NO_SAVED_MAPPING_TO_COMPARE' THEN 5
             ELSE 2
         END,
         r.content_id, r.field_name;

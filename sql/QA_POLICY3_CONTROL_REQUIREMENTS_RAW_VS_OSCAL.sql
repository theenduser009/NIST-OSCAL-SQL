-- Snowflake QA for Policy Level 3 control requirements.
-- Replace the three table placeholders with fully qualified Snowflake names.
-- Set <POLICY_LEVEL_3_SOURCE_IDENTITY> to SOURCE_TABLE_NAME in the Catalog DIM.
-- Replace the sample IDs with Policy Level 3 Content IDs. This query only reads data.
WITH scope AS (
    SELECT DISTINCT column1::VARCHAR AS content_id
    FROM VALUES ('PASTE_ID_1'), ('PASTE_ID_2'), ('PASTE_ID_3')
), fields AS (
    SELECT column1 AS archer_field
    FROM VALUES ('CONTROL_REQUIREMENTS_CONTROL_STANDARD_POLICY'),
                ('CONTROL_REQUIREMENTS_FUNCTIONAL_CORPORATE_POLICIES'),
                ('CONTROL_STANDARD_REQUIREMENTS')
), policies AS (
    SELECT s.content_id, p.CURATED_JSON AS doc,
           COUNT(p.CONTENT_ID) OVER (PARTITION BY s.content_id) AS source_rows
    FROM scope s
    LEFT JOIN <POLICY_LEVEL_3_RAW_TABLE> p
      ON p.CONTENT_ID::VARCHAR = s.content_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY s.content_id ORDER BY p.CONTENT_ID) = 1
), raw_fields AS (
    SELECT p.content_id, p.source_rows, f.archer_field,
           GET(AS_OBJECT(p.doc), f.archer_field) AS raw_value
    FROM policies p CROSS JOIN fields f
), raw_members AS (
    SELECT r.content_id,
           IFF(IS_OBJECT(m.value), m.value:ContentId, m.value)::VARCHAR AS standard_id,
           IFF(IS_OBJECT(m.value), m.value:LevelId::VARCHAR, NULL) AS declared_level
    FROM raw_fields r, LATERAL FLATTEN(INPUT => AS_ARRAY(r.raw_value)) m
    WHERE r.archer_field = 'CONTROL_STANDARD_REQUIREMENTS' AND r.source_rows = 1
), raw_ids AS (
    SELECT content_id,
           ARRAY_AGG(DISTINCT standard_id) WITHIN GROUP (ORDER BY standard_id) AS ids,
           COUNT_IF(standard_id IS NULL OR NOT REGEXP_LIKE(standard_id, '[1-9][0-9]*')
                    OR (declared_level IS NOT NULL AND declared_level <> '41')) AS invalid_members
    FROM raw_members
    GROUP BY content_id
), nodes AS (
    SELECT n.SOURCE_RECORD_ID::VARCHAR AS content_id, n.ELEMENT_TYPE AS kind,
           n.PK_DIM_OSCAL_CATALOG_ELEMENT_HASH AS node_id, n.METADATA_JSON AS doc
    FROM <OSCAL_CATALOG_ELEMENT_TABLE> n
    JOIN scope s ON s.content_id = n.SOURCE_RECORD_ID::VARCHAR
    WHERE n.SOURCE_SYSTEM_NAME = 'ARCHER'
      AND n.SOURCE_TABLE_NAME = '<POLICY_LEVEL_3_SOURCE_IDENTITY>'
      AND n.ELEMENT_TYPE IN ('catalog', 'groups', 'controls')
), policy_groups AS (
    SELECT DISTINCT g.content_id, g.node_id, g.doc
    FROM nodes c
    JOIN <OSCAL_CATALOG_DEPENDENCY_TABLE> e
      ON e.FK_SOURCE_ELEMENT_HASH = c.node_id AND e.DEPENDENCY_TYPE = 'CONTAINS'
    JOIN nodes g ON g.node_id = e.FK_TARGET_ELEMENT_HASH AND g.content_id = c.content_id
    WHERE c.kind = 'catalog' AND g.kind = 'groups'
), saved_links AS (
    SELECT DISTINCT g.content_id, l.value:href::VARCHAR AS href
    FROM policy_groups g, LATERAL FLATTEN(INPUT => g.doc:links) l
    WHERE l.value:rel::VARCHAR = 'related'
), saved_controls AS (
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
), saved_ids AS (
    SELECT l.content_id,
           ARRAY_AGG(DISTINCT c.standard_id) WITHIN GROUP (ORDER BY c.standard_id) AS ids
    FROM saved_links l JOIN saved_controls c
      ON l.content_id = c.content_id AND l.href = c.href
    GROUP BY l.content_id
)
SELECT r.content_id, r.archer_field, r.raw_value, s.ids AS saved_value,
       CASE
           WHEN r.source_rows = 0 THEN 'RAW_ROW_MISSING'
           WHEN r.source_rows > 1 THEN 'DUPLICATE_RAW_CONTENT_ID'
           WHEN r.archer_field <> 'CONTROL_STANDARD_REQUIREMENTS' THEN 'NO_SAVED_MAPPING_TO_COMPARE'
           WHEN r.raw_value IS NOT NULL AND NOT IS_NULL_VALUE(r.raw_value)
                AND NOT IS_ARRAY(r.raw_value) THEN 'RAW_NOT_AN_ARRAY'
           WHEN COALESCE(i.invalid_members, 0) > 0 THEN 'INVALID_RAW_REFERENCE'
           WHEN COALESCE(ARRAY_SIZE(i.ids), 0) = 0 AND s.ids IS NULL THEN 'BOTH_EMPTY'
           WHEN COALESCE(ARRAY_SIZE(i.ids), 0) = 0 THEN 'RAW_EMPTY_SAVED_PRESENT'
           WHEN s.ids IS NULL THEN 'NO_SAVED_CONTROL_IDS'
           WHEN TO_JSON(i.ids) = TO_JSON(s.ids) THEN 'MATCH'
           ELSE 'VALUE_MISMATCH'
       END AS q_result
FROM raw_fields r
LEFT JOIN raw_ids i ON i.content_id = r.content_id
                       AND r.archer_field = 'CONTROL_STANDARD_REQUIREMENTS'
LEFT JOIN saved_ids s ON s.content_id = r.content_id
                         AND r.archer_field = 'CONTROL_STANDARD_REQUIREMENTS'
ORDER BY r.content_id, r.archer_field;

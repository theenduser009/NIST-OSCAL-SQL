-- Read-only Snowflake query.
-- Select the database and schema that contain the Catalog DIM and FACT tables in your worksheet.
-- Returns one Catalog with two or more Section groups pointing to a single root-owned control.
-- This checks control IDs that can appear in a fragment without URI encoding.

WITH dim AS (
    SELECT SOURCE_RECORD_ID AS catalog_id,
           PK_DIM_OSCAL_CATALOG_ELEMENT_HASH AS pk,
           ELEMENT_TYPE AS kind,
           METADATA_JSON AS payload
    FROM DIM_OSCAL_CATALOG_ELEMENT
    WHERE SOURCE_SYSTEM_NAME = 'ARCHER'
      AND SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW'
),
section_links AS (
    SELECT d.catalog_id, d.payload:id::VARCHAR AS section_id,
           l.value:href::VARCHAR AS href
    FROM dim d, LATERAL FLATTEN(INPUT => d.payload:links) l
    WHERE d.kind = 'groups'
      AND STARTSWITH(d.payload:id::VARCHAR, 'g-sections-')
      AND l.value:rel::VARCHAR = 'related'
)
SELECT c.catalog_id AS archer_catalog_content_id,
       c.payload:id::VARCHAR AS control_id,
       MAX(c.payload:title::VARCHAR) AS control_title,
       ARRAY_AGG(DISTINCT s.section_id)
           WITHIN GROUP (ORDER BY s.section_id) AS section_ids
FROM dim c
JOIN FACT_OSCAL_CATALOG_DEPENDENCY f
  ON f.FK_TARGET_ELEMENT_HASH = c.pk AND f.DEPENDENCY_TYPE = 'CONTAINS'
JOIN dim root
  ON root.pk = f.FK_SOURCE_ELEMENT_HASH AND root.kind = 'catalog'
 AND root.catalog_id = c.catalog_id
JOIN section_links s
  ON s.catalog_id = c.catalog_id AND s.href = '#' || c.payload:id::VARCHAR
WHERE c.kind = 'controls'
  AND REGEXP_LIKE(c.payload:id::VARCHAR, '[A-Za-z0-9._~-]+')
GROUP BY 1, 2
HAVING COUNT(DISTINCT c.pk) = 1 AND COUNT(DISTINCT s.section_id) >= 2
ORDER BY 1, 2
LIMIT 1;

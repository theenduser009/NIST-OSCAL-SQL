-- Step 1. In the curated worksheet where DIM_OSCAL_CATALOG_ELEMENT is visible,
-- run this whole SELECT. The SSP and Catalog reads use Josh's property names and
-- element filters. Repeated requirements and Catalog placements count once per ID.
WITH catalog_controls AS (
    SELECT TRY_PARSE_JSON(metadata_json::VARCHAR) AS doc
    FROM DIM_OSCAL_CATALOG_ELEMENT
    WHERE element_type = 'controls'
),
catalog_ids AS (
    SELECT DISTINCT p.value:value::VARCHAR AS standard_id
    FROM catalog_controls c, LATERAL FLATTEN(INPUT => c.doc:props) p
    WHERE p.value:name::VARCHAR = 'archer-content-id'
      AND p.value:value::VARCHAR IS NOT NULL
),
package_ids AS (
    SELECT DISTINCT r.value:ContentId::VARCHAR AS standard_id
    FROM DIM_OSCAL_SSP_ELEMENT s,
         LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(s.metadata_json::VARCHAR):props) p,
         LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(p.value:value::VARCHAR)) r
    WHERE s.element_type = 'implemented-requirements'
      AND p.value:name::VARCHAR = 'archer-control-standard-reference'
      AND r.value:ContentId::VARCHAR IS NOT NULL
)
SELECT (SELECT COUNT(*) FROM catalog_controls) AS catalog_control_rows,
       (SELECT COUNT(*) FROM catalog_ids) AS distinct_catalog_standard_ids,
       COUNT(p.standard_id) AS package_standard_ids,
       COUNT(c.standard_id) AS package_ids_found_in_catalog,
       COUNT(p.standard_id) - COUNT(c.standard_id) AS package_ids_missing_from_catalog,
       ARRAY_AGG(IFF(c.standard_id IS NULL, p.standard_id, NULL)) AS missing_standard_ids
FROM package_ids p
LEFT JOIN catalog_ids c ON c.standard_id = p.standard_id;

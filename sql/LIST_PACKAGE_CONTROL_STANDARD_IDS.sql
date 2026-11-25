-- Run in the curated schema containing DIM_OSCAL_SSP_ELEMENT.
WITH package_standards AS (
    SELECT DISTINCT ref.value:ContentId::VARCHAR AS control_standard_id
    FROM DIM_OSCAL_SSP_ELEMENT AS ssp,
         LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(ssp.METADATA_JSON::VARCHAR):props) AS prop,
         LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(prop.value:value::VARCHAR)) AS ref
    WHERE ssp.ELEMENT_TYPE = 'implemented-requirements'
      AND prop.value:name::VARCHAR = 'archer-control-standard-reference'
      AND ref.value:ContentId::VARCHAR IS NOT NULL
)
SELECT control_standard_id, COUNT(*) OVER () AS total_distinct_standards
FROM package_standards
ORDER BY control_standard_id;

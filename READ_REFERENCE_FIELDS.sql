-- Select your curated database and schema in the Snowflake worksheet.
-- Run each query separately. Each shows up to 100 saved property rows.
-- Root Content IDs identify the Catalog or ATO package, not the individual Standard or Allocation.

-- 1. Control Standards: Policy Hierarchy (Level 1, 2, 3)
SELECT
    d.SOURCE_RECORD_ID AS CATALOG_ROOT_CONTENT_ID,
    TRY_PARSE_JSON(d.METADATA_JSON::VARCHAR):id::VARCHAR AS CONTROL_STANDARD,
    p.VALUE:value::VARCHAR AS POLICY_HIERARCHY
FROM DIM_OSCAL_CATALOG_ELEMENT d,
     LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(d.METADATA_JSON::VARCHAR):props) p
WHERE d.ELEMENT_TYPE = 'controls'
  AND d.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND d.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW'
  AND p.VALUE:name::VARCHAR = 'policy-hierarchy-level-1-2-3'
  AND p.VALUE:ns::VARCHAR = 'urn:archer:source:v1'
LIMIT 100;

-- 2. Control Standards: Authoritative Sources
SELECT
    d.SOURCE_RECORD_ID AS CATALOG_ROOT_CONTENT_ID,
    TRY_PARSE_JSON(d.METADATA_JSON::VARCHAR):id::VARCHAR AS CONTROL_STANDARD,
    p.VALUE:value::VARCHAR AS AUTHORITATIVE_SOURCES
FROM DIM_OSCAL_CATALOG_ELEMENT d,
     LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(d.METADATA_JSON::VARCHAR):props) p
WHERE d.ELEMENT_TYPE = 'controls'
  AND d.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND d.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW'
  AND p.VALUE:name::VARCHAR = 'authoritative-sources'
  AND p.VALUE:ns::VARCHAR = 'urn:archer:source:v1'
LIMIT 100;

-- 3. Allocated Controls: Digital Policy Framework Reference
SELECT
    d.SOURCE_RECORD_ID AS ATO_CONTENT_ID,
    TRY_PARSE_JSON(d.METADATA_JSON::VARCHAR):"control-id"::VARCHAR AS SSP_CONTROL_ID,
    p.VALUE:value::VARCHAR AS DPF_REFERENCE
FROM DIM_OSCAL_SSP_ELEMENT d,
     LATERAL FLATTEN(INPUT => TRY_PARSE_JSON(d.METADATA_JSON::VARCHAR):props) p
WHERE d.ELEMENT_TYPE = 'implemented-requirements'
  AND d.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND d.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW'
  AND p.VALUE:name::VARCHAR = 'archer-control-standard-reference'
  AND p.VALUE:ns::VARCHAR = 'urn:archer:source:v1'
LIMIT 100;

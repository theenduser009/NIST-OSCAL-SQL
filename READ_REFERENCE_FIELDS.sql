-- Select your curated database and schema in the Snowflake worksheet dropdowns.
-- Run this entire SELECT in that SQL worksheet.
-- No notebook variables, SET commands, or data writes are required.
-- Reads saved OSCAL elements, not Archer RAW tables.
-- Shows up to 100 saved property rows per field, with the full matching-row count.
-- Repeated Catalog placements are separate rows, not unique Standards.
-- A missing result does not establish why a property was not saved.

WITH saved_elements AS (
    SELECT
        'CATALOG' AS MODEL,
        d.PK_DIM_OSCAL_CATALOG_ELEMENT_HASH AS ELEMENT_KEY,
        d.SOURCE_SYSTEM_NAME,
        d.SOURCE_TABLE_NAME,
        d.SOURCE_RECORD_ID::VARCHAR AS ROOT_CONTENT_ID,
        IFF(IS_OBJECT(d.METADATA_JSON), d.METADATA_JSON,
            TRY_PARSE_JSON(d.METADATA_JSON::VARCHAR, 's')) AS DOC
    FROM DIM_OSCAL_CATALOG_ELEMENT d
    WHERE d.SOURCE_SYSTEM_NAME = 'ARCHER'
      AND d.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW'
      AND d.ELEMENT_TYPE = 'controls'

    UNION ALL

    SELECT
        'SSP' AS MODEL,
        d.PK_OSCAL_SSP_ELEMENT_HASH AS ELEMENT_KEY,
        d.SOURCE_SYSTEM_NAME,
        d.SOURCE_TABLE_NAME,
        d.SOURCE_RECORD_ID::VARCHAR AS ROOT_CONTENT_ID,
        IFF(IS_OBJECT(d.METADATA_JSON), d.METADATA_JSON,
            TRY_PARSE_JSON(d.METADATA_JSON::VARCHAR, 's')) AS DOC
    FROM DIM_OSCAL_SSP_ELEMENT d
    WHERE d.SOURCE_SYSTEM_NAME = 'ARCHER'
      AND d.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW'
      AND d.ELEMENT_TYPE = 'implemented-requirements'
), properties AS (
    SELECT
        e.MODEL,
        e.ELEMENT_KEY,
        e.SOURCE_SYSTEM_NAME,
        e.SOURCE_TABLE_NAME,
        e.ROOT_CONTENT_ID,
        CASE WHEN e.MODEL = 'SSP' THEN e.DOC:"control-id"::VARCHAR
             ELSE e.DOC:id::VARCHAR END AS OSCAL_CONTROL_ID,
        p.INDEX AS PROPERTY_INDEX,
        p.VALUE:name::VARCHAR AS PROPERTY_NAME,
        p.VALUE:ns::VARCHAR AS PROPERTY_NAMESPACE,
        p.VALUE:value::VARCHAR AS PROPERTY_VALUE,
        p.VALUE:name::VARCHAR = 'archer-content-id'
            AND (p.VALUE:ns IS NULL
                 OR COALESCE(IS_NULL_VALUE(p.VALUE:ns), FALSE))
            AS IS_RECORD_ID_PROPERTY
    FROM saved_elements e,
         LATERAL FLATTEN(INPUT => AS_ARRAY(e.DOC:props)) p
), identified AS (
    SELECT
        p.*,
        SUM(IFF(IS_RECORD_ID_PROPERTY, 1, 0))
            OVER (PARTITION BY MODEL, ELEMENT_KEY) AS CONTENT_ID_PROPERTY_COUNT,
        MAX(IFF(IS_RECORD_ID_PROPERTY, PROPERTY_VALUE, NULL))
            OVER (PARTITION BY MODEL, ELEMENT_KEY) AS RECORD_CONTENT_ID
    FROM properties p
), requested_properties AS (
    SELECT *
    FROM identified
    WHERE PROPERTY_NAMESPACE = 'urn:archer:source:v1'
      AND (
          (MODEL = 'CATALOG' AND PROPERTY_NAME IN (
              'policy-hierarchy-level-1-2-3',
              'authoritative-sources'
          ))
          OR (MODEL = 'SSP'
              AND PROPERTY_NAME = 'archer-control-standard-reference')
      )
)
SELECT
    MODEL,
    SOURCE_SYSTEM_NAME,
    SOURCE_TABLE_NAME AS ROOT_SOURCE_TABLE,
    ROOT_CONTENT_ID,
    CASE WHEN MODEL = 'SSP' THEN 'ALLOCATED_CONTROL'
         ELSE 'CONTROL_STANDARD' END AS RECORD_KIND,
    IFF(ELEMENT_KEY IS NOT NULL
        AND CONTENT_ID_PROPERTY_COUNT = 1
        AND REGEXP_LIKE(RECORD_CONTENT_ID, '[1-9][0-9]*'),
        RECORD_CONTENT_ID, NULL)
        AS RECORD_CONTENT_ID,
    CONTENT_ID_PROPERTY_COUNT,
    OSCAL_CONTROL_ID,
    PROPERTY_NAME,
    PROPERTY_NAMESPACE,
    PROPERTY_VALUE,
    COUNT(*) OVER (PARTITION BY MODEL, PROPERTY_NAME)
        AS TOTAL_SAVED_PROPERTY_ROWS_FOR_FIELD
FROM requested_properties
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY MODEL, PROPERTY_NAME
    ORDER BY SOURCE_SYSTEM_NAME, ROOT_SOURCE_TABLE, ROOT_CONTENT_ID,
             OSCAL_CONTROL_ID, ELEMENT_KEY, PROPERTY_INDEX
) <= 100
ORDER BY MODEL, PROPERTY_NAME, ROOT_SOURCE_TABLE, ROOT_CONTENT_ID,
         OSCAL_CONTROL_ID, ELEMENT_KEY, PROPERTY_INDEX;

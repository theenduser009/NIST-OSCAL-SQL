-- Policy Level 3. FINDINGS_POLICY_LEVEL_3. Read-only Snowflake DEV.
-- Target path is assessment-results.results[].findings[].title.
-- TARGET_VALUE shows the saved member for each current Archer reference, matched by the mapper's physical key.
WITH sample AS (
    SELECT DISTINCT CONTENT_ID::VARCHAR AS content_id
    FROM RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW
    WHERE CONTENT_ID IS NOT NULL
    -- AND CONTENT_ID::VARCHAR = 'YOUR_CONTENT_ID'
),
raw_row AS (
    SELECT p.CONTENT_ID::VARCHAR AS content_id,
           GET(AS_OBJECT(p.CURATED_JSON), 'FINDINGS_POLICY_LEVEL_3') AS mapped_source_value,
           GET(AS_OBJECT(p.CURATED_JSON), 'FINDINGS_POLICY_LEVEL_3') AS exact_source_value
    FROM RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW p
    JOIN sample s ON s.content_id = p.CONTENT_ID::VARCHAR
),
reference_members AS (
    SELECT DISTINCT r.content_id, COALESCE(f.value:ContentId::VARCHAR, AS_VARCHAR(f.value),
                             AS_INTEGER(f.value)::VARCHAR) AS referenced_id,
           f.value:LevelId::VARCHAR AS declared_level
    FROM raw_row r,
         LATERAL FLATTEN(INPUT => IFF(IS_ARRAY(r.mapped_source_value),
             AS_ARRAY(r.mapped_source_value), ARRAY_CONSTRUCT_COMPACT(r.mapped_source_value))) f
),
target_candidates AS (
    SELECT n0.SOURCE_RECORD_ID AS SAVED_OWNER_CONTENT_ID,
           n2.OSCAL_UUID AS OSCAL_UUID,
           n2.ELEMENT_TYPE AS ELEMENT_TYPE,
           GET_PATH(n2.METADATA_JSON, 'title') AS OSCAL_VALUE,
           n2.METADATA_JSON AS OSCAL_PAYLOAD,
           n2.DW_LOAD_TIMESTAMP AS OSCAL_LOAD_TIMESTAMP,
           n2.PK_DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT_HASH AS target_key
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT n0
    JOIN RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.FACT_OSCAL_ASSESSMENT_RESULTS_DEPENDENCY e1
      ON e1.FK_SOURCE_ELEMENT_HASH = n0.PK_DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT_HASH
     AND e1.DEPENDENCY_TYPE = 'CONTAINS'
    JOIN RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT n1
      ON n1.PK_DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT_HASH = e1.FK_TARGET_ELEMENT_HASH
     AND n1.ELEMENT_TYPE = 'results'
    JOIN RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.FACT_OSCAL_ASSESSMENT_RESULTS_DEPENDENCY e2
      ON e2.FK_SOURCE_ELEMENT_HASH = n1.PK_DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT_HASH
     AND e2.DEPENDENCY_TYPE = 'CONTAINS'
    JOIN RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT n2
      ON n2.PK_DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT_HASH = e2.FK_TARGET_ELEMENT_HASH
     AND n2.ELEMENT_TYPE = 'findings'
    WHERE n0.SOURCE_SYSTEM_NAME = 'ARCHER'
      AND n0.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW'
      AND n0.ELEMENT_TYPE = 'assessment-results'
      AND n0.SOURCE_RECORD_ID::VARCHAR IN (SELECT content_id FROM sample)
),
target_rows AS (
    SELECT c.SAVED_OWNER_CONTENT_ID, c.OSCAL_UUID, OBJECT_CONSTRUCT_KEEP_NULL(
               'ContentId', p.referenced_id, 'title', c.OSCAL_VALUE
           ) AS OSCAL_VALUE
    FROM target_candidates c JOIN reference_members p
      ON c.SAVED_OWNER_CONTENT_ID::VARCHAR = p.content_id
     AND c.target_key = MD5_BINARY(
            'v1_registry_path_instance|ARCHER|ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW|' ||
            c.SAVED_OWNER_CONTENT_ID::VARCHAR || '|' ||
            'ASSESSMENT_RESULTS|assessment-results.results[].findings[]|' ||
            TO_JSON(ARRAY_CONSTRUCT('FINDINGS_POLICY_LEVEL_3', 'RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_FINDINGS_RAW',
                                    p.referenced_id)))
    WHERE REGEXP_LIKE(p.referenced_id, '[1-9][0-9]*')
      AND (p.declared_level IS NULL OR p.declared_level = '62')
),
target_values AS (
    SELECT SAVED_OWNER_CONTENT_ID::VARCHAR AS content_id,
           COUNT(*) AS value_count,
           ARRAY_AGG(COALESCE(OSCAL_VALUE::VARIANT, PARSE_JSON('null')))
             WITHIN GROUP (ORDER BY OSCAL_UUID) AS values_array
    FROM target_rows
    GROUP BY SAVED_OWNER_CONTENT_ID::VARCHAR
)
SELECT s.content_id AS ARCHER_CONTENT_ID,
       r.exact_source_value AS SOURCE_VALUE,
       CASE WHEN t.value_count IS NULL THEN NULL
            WHEN t.value_count = 1 THEN GET(t.values_array, 0)
            ELSE TO_VARIANT(t.values_array)
       END AS TARGET_VALUE
FROM sample s
LEFT JOIN raw_row r ON r.content_id = s.content_id
LEFT JOIN target_values t ON t.content_id = s.content_id
ORDER BY s.content_id;

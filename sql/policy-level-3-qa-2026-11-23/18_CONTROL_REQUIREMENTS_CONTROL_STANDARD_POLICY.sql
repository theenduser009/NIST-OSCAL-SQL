-- Policy Level 3. CONTROL_REQUIREMENTS_CONTROL_STANDARD_POLICY. Read-only Snowflake DEV.
-- Target unavailable in the reviewed mapping (deferred no populated references). TARGET_VALUE is returned as SQL NULL.
WITH sample AS (
    SELECT DISTINCT CONTENT_ID::VARCHAR AS content_id
    FROM RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW
    WHERE CONTENT_ID IS NOT NULL
    -- AND CONTENT_ID::VARCHAR = 'YOUR_CONTENT_ID'
),
raw_row AS (
    SELECT p.CONTENT_ID::VARCHAR AS content_id,
           GET(AS_OBJECT(p.CURATED_JSON), 'CONTROL_REQUIREMENTS_CONTROL_STANDARD_POLICY') AS mapped_source_value,
           GET(AS_OBJECT(p.CURATED_JSON), 'CONTROL_REQUIREMENTS_CONTROL_STANDARD_POLICY') AS exact_source_value
    FROM RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW p
    JOIN sample s ON s.content_id = p.CONTENT_ID::VARCHAR
)
SELECT s.content_id AS ARCHER_CONTENT_ID,
       r.exact_source_value AS SOURCE_VALUE,
       NULL::VARIANT AS TARGET_VALUE
FROM sample s
LEFT JOIN raw_row r ON r.content_id = s.content_id
ORDER BY s.content_id;

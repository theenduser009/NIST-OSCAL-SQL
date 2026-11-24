-- Read-only. Run in the DEV schema containing ETL_CONFIG.
-- These are candidate extracts; confirm which one holds completed site assessments.
SELECT CONFIG_ID, NAME, OBJECT_NAME, RAW_TABLE_NAME
FROM ETL_CONFIG
WHERE UPPER(SOURCE_SYSTEM) = 'ARCHER'
  AND CONCAT_WS(' ', COALESCE(NAME, ''), COALESCE(OBJECT_NAME, ''),
                COALESCE(RAW_TABLE_NAME, '')) ILIKE ANY
      ('%QUESTIONNAIRE%', '%SITE%ASSESS%', '%FACILIT%ASSESS%', '%PHYSICAL%SECURITY%')
ORDER BY NAME, CONFIG_ID;

-- In the DEV worksheet, select the database and schema containing ETL_CONFIG and ES_ESC_GRC_RAW.
-- Run each numbered statement separately. This example is for the November 23 date folder.

-- 1. Record the original path and pattern for this feed.
SELECT CONFIG_ID, NAME, STAGE_NAME, STAGE_PATH, FILE_PATTERN, RAW_TABLE_NAME
FROM ETL_CONFIG
WHERE CONFIG_ID = 105 AND NAME = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE';

-- 2. Expect one file. This only lists files on the stage.
LIST @ES_ESC_GRC_RAW/ARCHER/2026/11/23/
  PATTERN = '^(.*/)?ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE[.]jsonl[.]gz$';

-- 3. After the one-file check, apply this to feed 105 when its next load uses the date-first layout.
-- The Matillion load component must append YYYY/MM/DD/ to STAGE_PATH and use FILE_PATTERN.
UPDATE ETL_CONFIG
SET STAGE_PATH = 'ARCHER',
    FILE_PATTERN = '^(.*/)?ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE[.]jsonl[.]gz$'
WHERE CONFIG_ID = 105
  AND NAME = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE'
  AND RTRIM(STAGE_PATH, '/') = 'ARCHER/ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE';

-- 4. Re-run statement 1 to check the saved settings. Compare the next eligible Matillion
-- run's loaded filename and raw-table destination with the expected feed before rollout.

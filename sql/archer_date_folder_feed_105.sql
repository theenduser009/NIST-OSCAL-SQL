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

-- 5. Matillion file-selection preview (inside the loop, after the config/watermark query).
-- Run only this LIST statement in Matillion, with the same database/schema context as the loader.
-- Bind the iterator's FILE_PATTERN column to jv_file_pattern (or use its existing variable name).
-- The iterator supplies the stage, path and zero-padded YYYY, MM, DD for watermark + 1 day.
LIST @${jv_stage_name}/${jv_stage_path}/${jv_year}/${jv_month}/${jv_day}/
  PATTERN = '${jv_file_pattern}';

-- For feed 105 expect one ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE.jsonl.gz.
-- In the existing raw-loader COPY, use the same @stage/path/year/month/day/ source
-- in its staged SELECT and the same PATTERN at COPY level, outside that SELECT.
-- Preserve the loader's target columns, JSON projection, filename, scan time,
-- file format and load options. LIST only verifies selection; COPY performs the load.

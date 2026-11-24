-- In the DEV worksheet, select the database and schema containing ETL_CONFIG and ES_ESC_GRC_RAW.
-- Follow the numbered instructions. Use the DEV Snowflake worksheet except for step 5 (Matillion).
-- Feed 105 already configured? Skip step 3. Use steps 6-8 for the other feeds.

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

-- 6. Snowflake worksheet only. Preview the other feeds for the known new-layout day.
-- Run both statements back to back in the same session. This step changes no config.
LIST @ES_ESC_GRC_RAW/ARCHER/2026/11/23/;

SELECT c.CONFIG_ID, c.NAME, c.STAGE_PATH AS current_path,
       f."name" AS staged_file,
       IFF(f."name" IS NULL, 'NO EXACT FILE FOUND', 'FILE FOUND') AS check_result
FROM ETL_CONFIG c
LEFT JOIN TABLE(RESULT_SCAN(LAST_QUERY_ID())) f
  ON ENDSWITH('/' || f."name",
              '/ARCHER/2026/11/23/' || SPLIT_PART(RTRIM(c.STAGE_PATH, '/'), '/', -1) || '.jsonl.gz')
WHERE UPPER(c.SOURCE_SYSTEM) = 'ARCHER'
  AND UPPER(c.STAGE_NAME) = 'ES_ESC_GRC_RAW'
  AND REGEXP_LIKE(RTRIM(c.STAGE_PATH, '/'), 'ARCHER/[A-Za-z0-9_]+')
  AND c.CONFIG_ID <> 105
ORDER BY c.CONFIG_ID;

-- FILE FOUND matches the old feed-folder name to the exact filename in the new day folder.
-- Check each feed's next watermark date before changing its path; older dates can use the old layout.

-- 7. Bulk cutover in the same DEV Snowflake worksheet. Run the whole LIST ->> UPDATE
-- as ONE statement, from LIST through the final semicolon. This is a one-time 2026 cutover.
-- A feed must match both the November 23 preview AND its next watermark day's actual file.
-- Only STAGE_PATH and FILE_PATTERN change. This does not load data or advance watermarks.
LIST @ES_ESC_GRC_RAW/ARCHER/2026/
->> UPDATE ETL_CONFIG
SET STAGE_PATH = 'ARCHER',
    FILE_PATTERN = '^(.*/)?' || matched.feed_name || '[.]jsonl[.]gz$'
FROM (
    WITH staged_files AS (
        SELECT DISTINCT SPLIT_PART('/' || "name", '/ARCHER/', -1) AS date_and_file
        FROM $1
    ), next_load AS (
        SELECT UPPER(SOURCE_SYSTEM) AS source_system, UPPER(OBJECT_NAME) AS object_name,
               DATEADD(day, 1, MIN(LAST_LOADED_DATE)::DATE) AS run_date
        FROM ETL_WATERMARK
        WHERE UPPER(SOURCE_SYSTEM) = 'ARCHER'
        GROUP BY UPPER(SOURCE_SYSTEM), UPPER(OBJECT_NAME)
        HAVING COUNT(*) = 1
    ), legacy_feeds AS (
        SELECT c.CONFIG_ID, c.STAGE_PATH, c.FILE_PATTERN,
               SPLIT_PART(RTRIM(c.STAGE_PATH, '/'), '/', -1) AS feed_name,
               w.run_date
        FROM ETL_CONFIG c
        JOIN next_load w ON UPPER(c.SOURCE_SYSTEM) = w.source_system
                        AND UPPER(c.OBJECT_NAME) = w.object_name
        WHERE UPPER(c.STAGE_NAME) = 'ES_ESC_GRC_RAW'
          AND c.CONFIG_ID <> 105
          AND REGEXP_LIKE(RTRIM(c.STAGE_PATH, '/'), 'ARCHER/[A-Za-z0-9_]+')
          AND w.run_date >= DATE '2026-11-23'
        QUALIFY COUNT(*) OVER (PARTITION BY c.CONFIG_ID) = 1
    )
    SELECT f.CONFIG_ID, f.STAGE_PATH, f.FILE_PATTERN, f.feed_name
    FROM legacy_feeds f
    JOIN staged_files reviewed
      ON reviewed.date_and_file = '2026/11/23/' || f.feed_name || '.jsonl.gz'
    JOIN staged_files due
      ON due.date_and_file = TO_CHAR(f.run_date, 'YYYY/MM/DD') || '/' || f.feed_name || '.jsonl.gz'
) AS matched
WHERE ETL_CONFIG.CONFIG_ID = matched.CONFIG_ID
  AND UPPER(ETL_CONFIG.SOURCE_SYSTEM) = 'ARCHER'
  AND UPPER(ETL_CONFIG.STAGE_NAME) = 'ES_ESC_GRC_RAW'
  AND ETL_CONFIG.STAGE_PATH = matched.STAGE_PATH
  AND EQUAL_NULL(ETL_CONFIG.FILE_PATTERN, matched.FILE_PATTERN);

-- 8. Check the feed settings after step 7. Rows still using a feed folder need review.
SELECT CONFIG_ID, NAME, STAGE_PATH, FILE_PATTERN
FROM ETL_CONFIG
WHERE UPPER(SOURCE_SYSTEM) = 'ARCHER' AND UPPER(STAGE_NAME) = 'ES_ESC_GRC_RAW'
ORDER BY CONFIG_ID;

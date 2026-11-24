-- Run once in the DEV schema containing ETL_CONFIG.
-- For Archer feeds moving from ARCHER/<feed>/YYYY/MM/DD/ to ARCHER/YYYY/MM/DD/,
-- use the old feed folder name as the new filename stem.
UPDATE ETL_CONFIG
SET FILE_PATTERN = '^(.*/)?' || SPLIT_PART(RTRIM(STAGE_PATH, '/'), '/', -1) || '[.]jsonl[.]gz$',
    STAGE_PATH = 'ARCHER'
WHERE UPPER(SOURCE_SYSTEM) = 'ARCHER'
  AND UPPER(STAGE_NAME) = 'ES_ESC_GRC_RAW'
  AND REGEXP_LIKE(RTRIM(STAGE_PATH, '/'), 'ARCHER/[A-Za-z0-9_]+');

-- Run once in the DEV schema containing ETL_WATERMARK and ETL_CONFIG.
-- The next Matillion run targets ARCHER/2026/11/23/ for these existing watermark rows.
-- With COPY FORCE = TRUE, previously loaded November 23 files can be loaded again.
UPDATE ETL_WATERMARK
SET LAST_LOADED_DATE = DATE '2026-11-22'
WHERE UPPER(SOURCE_SYSTEM) = 'ARCHER'
  AND LAST_LOADED_DATE::DATE IS DISTINCT FROM DATE '2026-11-22'
  AND UPPER(OBJECT_NAME) IN (
      SELECT UPPER(OBJECT_NAME)
      FROM ETL_CONFIG
      WHERE UPPER(SOURCE_SYSTEM) = 'ARCHER'
        AND UPPER(STAGE_NAME) = 'ES_ESC_GRC_RAW'
        AND STAGE_PATH = 'ARCHER'
  );

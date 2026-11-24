-- Matillion child job. Pass the current ETL_CONFIG.FILE_PATTERN into jv_file_pattern.
-- The existing FORCE = TRUE reloads matching files when the same day is rerun.
COPY INTO IDENTIFIER('${jv_raw_table_name}')
    (RAW_DATA, SOURCE_FILE_NAME, FILE_DATE, ETL_LOAD_TS, LOAD_TIMESTAMP)
FROM (
    SELECT t.$1,
           SPLIT_PART(METADATA$FILENAME, '/', -1),
           TO_DATE('${jv_year}-${jv_month}-${jv_day}', 'YYYY-MM-DD'),
           METADATA$START_SCAN_TIME,
           CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
    FROM @${jv_stage_name}/${jv_stage_path}/${jv_year}/${jv_month}/${jv_day}/ t
)
PATTERN = '${jv_file_pattern}'
FILE_FORMAT = (FORMAT_NAME = '${jv_file_format_name}')
ON_ERROR = 'CONTINUE'
FORCE = TRUE;

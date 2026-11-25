-- Run the whole block in your DEV worksheet. It reads each visible Archer base table
-- in the RAW schema, including ARCHER_META tables, and puts empty tables first.
EXECUTE IMMEDIATE $$
DECLARE
    inventory_id VARCHAR;
    schema_count INTEGER;
    raw_database VARCHAR;
    raw_schema VARCHAR;
    tables_view VARCHAR;
    counts_sql VARCHAR;
    counts RESULTSET;
    scope_error EXCEPTION (-20032, 'Select the DEV Archer RAW database and schema, and check that the role can see the Allocated Controls and Authorization Package tables.');
BEGIN
    SHOW TABLES IN ACCOUNT STARTS WITH 'ARCHER_CONTENT_A';
    inventory_id := SQLID;
    SELECT COUNT(*), MIN(db_name), MIN(schema_name)
      INTO :schema_count, :raw_database, :raw_schema
    FROM (
        SELECT "database_name" AS db_name, "schema_name" AS schema_name
        FROM TABLE(RESULT_SCAN(:inventory_id))
        WHERE ENDSWITH(UPPER("database_name"), '_DEV')
          AND "name" IN ('ARCHER_CONTENT_ALLOCATED_CONTROLS_CONTROL_RAW',
                         'ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW')
        GROUP BY "database_name", "schema_name"
        HAVING COUNT(DISTINCT "name") = 2
        QUALIFY DENSE_RANK() OVER (ORDER BY IFF("database_name" = CURRENT_DATABASE()
            AND "schema_name" = CURRENT_SCHEMA(), 0, 1)) = 1
    );
    IF (schema_count <> 1) THEN
        RAISE scope_error;
    END IF;

    tables_view := '"' || REPLACE(raw_database, '"', '""') || '".INFORMATION_SCHEMA.TABLES';
    SELECT LISTAGG(
        'SELECT ' || CHR(39) || REPLACE(REPLACE(table_name, CHR(92), CHR(92) || CHR(92)),
            CHR(39), CHR(39) || CHR(39)) || CHR(39) || ' AS table_name, COUNT(*) AS row_count FROM "'
        || REPLACE(table_catalog, '"', '""') || '"."' || REPLACE(table_schema, '"', '""')
        || '"."' || REPLACE(table_name, '"', '""') || '"',
        ' UNION ALL '
    ) WITHIN GROUP (ORDER BY table_name) INTO :counts_sql
    FROM IDENTIFIER(:tables_view)
    WHERE table_schema = :raw_schema AND table_type = 'BASE TABLE'
      AND STARTSWITH(UPPER(table_name), 'ARCHER_');

    IF (counts_sql IS NULL OR counts_sql = '') THEN
        RAISE scope_error;
    END IF;
    counts_sql := counts_sql || ' ORDER BY row_count, table_name';
    counts := (EXECUTE IMMEDIATE :counts_sql);
    RETURN TABLE(counts);
END;
$$;

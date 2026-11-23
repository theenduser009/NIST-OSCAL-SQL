# Policy Level 3 field queries

Open [FIELD_INDEX.csv](FIELD_INDEX.csv) to find the SQL file for a field. Each file is a standalone, read-only Snowflake DEV query and returns the raw Archer value alongside the saved OSCAL value for each Policy Level 3 Content ID.

To check one record, add its Content ID to the filter in the opening `sample` CTE. The existing statement runs for all Policy Level 3 records when the optional filter is commented out.

[ALL_QUERIES.sql](ALL_QUERIES.sql) contains all 89 statements. Queries with no verified target mapping return a null target value and explain the mapping status in their comments.

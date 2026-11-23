# Policy Level 3 source and target values

Open [ALL_QUERIES.sql](ALL_QUERIES.sql), copy the whole file, and run it in Snowflake DEV. It is one read-only SQL statement and returns the field name, Content ID, source value, and saved target value for the 89 reviewed fields.

The public query selects one source sample per field. It uses the lowest Content ID with a populated value when one exists. No edits or setup are required. The target is null when the query finds no saved value or the mapping has no verified target.

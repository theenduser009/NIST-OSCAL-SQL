-- Run in the Archer RAW schema.
-- Step 1: Archer source only. One output row shows a package, its allocation,
-- and the Control Standard referenced by that allocation. Totals repeat on each row.
WITH packages AS (
    SELECT DISTINCT content_id::VARCHAR AS package_id,
           TRY_PARSE_JSON(curated_json::VARCHAR):AUTHORIZATION_PACKAGE_NAME::VARCHAR AS package_name
    FROM ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW
    WHERE content_id IS NOT NULL
),
allocations AS (
    SELECT content_id::VARCHAR AS allocation_id, TRY_PARSE_JSON(curated_json::VARCHAR) AS doc
    FROM ARCHER_CONTENT_ALLOCATED_CONTROLS_CONTROL_RAW
),
assignments AS (
    -- The existing mapper uses the first Authorization Package member as the owner.
    SELECT DISTINCT a.allocation_id,
           CASE WHEN IS_OBJECT(a.doc:AUTHORIZATION_PACKAGE[0])
                THEN a.doc:AUTHORIZATION_PACKAGE[0].ContentId::VARCHAR
                ELSE a.doc:AUTHORIZATION_PACKAGE[0]::VARCHAR END AS package_id,
           CASE WHEN IS_OBJECT(ref.value) THEN ref.value:ContentId::VARCHAR
                WHEN IS_INTEGER(ref.value) OR IS_VARCHAR(ref.value) THEN ref.value::VARCHAR
           END AS standard_id
    FROM allocations a,
         LATERAL FLATTEN(INPUT => TO_ARRAY(a.doc:DIGITAL_POLICY_FRAMEWORK_DPF_REFERENCE), OUTER => TRUE) ref
),
standards AS (
    SELECT DISTINCT content_id::VARCHAR AS standard_id,
           TRY_PARSE_JSON(curated_json::VARCHAR):CONTROL_STANDARD_NAME::VARCHAR AS standard_name
    FROM ARCHER_CONTENT_CONTROL_STANDARDS_RAW
    WHERE content_id IS NOT NULL
)
SELECT p.package_id, p.package_name, a.allocation_id,
       a.standard_id AS referenced_standard_id, s.standard_name,
       CASE WHEN a.allocation_id IS NULL THEN 'NO ALLOCATION FOUND'
            WHEN a.standard_id IS NULL THEN 'NO STANDARD ID ON ALLOCATION'
            WHEN s.standard_id IS NULL THEN 'STANDARD ID MISSING FROM STANDARD TABLE'
            ELSE 'FOUND IN STANDARD TABLE' END AS source_link_status,
       COUNT(DISTINCT p.package_id) OVER () AS total_archer_packages,
       COUNT(DISTINCT a.standard_id) OVER () AS total_referenced_standard_ids,
       COUNT(DISTINCT s.standard_id) OVER () AS total_found_standard_ids
FROM packages p
LEFT JOIN assignments a ON a.package_id = p.package_id
LEFT JOIN standards s ON s.standard_id = a.standard_id
ORDER BY p.package_id, a.allocation_id, a.standard_id;

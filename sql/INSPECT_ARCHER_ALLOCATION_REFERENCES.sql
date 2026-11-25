-- Select the Archer RAW schema in the worksheet.
-- Josh's two policy questions follow the source check: which package standards
-- reach UCF policies, and do the 98 standards without a path really stop there?
-- First establish the source assignments and compare their IDs to the saved SSP.
-- Read-only Archer source check. Run the whole SELECT. It always returns one row.
-- Start with the package's forward list to locate a current allocation.
-- The mapper separately checks the allocation's owner. A forward link alone does
-- not establish a mapped package-to-standard assignment.
WITH packages AS (
    SELECT CONTENT_ID::VARCHAR AS package_id,
           IFF(IS_OBJECT(CURATED_JSON), CURATED_JSON,
               TRY_PARSE_JSON(CURATED_JSON::VARCHAR)) AS doc
    FROM ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW
),
listed AS (
    SELECT DISTINCT p.package_id,
           IFF(IS_OBJECT(f.value), f.value:ContentId, f.value)::VARCHAR AS allocation_id
    FROM packages p, LATERAL FLATTEN(INPUT => TO_ARRAY(p.doc:ALLOCATED_CONTROLS)) f
    WHERE REGEXP_LIKE(IFF(IS_OBJECT(f.value), f.value:ContentId, f.value)::VARCHAR, '[1-9][0-9]*')
),
allocations AS (
    SELECT CONTENT_ID::VARCHAR AS allocation_id,
           IFF(IS_OBJECT(CURATED_JSON), CURATED_JSON,
               TRY_PARSE_JSON(CURATED_JSON::VARCHAR)) AS doc
    FROM ARCHER_CONTENT_ALLOCATED_CONTROLS_CONTROL_RAW
),
linked AS (
    SELECT l.package_id, l.allocation_id, a.doc
    FROM listed l JOIN allocations a ON a.allocation_id = l.allocation_id
),
example AS (
    SELECT package_id, allocation_id, doc:AUTHORIZATION_PACKAGE AS owner_reference,
           doc:DIGITAL_POLICY_FRAMEWORK_DPF_REFERENCE AS standard_reference
    FROM linked
    ORDER BY IFF(doc:DIGITAL_POLICY_FRAMEWORK_DPF_REFERENCE IS NULL
                 OR IS_NULL_VALUE(doc:DIGITAL_POLICY_FRAMEWORK_DPF_REFERENCE), 1, 0),
             package_id, allocation_id
    LIMIT 1
),
counts AS (
    SELECT (SELECT COUNT(DISTINCT package_id) FROM packages) AS raw_packages,
           (SELECT COUNT(*) FROM allocations) AS allocation_table_rows,
           (SELECT COUNT(DISTINCT allocation_id) FROM listed) AS allocation_ids_listed_by_packages,
           (SELECT COUNT(DISTINCT allocation_id) FROM linked) AS listed_ids_found_in_allocation_table
)
SELECT c.*, e.package_id AS example_package_id, e.allocation_id AS example_allocation_id,
       e.owner_reference AS owner_as_stored, e.standard_reference AS standard_reference_as_stored
FROM counts c LEFT JOIN example e ON TRUE;

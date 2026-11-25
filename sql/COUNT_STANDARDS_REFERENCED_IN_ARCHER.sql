-- Select the Archer RAW schema in your worksheet.
-- Run the full statement. It returns one row from the stored Archer RAW extract.
-- A standard that is assigned to multiple packages counts once in REFERENCED_STANDARDS.
WITH packages AS (
    SELECT DISTINCT CONTENT_ID::VARCHAR AS package_id
    FROM ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW
    WHERE CONTENT_ID IS NOT NULL
),
allocation_docs AS (
    SELECT TRY_PARSE_JSON(CURATED_JSON::VARCHAR) AS doc
    FROM ARCHER_CONTENT_ALLOCATED_CONTROLS_CONTROL_RAW
),
allocation_fields AS (
    SELECT doc:AUTHORIZATION_PACKAGE[0] AS owner,
           doc:DIGITAL_POLICY_FRAMEWORK_DPF_REFERENCE AS standard_refs
    FROM allocation_docs
),
raw_pairs AS (
    SELECT DISTINCT p.package_id,
           IFF(IS_OBJECT(ref.value), ref.value:ContentId, ref.value)::VARCHAR AS standard_id
    FROM allocation_fields AS a
    JOIN packages AS p
      ON p.package_id = IFF(IS_OBJECT(a.owner), a.owner:ContentId, a.owner)::VARCHAR,
         LATERAL FLATTEN(INPUT => TO_ARRAY(a.standard_refs)) AS ref
    WHERE REGEXP_LIKE(IFF(IS_OBJECT(ref.value), ref.value:ContentId, ref.value)::VARCHAR, '[1-9][0-9]*')
),
standard_records AS (
    SELECT DISTINCT CONTENT_ID::VARCHAR AS standard_id
    FROM ARCHER_CONTENT_CONTROL_STANDARDS_RAW
)
SELECT (SELECT COUNT(*) FROM packages) AS archer_packages,
       COUNT(DISTINCT r.package_id) AS packages_with_standard_references,
       COUNT(DISTINCT r.standard_id) AS referenced_standards,
       COUNT(DISTINCT s.standard_id) AS referenced_standards_found_in_archer
FROM raw_pairs AS r
LEFT JOIN standard_records AS s ON s.standard_id = r.standard_id;

-- Josh's sanity check, in order:
-- 1. Establish the distinct standards referenced by packages in Archer RAW.
-- 2. Compare package and standard IDs, including their pairings, with saved SSP data.
-- 3. For those standards, distinguish a direct Level Three policy, a Level Three
--    policy through a referring standard, and neither. Check reported gaps in RAW.
-- 4. Confirm UCF membership using authoritative evidence independent of an ID range.
--    Check NIST Revision 2 separately through the standard's authoritative-source links.
-- Select the Archer RAW schema. This public version shows up to ten stored examples.
-- The DEV version reads the previously traced allocation by its exact Content ID.
WITH allocation AS (
    SELECT CONTENT_ID, CURATED_JSON,
           IFF(IS_OBJECT(CURATED_JSON), CURATED_JSON,
               TRY_PARSE_JSON(CURATED_JSON::VARCHAR)) AS doc
    FROM ARCHER_CONTENT_ALLOCATED_CONTROLS_CONTROL_RAW
)
SELECT a.content_id AS allocation_id, TYPEOF(a.curated_json) AS stored_json_type,
       TYPEOF(a.doc) AS decoded_json_type,
       GET(AS_OBJECT(a.doc), 'AUTHORIZATION_PACKAGE') AS package_reference_as_stored,
       GET(AS_OBJECT(a.doc), 'DIGITAL_POLICY_FRAMEWORK_DPF_REFERENCE') AS standard_reference_as_stored
FROM allocation a
ORDER BY a.content_id
LIMIT 10;

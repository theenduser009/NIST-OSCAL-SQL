-- Saved OSCAL relationships: independent read-only examples.
-- Select the database/schema containing these DIM/FACT tables first.
-- Each SELECT is a 100-row sample, not a complete coverage/reconciliation check.
-- SOURCE_RECORD_ID is the owning root record: package for SSP; Source or Policy
-- for Catalog. Referenced Allocation/Standard/group IDs are separate values.
-- Original field labels appear in ARCHER_FIELD_NAME; derived links are separate.
-- JSON text is displayed as stored; TRY_PARSE_JSON(SAVED_VALUE) can inspect it.

-- 1. Original Archer field: Authorization Package.ALLOCATED_CONTROLS.
-- Separate SSP property rows; each value is a preserved target Allocation ID.
-- This forward list is NOT the ownership rule used to build implemented requirements.
SELECT SOURCE_RECORD_ID AS AUTHORIZATION_PACKAGE_CONTENT_ID,
       'ALLOCATED_CONTROLS' AS ARCHER_FIELD_NAME,
       METADATA_JSON:value::STRING AS SAVED_VALUE
FROM DIM_OSCAL_SSP_ELEMENT
WHERE ELEMENT_TYPE = 'props'
  AND SOURCE_SYSTEM_NAME = 'ARCHER'
  AND SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW'
  AND METADATA_JSON:name::STRING = 'allocated-controls'
  AND METADATA_JSON:ns IS NULL
ORDER BY AUTHORIZATION_PACKAGE_CONTENT_ID, SAVED_VALUE
LIMIT 100;


-- 2. Allocation.CONTENT_ID and DIGITAL_POLICY_FRAMEWORK_DPF_REFERENCE.
-- Both are EMBEDDED on an existing implemented requirement, so flatten props.
-- CONTENT_ID is actual Allocation RAW identity, not native control-id and not
-- ALLOCATED_CONTROL_ID (the collection instance key).
-- Package owner below derives from the existing SSP root ownership. The original
-- Allocation.AUTHORIZATION_PACKAGE array is NOT preserved by this projection.
SELECT ir.SOURCE_RECORD_ID AS AUTHORIZATION_PACKAGE_OWNER_ID,
       ir.METADATA_JSON:"control-id"::STRING AS NATIVE_CONTROL_ID,
       CASE p.value:name::STRING
         WHEN 'archer-content-id' THEN 'CONTENT_ID'
         WHEN 'archer-control-standard-reference' THEN 'DIGITAL_POLICY_FRAMEWORK_DPF_REFERENCE'
       END AS ARCHER_FIELD_NAME,
       p.value:value::STRING AS SAVED_VALUE
FROM DIM_OSCAL_SSP_ELEMENT ir,
     LATERAL FLATTEN(INPUT => ir.METADATA_JSON:props) p
WHERE ir.ELEMENT_TYPE = 'implemented-requirements'
  AND ir.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND ir.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORIZATION_PACKAGE_RAW'
  AND ((p.value:name::STRING = 'archer-content-id' AND p.value:ns IS NULL)
    OR (p.value:name::STRING = 'archer-control-standard-reference'
        AND p.value:ns::STRING = 'urn:archer:source:v1'))
ORDER BY AUTHORIZATION_PACKAGE_OWNER_ID, NATIVE_CONTROL_ID, ARCHER_FIELD_NAME
LIMIT 100;

-- 3. Original Standard fields: POLICY_HIERARCHY_LEVEL_1_2_3 / AUTHORITATIVE_SOURCES.
-- The embedded unnamespaced archer-content-id identifies the Standard target.
-- policy-hierarchy-level-1-2-3 is JSON-preserved source data.
-- authoritative-sources is RESOLVED output [{ContentId,ModuleId,Name}]; invalid,
-- missing or ambiguous targets can be omitted by that recipe. It is not raw equality.
-- Duplicate Standard IDs across different Catalog roots are legitimate placements.
SELECT c.SOURCE_TABLE_NAME AS CATALOG_SOURCE,
       c.SOURCE_RECORD_ID AS CATALOG_ROOT_CONTENT_ID,
       sid.value:value::STRING AS CONTROL_STANDARD_CONTENT_ID,
       c.METADATA_JSON:id::STRING AS NATIVE_CONTROL_ID,
       CASE p.value:name::STRING
         WHEN 'policy-hierarchy-level-1-2-3' THEN 'POLICY_HIERARCHY_LEVEL_1_2_3'
         WHEN 'authoritative-sources' THEN 'AUTHORITATIVE_SOURCES'
       END AS ARCHER_FIELD_NAME,
       p.value:value::STRING AS SAVED_VALUE
FROM DIM_OSCAL_CATALOG_ELEMENT c,
     LATERAL FLATTEN(INPUT => c.METADATA_JSON:props) sid,
     LATERAL FLATTEN(INPUT => c.METADATA_JSON:props) p
WHERE c.ELEMENT_TYPE = 'controls'
  AND c.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND c.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW'
  AND sid.value:name::STRING = 'archer-content-id' AND sid.value:ns IS NULL
  AND p.value:name::STRING IN ('policy-hierarchy-level-1-2-3', 'authoritative-sources')
  AND p.value:ns::STRING = 'urn:archer:source:v1'
ORDER BY CATALOG_SOURCE, CATALOG_ROOT_CONTENT_ID, CONTROL_STANDARD_CONTENT_ID, ARCHER_FIELD_NAME
LIMIT 100;

-- 4. Derived Standard Subsection/Section reference, not another raw Archer field.
-- Same namespace; value contains Subsection ContentId/LevelId/ModuleId and an
-- optional Section object. Missing names/targets remain diagnostic conditions.
SELECT c.SOURCE_RECORD_ID AS CATALOG_ROOT_CONTENT_ID,
       sid.value:value::STRING AS CONTROL_STANDARD_CONTENT_ID,
       p.value:name::STRING AS SAVED_PROPERTY_NAME,
       p.value:value::STRING AS SAVED_VALUE
FROM DIM_OSCAL_CATALOG_ELEMENT c,
     LATERAL FLATTEN(INPUT => c.METADATA_JSON:props) sid,
     LATERAL FLATTEN(INPUT => c.METADATA_JSON:props) p
WHERE c.ELEMENT_TYPE = 'controls'
  AND c.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND c.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW'
  AND sid.value:name::STRING = 'archer-content-id' AND sid.value:ns IS NULL
  AND p.value:name::STRING = 'authoritative-subsection-reference'
  AND p.value:ns::STRING = 'urn:archer:source:v1'
ORDER BY CATALOG_ROOT_CONTENT_ID, CONTROL_STANDARD_CONTENT_ID
LIMIT 100;

-- 5. Policy Level 1/2/3 original reference fields, JSON-preserved in SEPARATE
-- Catalog props rows beneath each Policy group. SOURCE_RECORD_ID is that Policy ID.
-- L1: POLICY_LEVEL_2_REFERENCE / POLICY_LEVEL_3_REFERENCE (child references).
-- L2: POLICY_LEVEL_1_REFERENCE (parent) / POLICY_LEVEL_3_REFERENCE (child).
-- L3: POLICY_LEVEL_2_REFERENCE (parent), AUTHORITATIVE_SOURCES and other crossrefs.
-- These are preserved values, not cross-document native containment/imports.
SELECT p.SOURCE_TABLE_NAME AS POLICY_SOURCE,
       p.SOURCE_RECORD_ID AS POLICY_CONTENT_ID,
       g.METADATA_JSON:id::STRING AS NATIVE_POLICY_GROUP_ID,
       CASE p.METADATA_JSON:name::STRING
         WHEN 'policy-level-1-reference' THEN 'POLICY_LEVEL_1_REFERENCE'
         WHEN 'policy-level-2-reference' THEN 'POLICY_LEVEL_2_REFERENCE'
         WHEN 'policy-level-3-reference' THEN 'POLICY_LEVEL_3_REFERENCE'
         WHEN 'authoritative-sources' THEN 'AUTHORITATIVE_SOURCES'
         WHEN 'authoritative-source-references' THEN 'AUTHORITATIVE_SOURCE_REFERENCES'
       END AS ARCHER_FIELD_NAME,
       p.METADATA_JSON:value::STRING AS SAVED_VALUE
FROM DIM_OSCAL_CATALOG_ELEMENT p
JOIN FACT_OSCAL_CATALOG_DEPENDENCY f
  ON f.FK_TARGET_ELEMENT_HASH = p.PK_DIM_OSCAL_CATALOG_ELEMENT_HASH
 AND f.DEPENDENCY_TYPE = 'CONTAINS'
JOIN DIM_OSCAL_CATALOG_ELEMENT g
  ON g.PK_DIM_OSCAL_CATALOG_ELEMENT_HASH = f.FK_SOURCE_ELEMENT_HASH
WHERE p.ELEMENT_TYPE = 'props' AND g.ELEMENT_TYPE = 'groups'
  AND p.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND g.SOURCE_SYSTEM_NAME = p.SOURCE_SYSTEM_NAME
  AND g.SOURCE_TABLE_NAME = p.SOURCE_TABLE_NAME
  AND g.SOURCE_RECORD_ID = p.SOURCE_RECORD_ID
  AND p.SOURCE_TABLE_NAME IN ('ARCHER_CONTENT_POLICIES_POLICY_LEVEL_1_RAW',
      'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW', 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW')
  AND p.METADATA_JSON:ns::STRING = 'urn:archer:source:v1'
  AND p.METADATA_JSON:name::STRING IN ('policy-level-1-reference', 'policy-level-2-reference',
      'policy-level-3-reference', 'authoritative-sources', 'authoritative-source-references')
ORDER BY POLICY_SOURCE, POLICY_CONTENT_ID, ARCHER_FIELD_NAME
LIMIT 100;

-- 6. Authoritative Source/Topic/Section/Subsection native hierarchy.
-- SOURCE_REFERENCES, TOPIC_REFERENCES and SECTION_REFERENCES were consumed into
-- first-member reverse ownership; no same-named complete parent arrays are saved.
-- These rows deliberately show native containment, not reconstructed original arrays.
-- A root Catalog may have no native id; CATALOG_ROOT_CONTENT_ID still identifies it.
SELECT parent.SOURCE_RECORD_ID AS CATALOG_ROOT_CONTENT_ID,
       parent.ELEMENT_TYPE AS PARENT_ELEMENT_TYPE,
       parent.METADATA_JSON:id::STRING AS NATIVE_PARENT_ID,
       child.METADATA_JSON:id::STRING AS NATIVE_CHILD_ID,
       'CONTAINS' AS SAVED_RELATIONSHIP
FROM DIM_OSCAL_CATALOG_ELEMENT parent
JOIN FACT_OSCAL_CATALOG_DEPENDENCY f
  ON f.FK_SOURCE_ELEMENT_HASH = parent.PK_DIM_OSCAL_CATALOG_ELEMENT_HASH
 AND f.DEPENDENCY_TYPE = 'CONTAINS'
JOIN DIM_OSCAL_CATALOG_ELEMENT child
  ON child.PK_DIM_OSCAL_CATALOG_ELEMENT_HASH = f.FK_TARGET_ELEMENT_HASH
WHERE parent.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW'
  AND parent.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND child.SOURCE_SYSTEM_NAME = parent.SOURCE_SYSTEM_NAME
  AND child.SOURCE_TABLE_NAME = parent.SOURCE_TABLE_NAME
  AND child.SOURCE_RECORD_ID = parent.SOURCE_RECORD_ID
  AND parent.ELEMENT_TYPE IN ('catalog', 'groups') AND child.ELEMENT_TYPE = 'groups'
ORDER BY CATALOG_ROOT_CONTENT_ID, NATIVE_PARENT_ID, NATIVE_CHILD_ID
LIMIT 100;

-- 7. Native Control Standard placements beneath Catalog/group owners.
-- Standard CID is the referenced target; Catalog root CID is its owning document.
-- Placement CONTAINS does not recover every original CONTROL_STANDARDS array:
-- shared controls can move to a common/root owner and originating groups retain
-- related fragment links. Policy Level 2 merges CONTROL_STANDARDS with
-- CONTROL_STANDARD_REQUIREMENTS; the individual field origin is NOT recoverable
-- from these saved placements/links. Never select an arbitrary first Catalog.
SELECT c.SOURCE_TABLE_NAME AS CATALOG_SOURCE,
       c.SOURCE_RECORD_ID AS CATALOG_ROOT_CONTENT_ID,
       sid.value:value::STRING AS CONTROL_STANDARD_CONTENT_ID,
       c.METADATA_JSON:id::STRING AS NATIVE_CONTROL_ID,
       owner.ELEMENT_TYPE AS OWNER_ELEMENT_TYPE,
       owner.METADATA_JSON:id::STRING AS NATIVE_OWNER_ID,
       CASE WHEN c.SOURCE_TABLE_NAME = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW'
            THEN 'MERGED_CONTROL_FIELDS_NOT_RECOVERABLE'
            ELSE 'NATIVE_PLACEMENT_NOT_ORIGINAL_REFERENCE_ARRAY'
       END AS RELATIONSHIP_NOTE
FROM DIM_OSCAL_CATALOG_ELEMENT c
JOIN FACT_OSCAL_CATALOG_DEPENDENCY f
  ON f.FK_TARGET_ELEMENT_HASH = c.PK_DIM_OSCAL_CATALOG_ELEMENT_HASH
 AND f.DEPENDENCY_TYPE = 'CONTAINS'
JOIN DIM_OSCAL_CATALOG_ELEMENT owner
  ON owner.PK_DIM_OSCAL_CATALOG_ELEMENT_HASH = f.FK_SOURCE_ELEMENT_HASH,
     LATERAL FLATTEN(INPUT => c.METADATA_JSON:props) sid
WHERE c.ELEMENT_TYPE = 'controls'
  AND c.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND owner.SOURCE_SYSTEM_NAME = c.SOURCE_SYSTEM_NAME
  AND owner.SOURCE_TABLE_NAME = c.SOURCE_TABLE_NAME
  AND owner.SOURCE_RECORD_ID = c.SOURCE_RECORD_ID
  AND owner.ELEMENT_TYPE IN ('catalog', 'groups')
  AND sid.value:name::STRING = 'archer-content-id' AND sid.value:ns IS NULL
ORDER BY CATALOG_SOURCE, CATALOG_ROOT_CONTENT_ID, CONTROL_STANDARD_CONTENT_ID
LIMIT 100;

-- 8. Related fragment links retain connections beyond the single containment owner.
-- These are saved native links, not copies of the original Archer reference arrays.
-- A displayed href is not independently checked for target resolution by this query.
SELECT d.SOURCE_TABLE_NAME AS CATALOG_SOURCE,
       d.SOURCE_RECORD_ID AS CATALOG_ROOT_CONTENT_ID,
       d.ELEMENT_TYPE AS OWNER_ELEMENT_TYPE,
       d.METADATA_JSON:id::STRING AS NATIVE_OWNER_ID,
       l.VALUE:rel::STRING AS SAVED_RELATIONSHIP,
       l.VALUE:href::STRING AS REFERENCED_OSCAL_HREF
FROM DIM_OSCAL_CATALOG_ELEMENT d,
     LATERAL FLATTEN(INPUT => d.METADATA_JSON:links) l
WHERE d.SOURCE_SYSTEM_NAME = 'ARCHER'
  AND d.ELEMENT_TYPE IN ('groups', 'controls')
  AND d.SOURCE_TABLE_NAME IN (
      'ARCHER_CONTENT_AUTHORITATIVE_SOURCES_SOURCE_RAW',
      'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_1_RAW',
      'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_2_RAW',
      'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW')
  AND l.VALUE:rel::STRING = 'related'
  AND STARTSWITH(l.VALUE:href::STRING, '#')
ORDER BY CATALOG_SOURCE, CATALOG_ROOT_CONTENT_ID, NATIVE_OWNER_ID, REFERENCED_OSCAL_HREF
LIMIT 100;

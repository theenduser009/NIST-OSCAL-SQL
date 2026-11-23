-- Policy Level 3 source and saved target values. Snowflake DEV. Read-only.
-- Selects the lowest Content ID with a populated source value for each field.
-- For a documented worksheet alias, the source uses the exact key when present.
-- A null selector means the reviewed mapping has no verified saved target.
WITH fields AS (
    SELECT column1 AS seq, column2 AS field_name, column3::VARCHAR AS requested_id,
           column4 AS mapped_field, column5 AS selector, column6 AS payload_key
    FROM VALUES
        (1, 'ABBREVIATION', NULL, NULL, 'group_prop', 'abbreviation'),
        (2, 'ACTIVATED_PLANS_POLICIES', NULL, NULL, 'group_prop', 'activated-plans-policies'),
        (3, 'ADMIN_POLICY_NAME', NULL, NULL, 'group_prop', 'admin-policy-name'),
        (4, 'APPLICABILITY', NULL, NULL, 'group_prop', 'applicability'),
        (5, 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_CONFIRMED_IN_ARCHER', NULL, NULL, 'group_prop', 'confirmed-date'),
        (6, 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_CONTENT_ID', NULL, NULL, 'group_prop', 'archer-content-id'),
        (7, 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_FIRST_PUBLISHED', NULL, NULL, 'metadata', 'published'),
        (8, 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_LAST_UPDATED', NULL, NULL, 'metadata', 'last-modified'),
        (9, 'AUTHORITATIVE_SOURCES', NULL, NULL, 'group_prop', 'authoritative-sources'),
        (10, 'AUTHORITATIVE_SOURCES_POLICY_LEVEL_3_FROM_SECTION_AND_SUBSECTION_LEVELS', NULL, NULL, 'group_prop', 'authoritative-sources-policy-level-3-from-section-and-subsection-levels'),
        (11, 'AUTHORITATIVE_SOURCES_POLICY_LEVEL_3__FROM_SECTION_AND_SUBSECTION_LEVELS', NULL, NULL, NULL, NULL),
        (12, 'AUTHORITATIVE_SOURCES_POLICY_LEVEL_3_FROM_SECTION_LEVEL_AND_BELOW', NULL, NULL, 'group_prop', 'authoritative-sources-policy-level-3-from-section-level-and-below'),
        (13, 'AUTHORITATIVE_SOURCES_POLICY_LEVEL_3_FROM_TOPIC_SECTION_AND_SUBSECTION_LEVELS', NULL, NULL, 'group_prop', 'authoritative-sources-policy-level-3-from-topic-section-and-subsection-levels'),
        (14, 'BUSINESS_CONTINUITY_PLANS', NULL, NULL, 'group_prop', 'business-continuity-plans'),
        (15, 'CHECKSUM_VALUE', NULL, NULL, NULL, NULL),
        (16, 'COMPLIANCE_ENGAGEMENTS_SCOPE_PROCEDURES_FROM_SELECTED_POLICY_TOPICS', NULL, NULL, 'group_prop', 'compliance-engagements-scope-procedures-from-selected-policy-topics'),
        (17, 'CONTROL_PROCEDURES', NULL, NULL, 'procedures', 'description'),
        (18, 'CONTROL_REQUIREMENTS_CONTROL_STANDARD_POLICY', NULL, NULL, NULL, NULL),
        (19, 'CONTROL_REQUIREMENTS_FUNCTIONAL_CORPORATE_POLICIES', NULL, NULL, NULL, NULL),
        (20, 'CONTROL_STANDARD_REQUIREMENTS', NULL, NULL, 'standards', NULL),
        (21, 'CONTROL_STANDARD_TYPE_LEVEL_3', NULL, NULL, 'group_prop', 'control-standard-type-level-3'),
        (22, 'CONTROL_STANDARDS_CALCULATED_POLICY_LEVEL_3_FIELD_VALUE_MATCH', NULL, NULL, 'group_prop', 'control-standards-calculated-policy-level-3-field-value-match'),
        (23, 'CONTROL_STANDARDS_CALCULATED_POLICY_LEVEL_3__FIELD_VALUE_MATCH', NULL, NULL, NULL, NULL),
        (24, 'CONTROL_TESTING_RESULTS_FAILED_POLICY_LEVEL_3', NULL, NULL, 'findings_prop', 'failed-test-result'),
        (25, 'CONTROL_TESTING_RESULTS_POLICY', NULL, NULL, 'findings_prop', 'test-result'),
        (26, 'COUNT_OF_OBJECTIVES', NULL, NULL, 'group_prop', 'objective-count'),
        (27, 'COUNT_OF_OPEN_POAMS', NULL, NULL, 'results_prop', 'open-poam-count'),
        (28, 'DEFAULT_RECORD_PERMISSIONS', NULL, NULL, 'group_prop', 'default-record-permissions'),
        (29, 'DCMA_CONTROL_SCORE_AVERAGE_SUM', NULL, NULL, 'results_prop', 'dcma-control-score-average-sum'),
        (30, 'DOCUMENT_REPOSITORY', NULL, NULL, NULL, NULL),
        (31, 'EVIDENCE_REPOSITORY_POLICY_LEVEL_3', NULL, NULL, NULL, NULL),
        (32, 'EVIDENCE_REPOSITORY_RELATED_POLICY_LEVEL_3', NULL, NULL, NULL, NULL),
        (33, 'EXECUTIVE_OWNER', NULL, NULL, 'group_prop', 'executive-owner'),
        (34, 'EXCEPTION_REQUESTS_POLICIES', NULL, NULL, NULL, NULL),
        (35, 'FINDINGS', NULL, NULL, 'findings', 'title'),
        (36, 'FINDINGS_POLICY_LEVEL_3', NULL, NULL, 'findings', 'title'),
        (37, 'FINDINGS_POLICY_LEVEL_3_FROM_DEVIATIONS_DO_NOT_USE2', NULL, NULL, NULL, NULL),
        (38, 'FINDINGS_POLICY_LEVEL_3_FROM_DEVIATIONS__DO_NOT_USE2', NULL, NULL, NULL, NULL),
        (39, 'FINDINGS_POLICY__LEVEL_3', NULL, 'FINDINGS_POLICY_LEVEL_3', 'findings', 'title'),
        (40, 'FINDINGS_POLICIES_CALCULATED_LEVEL_3', NULL, NULL, 'group_prop', 'findings-policies-calculated-level-3'),
        (41, 'FINDINGS_POLICIES__CALCULATED_LEVEL_3', NULL, NULL, NULL, NULL),
        (42, 'FCP_POLICY_LEVEL_1_NAME', NULL, NULL, 'group_prop', 'fcp-policy-level-1-name'),
        (43, 'FCP_POLICY_LEVEL_2_NAME', NULL, NULL, 'group_prop', 'fcp-policy-level-2-name'),
        (44, 'FCP_POLICY_LEVEL_3_NAME', NULL, NULL, 'group_prop', 'fcp-policy-level-3-name'),
        (45, 'GLOSSARY', NULL, NULL, NULL, NULL),
        (46, 'HELPER_POLICY_FEED', NULL, NULL, 'group_prop', 'helper-policy-feed'),
        (47, 'INSERT_DATE', NULL, NULL, NULL, NULL),
        (48, 'ISSUES_POLICIES', NULL, NULL, 'findings_prop', 'issue'),
        (49, 'ISSUES_POLICIES1', NULL, NULL, NULL, NULL),
        (50, 'LINKED_POLICY_CHANGED_DATE', NULL, NULL, 'group_prop', 'linked-policy-changed-date'),
        (51, 'META_DATA', NULL, NULL, 'group_prop', 'meta-data'),
        (52, 'NEW_AUTH_SOURCE_CALC_CROSSREF_SECTION', NULL, NULL, 'group_prop', 'new-auth-source-calc-crossref-section'),
        (53, 'NEW_AUTH_SOURCE_CALC_CROSSREF_SUBSECTION', NULL, NULL, 'group_prop', 'new-auth-source-calc-crossref-subsection'),
        (54, 'POLICIES_FCP_POLICY_LEVEL_3_NAME', NULL, NULL, 'group_prop', 'policies-fcp-policy-level-3-name'),
        (55, 'POLICIES_POLICY__LEVEL_3', NULL, NULL, NULL, NULL),
        (56, 'POLICIES_POLICY_TO_POLICY_CROSSREF', NULL, NULL, 'group_prop', 'policies-policy-to-policy-crossref'),
        (57, 'POLICY_CHANGE_RECOMMENDATION_POLICIES', NULL, NULL, 'group_prop', 'policy-change-recommendation-policies'),
        (58, 'POLICY_HIERARCHY_1_2_3', NULL, NULL, 'group_prop', 'policy-hierarchy-1-2-3'),
        (59, 'POLICY_LEVEL_1_NAME', NULL, NULL, 'group_prop', 'policy-level-1-name'),
        (60, 'POLICY_LEVEL_2_NAME', NULL, NULL, 'group_prop', 'policy-level-2-name'),
        (61, 'POLICY_LEVEL_2_REFERENCE', NULL, NULL, 'group_prop', 'policy-level-2-reference'),
        (62, 'POLICY_LEVEL_3_NAME', NULL, NULL, 'groups', 'title'),
        (63, 'POLICY_LEVEL_3_OWNER', NULL, NULL, 'group_prop', 'policy-owner'),
        (64, 'POLICY_LEVEL_3_STATEMENT', NULL, NULL, 'group_part', 'statement'),
        (65, 'POLICY_LEVEL_3_TRACKING_ID', NULL, NULL, 'group_prop', 'tracking-id'),
        (66, 'POLICY_NAME', NULL, NULL, 'group_prop', 'policy-name'),
        (67, 'POLICY_NUMBER', NULL, NULL, 'groups', 'id'),
        (68, 'POLICY_TOPIC_NAME', NULL, NULL, 'group_prop', 'policy-topic-name'),
        (69, 'POLICY__LEVEL_1_NAME', NULL, 'POLICY_LEVEL_1_NAME', 'group_prop', 'policy-level-1-name'),
        (70, 'POLICY__LEVEL_2_NAME', NULL, 'POLICY_LEVEL_2_NAME', 'group_prop', 'policy-level-2-name'),
        (71, 'POLICY__LEVEL_2_REFERENCE', NULL, 'POLICY_LEVEL_2_REFERENCE', 'group_prop', 'policy-level-2-reference'),
        (72, 'POLICY__LEVEL_3_NAME', NULL, 'POLICY_LEVEL_3_NAME', 'groups', 'title'),
        (73, 'POLICY__LEVEL_3_OWNER', NULL, 'POLICY_LEVEL_3_OWNER', 'group_prop', 'policy-owner'),
        (74, 'POLICY__LEVEL_3_STATEMENT', NULL, 'POLICY_LEVEL_3_STATEMENT', 'group_part', 'statement'),
        (75, 'POLICY__LEVEL_3_TRACKING_ID', NULL, 'POLICY_LEVEL_3_TRACKING_ID', 'group_prop', 'tracking-id'),
        (76, 'POLICIES_POLICY__LEVEL_3_POLICY_HIERARCHY_1_2_3', NULL, 'POLICIES_POLICY_LEVEL_3_POLICY_HIERARCHY_1_2_3', 'group_prop', 'policy-hierarchy-1-2-3'),
        (77, 'POLICIES_POLICY_LEVEL_3_POLICY_HIERARCHY_1_2_3', NULL, NULL, 'group_prop', 'policy-hierarchy-1-2-3'),
        (78, 'POLICIES_POLICY_LEVEL_3', NULL, NULL, 'group_prop', 'policies-policy-level-3'),
        (79, 'PURPOSE', NULL, NULL, 'group_part_default_ns', 'overview'),
        (80, 'QUESTION_LIBRARY', NULL, NULL, 'activities_prop', 'question-library'),
        (81, 'REGULATORY_TESTING_SCOPE', NULL, NULL, 'group_prop', 'regulatory-testing-scope'),
        (82, 'RETIRED_DATE', NULL, NULL, 'group_prop', 'retired-date'),
        (83, 'SECTION_DATE_CREATED', NULL, NULL, 'group_prop', 'date-created'),
        (84, 'SECTION_LAST_UPDATED', NULL, NULL, 'group_prop', 'last-updated'),
        (85, 'SOX_CONTROL', NULL, NULL, 'group_prop', 'sox-control'),
        (86, 'SOX_REFERENCE_ID', NULL, NULL, 'group_prop', 'sox-reference-id'),
        (87, 'SORT_ORDER', NULL, NULL, 'group_prop', 'sort-order'),
        (88, 'STATUS', NULL, NULL, 'group_prop', 'status'),
        (89, 'UPDATE_DATE', NULL, NULL, NULL, NULL)
),
layouts AS (
    SELECT column1 AS selector, column2 AS model, column3 AS node_type, column4 AS parent_type,
           column5 AS mode, column6 AS member_name, column7 AS namespace
    FROM VALUES
        ('group_prop', 'CATALOG', 'props', 'groups', 'property', 'value', 'urn:archer:source:v1'),
        ('metadata', 'CATALOG', 'metadata', 'catalog', 'member', NULL, NULL),
        ('procedures', 'COMPONENT_DEFINITION', 'implemented-requirements', 'control-implementations', 'procedures', 'description', NULL),
        ('findings_prop', 'ASSESSMENT_RESULTS', 'props', 'findings', 'property', 'value', 'urn:archer:source:v1'),
        ('results_prop', 'ASSESSMENT_RESULTS', 'props', 'results', 'property', 'value', 'urn:archer:source:v1'),
        ('findings', 'ASSESSMENT_RESULTS', 'findings', 'results', 'findings', 'title', NULL),
        ('groups', 'CATALOG', 'groups', 'catalog', 'member', NULL, NULL),
        ('group_part', 'CATALOG', 'parts', 'groups', 'property', 'prose', 'urn:archer:source:v1'),
        ('group_part_default_ns', 'CATALOG', 'parts', 'groups', 'property', 'prose', NULL),
        ('activities_prop', 'SECURITY_ASSESSMENT_PLAN', 'props', 'activities', 'property', 'value', 'urn:archer:source:v1')
),
raw_rows AS (
    SELECT CONTENT_ID::VARCHAR AS content_id, TRY_PARSE_JSON(CURATED_JSON::VARCHAR) AS doc
    FROM RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW WHERE CONTENT_ID IS NOT NULL
),
source_rows AS (
    SELECT f.*, COALESCE(r.content_id, f.requested_id) AS content_id,
           COALESCE(GET(AS_OBJECT(r.doc), f.field_name), GET(AS_OBJECT(r.doc), f.mapped_field)) AS source_value,
           GET(AS_OBJECT(r.doc), COALESCE(f.mapped_field, f.field_name)) AS mapped_source_value
    FROM fields f LEFT JOIN raw_rows r ON f.requested_id IS NULL OR r.content_id = f.requested_id
),
picked AS (
    SELECT * FROM source_rows
    QUALIFY requested_id IS NOT NULL OR ROW_NUMBER() OVER (
        PARTITION BY seq ORDER BY
        CASE WHEN source_value IS NULL OR IS_NULL_VALUE(source_value)
               OR NULLIF(TRIM(AS_VARCHAR(source_value)), '') = ''
               OR ARRAY_SIZE(AS_ARRAY(source_value)) = 0 THEN 1 ELSE 0 END,
        TRY_TO_NUMBER(content_id), content_id
    ) = 1
),
nodes AS (
    SELECT 'CATALOG' AS model, SOURCE_RECORD_ID AS content_id,
           PK_DIM_OSCAL_CATALOG_ELEMENT_HASH AS node_key, ELEMENT_TYPE AS kind, METADATA_JSON AS doc
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.DIM_OSCAL_CATALOG_ELEMENT
    WHERE SOURCE_SYSTEM_NAME = 'ARCHER' AND SOURCE_TABLE_NAME = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW'
      AND SOURCE_RECORD_ID IN (SELECT content_id FROM picked)
    UNION ALL
    SELECT 'SECURITY_ASSESSMENT_PLAN' AS model, SOURCE_RECORD_ID AS content_id,
           PK_DIM_OSCAL_ASSESSMENT_PLAN_ELEMENT_HASH AS node_key, ELEMENT_TYPE AS kind, METADATA_JSON AS doc
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.DIM_OSCAL_ASSESSMENT_PLAN_ELEMENT
    WHERE SOURCE_SYSTEM_NAME = 'ARCHER' AND SOURCE_TABLE_NAME = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW'
      AND SOURCE_RECORD_ID IN (SELECT content_id FROM picked)
    UNION ALL
    SELECT 'ASSESSMENT_RESULTS' AS model, SOURCE_RECORD_ID AS content_id,
           PK_DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT_HASH AS node_key, ELEMENT_TYPE AS kind, METADATA_JSON AS doc
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.DIM_OSCAL_ASSESSMENT_RESULTS_ELEMENT
    WHERE SOURCE_SYSTEM_NAME = 'ARCHER' AND SOURCE_TABLE_NAME = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW'
      AND SOURCE_RECORD_ID IN (SELECT content_id FROM picked)
    UNION ALL
    SELECT 'COMPONENT_DEFINITION' AS model, SOURCE_RECORD_ID AS content_id,
           PK_DIM_OSCAL_COMPONENT_ELEMENT_HASH AS node_key, ELEMENT_TYPE AS kind, METADATA_JSON AS doc
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.DIM_OSCAL_COMPONENT_ELEMENT
    WHERE SOURCE_SYSTEM_NAME = 'ARCHER' AND SOURCE_TABLE_NAME = 'ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW'
      AND SOURCE_RECORD_ID IN (SELECT content_id FROM picked)
),
edges AS (
    SELECT 'CATALOG' AS model, FK_SOURCE_ELEMENT_HASH AS parent_key, FK_TARGET_ELEMENT_HASH AS child_key
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.FACT_OSCAL_CATALOG_DEPENDENCY WHERE DEPENDENCY_TYPE = 'CONTAINS'
    UNION ALL
    SELECT 'SECURITY_ASSESSMENT_PLAN' AS model, FK_SOURCE_ELEMENT_HASH AS parent_key, FK_TARGET_ELEMENT_HASH AS child_key
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.FACT_OSCAL_ASSESSMENT_PLAN_DEPENDENCY WHERE DEPENDENCY_TYPE = 'CONTAINS'
    UNION ALL
    SELECT 'ASSESSMENT_RESULTS' AS model, FK_SOURCE_ELEMENT_HASH AS parent_key, FK_TARGET_ELEMENT_HASH AS child_key
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.FACT_OSCAL_ASSESSMENT_RESULTS_DEPENDENCY WHERE DEPENDENCY_TYPE = 'CONTAINS'
    UNION ALL
    SELECT 'COMPONENT_DEFINITION' AS model, FK_SOURCE_ELEMENT_HASH AS parent_key, FK_TARGET_ELEMENT_HASH AS child_key
    FROM RTX_ENTERPRISESERVICES_DEV.ES_ESC_GRC_CURATED.FACT_OSCAL_COMPONENT_DEPENDENCY WHERE DEPENDENCY_TYPE = 'CONTAINS'
),
attached AS (
    SELECT n.*, p.kind AS parent_type
    FROM nodes n JOIN edges e ON e.model = n.model AND e.child_key = n.node_key
    JOIN nodes p ON p.model = n.model AND p.content_id = n.content_id AND p.node_key = e.parent_key
),
direct_targets AS (
    SELECT DISTINCT r.seq, r.content_id, n.node_key,
           GET(AS_OBJECT(n.doc), COALESCE(l.member_name, r.payload_key)) AS target_value
    FROM picked r JOIN layouts l ON l.selector = r.selector AND l.mode IN ('member', 'property')
    JOIN attached n ON n.content_id = r.content_id AND n.model = l.model
                   AND n.kind = l.node_type AND n.parent_type = l.parent_type
    WHERE l.mode = 'member'
       OR (n.doc:name::VARCHAR = r.payload_key AND
           (l.namespace IS NULL OR n.doc:ns::VARCHAR = l.namespace))
),
standard_links AS (
    SELECT DISTINCT r.seq, r.content_id, link.value:href::VARCHAR AS href
    FROM picked r JOIN attached g ON g.content_id = r.content_id AND g.model = 'CATALOG'
                             AND g.kind = 'groups' AND g.parent_type = 'catalog',
         LATERAL FLATTEN(INPUT => g.doc:links) link
    WHERE r.selector = 'standards' AND link.value:rel::VARCHAR = 'related'
),
standards AS (
    SELECT n.content_id, n.node_key,
           '#' || ARRAY_TO_STRING(TRANSFORM(REGEXP_SUBSTR_ALL(n.doc:id::VARCHAR, '.'), ch ->
               IFF(REGEXP_LIKE(ch::VARCHAR, '[A-Za-z0-9_.~-]'), ch::VARCHAR,
                   REGEXP_REPLACE(HEX_ENCODE(ch::VARCHAR), '(..)', '%\\1'))), '') AS href,
           TO_VARIANT(OBJECT_CONSTRUCT_KEEP_NULL('ContentId', p.value:value::VARCHAR,
                                                'Name', n.doc:title::VARCHAR)) AS target_value
    FROM nodes n, LATERAL FLATTEN(INPUT => n.doc:props) p
    WHERE n.model = 'CATALOG' AND n.kind = 'controls' AND p.value:name::VARCHAR = 'archer-content-id'
),
forward_layouts AS (
    SELECT column1 AS source_field, column2 AS target_table, column3 AS target_level, column4 AS node_path
    FROM VALUES
        ('CONTROL_PROCEDURES', 'RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_CONTROL_PROCEDURES_RAW', '39', 'component-definition.components[].control-implementations[].implemented-requirements[]'),
        ('FINDINGS', 'RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_FINDINGS_RAW', '62', 'assessment-results.results[].findings[]'),
        ('FINDINGS_POLICY_LEVEL_3', 'RTX_RAW_DEV.ES_ESC_GRC.ARCHER_CONTENT_FINDINGS_RAW', '62', 'assessment-results.results[].findings[]')
),
forward_ids AS (
    SELECT DISTINCT r.seq, r.content_id, l.model, l.node_type, l.parent_type, l.member_name,
           f.source_field, f.target_table, f.node_path,
           IFF(IS_OBJECT(m.value), m.value:ContentId, m.value)::VARCHAR AS referenced_id
    FROM picked r JOIN layouts l ON l.selector = r.selector AND l.mode IN ('procedures', 'findings')
    JOIN forward_layouts f ON f.source_field = COALESCE(r.mapped_field, r.field_name),
         LATERAL FLATTEN(INPUT => IFF(IS_ARRAY(r.mapped_source_value),
             AS_ARRAY(r.mapped_source_value), ARRAY_CONSTRUCT_COMPACT(r.mapped_source_value))) m
    WHERE m.value:LevelId IS NULL OR m.value:LevelId::VARCHAR = f.target_level
),
forward_targets AS (
    SELECT DISTINCT f.seq, f.content_id, n.node_key,
           TO_VARIANT(OBJECT_CONSTRUCT_KEEP_NULL('ContentId', f.referenced_id,
               f.member_name, GET(AS_OBJECT(n.doc), f.member_name))) AS target_value
    FROM forward_ids f JOIN attached n ON n.content_id = f.content_id AND n.model = f.model
                   AND n.kind = f.node_type AND n.parent_type = f.parent_type
                   AND n.node_key = MD5_BINARY(
                       'v1_registry_path_instance|ARCHER|ARCHER_CONTENT_POLICIES_POLICY_LEVEL_3_RAW|' ||
                       f.content_id || '|' || f.model || '|' || f.node_path || '|' ||
                       TO_JSON(ARRAY_CONSTRUCT(f.source_field, f.target_table, f.referenced_id)))
    WHERE REGEXP_LIKE(f.referenced_id, '[1-9][0-9]*')
),
target_rows AS (
    SELECT * FROM direct_targets
    UNION ALL
    SELECT DISTINCT l.seq, l.content_id, s.node_key, s.target_value
    FROM standard_links l JOIN standards s ON s.content_id = l.content_id AND s.href = l.href
    UNION ALL
    SELECT * FROM forward_targets
),
saved AS (
    SELECT seq, content_id, COUNT(*) AS item_count,
           ARRAY_AGG(COALESCE(target_value, PARSE_JSON('null')))
               WITHIN GROUP (ORDER BY node_key) AS items
    FROM target_rows GROUP BY seq, content_id
)
SELECT r.field_name, r.content_id AS archer_content_id, r.source_value,
       CASE WHEN s.item_count = 1 THEN GET(s.items, 0)
            WHEN s.item_count > 1 THEN TO_VARIANT(s.items) END AS target_value
FROM picked r LEFT JOIN saved s ON s.seq = r.seq AND s.content_id = r.content_id
ORDER BY r.seq, r.content_id;

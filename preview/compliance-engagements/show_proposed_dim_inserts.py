# Run in a new Python cell after the Compliance Engagements Preview in Cell 7.
# Compare the same graph's proposed DIM keys with the current target table.
source_key = "source-three-compliance-engagements"
route = (source_key, "SECURITY_ASSESSMENT_PLAN")
engagement_graph = MODEL_GRAPHS[route]
config = engagement_graph["context"]["config"]

target_dim_keys = session.table(config["TARGET_DIM"]).select_expr(
    f'{config["DIM_PK_COLUMN"]} AS DIM_KEY'
)

candidate_dim_rows = engagement_graph["nodes"].select_expr(
    "TO_BINARY(NODE_KEY, 'HEX') AS DIM_KEY",
    "SOURCE_RECORD_ID AS CONTENT_ID",
    "ELEMENT_PATH",
    "AS_VARCHAR(GET(TRY_PARSE_JSON(METADATA_JSON::VARCHAR), 'title')) AS OSCAL_TITLE",
    "METADATA_JSON AS PREVIEW_PAYLOAD",
)

source_names = SOURCE_INPUTS[source_key]["source_df"].select_expr(
    "SOURCE_RECORD_ID AS CONTENT_ID",
    "AS_VARCHAR(GET(TRY_PARSE_JSON(CURATED_JSON::VARCHAR), 'ENGAGEMENT_NAME')) AS ARCHER_ENGAGEMENT_NAME",
)

proposed_dim_inserts = (
    candidate_dim_rows
    .join(target_dim_keys, ["DIM_KEY"], how="leftanti")
    .join(source_names, ["CONTENT_ID"], how="left")
    .select(
        "CONTENT_ID",
        "ELEMENT_PATH",
        "ARCHER_ENGAGEMENT_NAME",
        "OSCAL_TITLE",
        "PREVIEW_PAYLOAD",
    )
    .sort("CONTENT_ID", "ELEMENT_PATH")
)

proposed_dim_inserts

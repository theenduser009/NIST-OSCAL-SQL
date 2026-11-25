# Run after Cell 7 in the same notebook session.
# Shows the source records selected for Preview and the Archer field mapped to the title.
source_key = "source-three-compliance-engagements"

engagement_source_rows = (
    SOURCE_INPUTS[source_key]["source_df"]
    .select_expr(
        "SOURCE_RECORD_ID AS CONTENT_ID",
        "AS_VARCHAR(GET(TRY_PARSE_JSON(CURATED_JSON::VARCHAR), 'ENGAGEMENT_NAME')) AS ENGAGEMENT_NAME",
    )
    .sort("CONTENT_ID")
)

engagement_source_rows

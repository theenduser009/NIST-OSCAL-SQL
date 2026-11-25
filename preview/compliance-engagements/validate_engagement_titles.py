# Run in a new Python cell after Cell 7 completes the Compliance Engagements Preview.
from snowflake.snowpark.functions import count, lit, max as max_value

source_key = "source-three-compliance-engagements"
route = (source_key, "SECURITY_ASSESSMENT_PLAN")

archer_names = SOURCE_INPUTS[source_key]["source_df"].select_expr(
    "SOURCE_RECORD_ID AS CONTENT_ID",
    "TRUE AS ARCHER_RECORD_PRESENT",
    "AS_VARCHAR(GET(TRY_PARSE_JSON(CURATED_JSON::VARCHAR), 'ENGAGEMENT_NAME')) AS ARCHER_NAME",
)

plan_titles = (
    MODEL_GRAPHS[route]["nodes"]
    .filter("ELEMENT_PATH = 'assessment-plan.metadata'")
    .select_expr(
        "SOURCE_RECORD_ID AS CONTENT_ID",
        "AS_VARCHAR(GET(TRY_PARSE_JSON(METADATA_JSON::VARCHAR), 'title')) AS OSCAL_TITLE",
    )
)

titles_by_id = plan_titles.group_by("CONTENT_ID").agg(
    count(lit(1)).alias("METADATA_ROWS"),
    max_value("OSCAL_TITLE").alias("OSCAL_TITLE"),
)

title_check = archer_names.join(titles_by_id, ["CONTENT_ID"], how="full").select_expr(
    "CONTENT_ID",
    "ARCHER_NAME",
    "OSCAL_TITLE",
    """CASE
        WHEN ARCHER_RECORD_PRESENT IS NULL THEN 'UNEXPECTED_PREVIEW_RECORD'
        WHEN METADATA_ROWS IS NULL THEN 'MISSING_PREVIEW_METADATA'
        WHEN METADATA_ROWS > 1 THEN 'DUPLICATE_PREVIEW_METADATA'
        WHEN NULLIF(TRIM(ARCHER_NAME), '') IS NULL THEN 'MISSING_ARCHER_NAME'
        WHEN NULLIF(TRIM(OSCAL_TITLE), '') IS NULL THEN 'MISSING_OSCAL_TITLE'
        WHEN ARCHER_NAME = OSCAL_TITLE THEN 'MATCH'
        ELSE 'TITLE_MISMATCH'
    END AS RESULT""",
)

print("Preview status:", PIPELINE_REPORT["status"])
title_check.group_by("RESULT").count().sort("RESULT").show()

print("Rows to review (empty if every title matched):")
title_check.filter("RESULT <> 'MATCH'").sort("CONTENT_ID").show(10)

print("Sample matching titles:")
title_check.filter("RESULT = 'MATCH'").sort("CONTENT_ID").show(5)

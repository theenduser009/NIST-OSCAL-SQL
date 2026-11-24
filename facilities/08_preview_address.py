# Run in the same Snowflake notebook session, after Cell 7 passes in PREVIEW.
nodes = MODEL_GRAPHS[("source-three-facilities", "SSP")]["nodes"]

for node in nodes:
    if node["ELEMENT_TYPE"] == "address":
        print("Archer Content ID:", node["SOURCE_RECORD_ID"])
        print("Mapped address:", node["METADATA_JSON"])
        break
else:
    print("No address was produced in this preview.")

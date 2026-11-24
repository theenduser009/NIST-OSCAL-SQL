# Run in the same Snowflake notebook session after a successful Cell 7 preview.
nodes = MODEL_GRAPHS[("source-three-facilities", "SSP")]["nodes"]
address = (
    nodes.filter(nodes["ELEMENT_TYPE"] == "address")
    .select("SOURCE_RECORD_ID", "METADATA_JSON")
    .first()
)

if address is None:
    print("No address was produced in this preview.")
else:
    print("Archer Content ID:", address["SOURCE_RECORD_ID"])
    print("Mapped address:", address["METADATA_JSON"])

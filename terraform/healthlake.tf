resource "awscc_healthlake_fhir_datastore" "store" {
  # FIXED: Changed var.env to var.environment
  datastore_name         = "healthtech-store-${var.environment}"
  datastore_type_version = "R4"

  preload_data_config = {
    preload_data_type = "SYNTHEA"
  }
}

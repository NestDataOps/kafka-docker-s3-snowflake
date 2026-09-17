output "stage_name" {
  value = "${snowflake_database.db.name}.${snowflake_schema.raw.name}.${snowflake_stage.processed_stage.name}"
}

output "warehouse_name" {
  value = snowflake_warehouse.wh.name
}

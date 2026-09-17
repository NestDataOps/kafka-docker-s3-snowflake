output "stage_name" {
  value = "${snowflake_database.db.name}.${snowflake_schema.raw.name}.${snowflake_stage.processed_stage.name}"
}

output "raw_table_fqn" {
  value = "${snowflake_database.db.name}.${snowflake_schema.raw.name}.${snowflake_table.raw_events.name}"
}

output "warehouse_name" {
  value = snowflake_warehouse.wh.name
}

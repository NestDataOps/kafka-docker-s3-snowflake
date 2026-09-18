output "stage_name" {
  value = "${snowflake_database.db.name}.${snowflake_schema.raw.name}.${snowflake_stage.processed_stage.name}"
}

output "warehouse_name" {
  value = snowflake_warehouse.wh.name
}

output "external_id" {
  value = snowflake_storage_integration_aws.s3_integration.describe_output[0].external_id
}

output "storage_aws_iam_user_arn" {
  value = snowflake_storage_integration_aws.s3_integration.describe_output[0].iam_user_arn
}

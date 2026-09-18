output "processed_bucket_name" {
  value = module.s3.processed_bucket_name
}

#output "lambda_name" {
#  value = module.lambda.lambda_name
#}

output "snowflake_stage_name" {
  value = module.snowflake.stage_name
}

#output "airflow_public_ip" {
#  value = module.ec2_airflow.public_ip
#}

output "snowflake_external_id" {
  value = module.snowflake.external_id
}

output "snowflake_storage_aws_iam_user_arn" {
  value = module.snowflake.storage_aws_iam_user_arn
}

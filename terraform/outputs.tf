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


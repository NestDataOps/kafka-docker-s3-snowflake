locals {
  trust_ready = var.snowflake_storage_aws_iam_user_arn != "" && var.snowflake_external_id != ""
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_exec.arn
}

output "snowflake_storage_role_arn" {
  value = aws_iam_role.snowflake_storage.arn
}

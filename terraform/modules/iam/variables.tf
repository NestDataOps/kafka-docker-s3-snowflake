variable "project_name" {
  type = string
}

variable "raw_bucket_arn" {
  type = string
}

variable "processed_bucket_arn" {
  type = string
}

variable "snowflake_storage_aws_iam_user_arn" {
  description = "Real STORAGE_AWS_IAM_USER_ARN from `DESC STORAGE INTEGRATION`, set after the first apply. Leave empty on first apply -- the role self-trusts your own account until this is set."
  type        = string
  default     = ""
}

variable "snowflake_external_id" {
  description = "Real STORAGE_AWS_EXTERNAL_ID from `DESC STORAGE INTEGRATION`, set after the first apply."
  type        = string
  default     = "placeholder_external_id"
}

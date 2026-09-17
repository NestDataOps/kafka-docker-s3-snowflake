variable "project_name" {
  type = string
}

variable "processed_bucket_name" {
  type = string
}

variable "storage_aws_role_arn" {
  type = string
}

variable "transformer_user" {
  description = "Snowflake username that Airflow/dbt actually log in as -- gets the TRANSFORMER role granted to it"
  type        = string
}

variable "trust_ready" {
  type = bool
}

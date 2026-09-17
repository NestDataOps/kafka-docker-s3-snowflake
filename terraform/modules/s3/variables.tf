variable "project_name" {
  type = string
}

variable "snowpipe_notification_channel" {
  type        = string
  description = "SQS queue ARN from the Snowflake pipe's notification_channel, used to wire up S3 event notifications"
  default     = ""
}

variable "trust_ready" {
  type = bool
}

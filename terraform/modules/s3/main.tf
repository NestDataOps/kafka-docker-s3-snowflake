resource "aws_s3_bucket" "processed" {
  bucket = "${var.project_name}-processed"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "processed" {
  bucket = aws_s3_bucket.processed.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_notification" "commerce_events" {
  count  = var.trust_ready ? 1 : 0
  bucket = aws_s3_bucket.processed.id

  queue {
    queue_arn     = var.snowpipe_notification_channel   # from snowflake module output
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/commerce_events/"
  }
}

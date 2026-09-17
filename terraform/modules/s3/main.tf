resource "aws_s3_bucket" "raw" {
  bucket = "${var.project_name}-raw"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration {
    status = "Enabled"
  }
}

# This is the key setting: it makes every S3 event on this bucket
# (PUT, DELETE, etc.) flow into the account's default EventBridge bus,
# instead of requiring a separate SNS/SQS notification config.
resource "aws_s3_bucket_notification" "raw_eventbridge" {
  bucket      = aws_s3_bucket.raw.id
  eventbridge = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    id     = "expire-old-raw-uploads"
    status = "Enabled"
    expiration {
      days = 30
    }
  }
}

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

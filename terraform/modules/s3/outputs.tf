output "processed_bucket_name" {
  value = aws_s3_bucket.processed.bucket
}

output "processed_bucket_arn" {
  value = aws_s3_bucket.processed.arn
}

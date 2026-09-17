data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Lambda execution role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${var.project_name}-lambda-s3-access"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.raw_bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.processed_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# Snowflake storage integration role
#
# Chicken-and-egg fix: a trust policy's "AWS" principal must reference a
# REAL account -- AWS rejects CreateRole outright with a placeholder like
# 123456789012. So on the first apply, this trusts your OWN account
# (always real) with a placeholder external ID. Apply once, create the
# Snowflake STORAGE INTEGRATION pointing at this role's ARN, run
# `DESC STORAGE INTEGRATION` to get the real STORAGE_AWS_IAM_USER_ARN and
# STORAGE_AWS_EXTERNAL_ID, then set those two variables and apply again --
# this swaps the principal from "yourself" to the actual Snowflake IAM
# user, and the external ID to the real one. See README for the full flow.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "snowflake_storage" {
  name = "${var.project_name}-snowflake-storage"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = coalesce(
          var.snowflake_storage_aws_iam_user_arn,
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        )
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = var.snowflake_external_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "snowflake_storage_access" {
  name = "${var.project_name}-snowflake-storage-access"
  role = aws_iam_role.snowflake_storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${var.processed_bucket_arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.processed_bucket_arn
      }
    ]
  })
}

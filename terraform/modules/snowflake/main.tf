terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

locals {
  # Snowflake unquoted identifiers can't contain hyphens -- upper() alone
  # doesn't strip them, so a hyphenated project_name (e.g. the default
  # "eventdriven-pipeline") silently produces a *different*, hyphenated
  # identifier than what any hand-typed SQL elsewhere (Airflow DAG, this
  # README, ad-hoc worksheet queries) assumes. Sanitize once, here, and
  # use this for every Snowflake object name in this module.
  sql_safe_name = upper(replace(var.project_name, "-", "_"))
}


resource "snowflake_warehouse" "wh" {
  name           = "${local.sql_safe_name}_WH"
  warehouse_size = "XSMALL"
  auto_suspend   = 60
  auto_resume    = true
}

resource "snowflake_database" "db" {
  name = "${local.sql_safe_name}_DB"
}

resource "snowflake_schema" "raw" {
  database = snowflake_database.db.name
  name     = "RAW"
}

# Storage integration: lets Snowflake assume the IAM role created in the
# iam module to read the processed bucket directly (no static AWS keys).
# NOTE: first `terraform apply` will fail to fully connect until you run
# `DESC STORAGE INTEGRATION` in Snowflake and feed the returned
# STORAGE_AWS_IAM_USER_ARN/EXTERNAL_ID back into the iam module variables,
# then `terraform apply` again. This chicken-and-egg step is normal for
# Snowflake storage integrations -- documented in the README.
resource "snowflake_storage_integration" "s3_integration" {
  name             = "${local.sql_safe_name}_S3_INTEGRATION"
  storage_provider = "S3"
  enabled          = true

  storage_aws_role_arn      = var.storage_aws_role_arn
  storage_allowed_locations = ["s3://${var.processed_bucket_name}/"]
}

resource "snowflake_file_format" "parquet" {
  name        = "PARQUET_FORMAT"
  database    = snowflake_database.db.name
  schema      = snowflake_schema.raw.name
  format_type = "PARQUET"
}

resource "snowflake_stage" "processed_stage" {
  name                = "PROCESSED_STAGE"
  database            = snowflake_database.db.name
  schema              = snowflake_schema.raw.name
  url                 = "s3://${var.processed_bucket_name}/"
  storage_integration = snowflake_storage_integration.s3_integration.name
  file_format         = "FORMAT_NAME = ${snowflake_database.db.name}.${snowflake_schema.raw.name}.${snowflake_file_format.parquet.name}"
}

# AWS IAM trust-policy updates (setting the Snowflake external_id/ARN
# condition via the -var flags) are eventually consistent -- Snowflake's
# sts:AssumeRole call can hit stale policy for up to ~30-60s after
# Terraform applies the change, causing an intermittent "not authorized
# to perform sts:AssumeRole" error on the pipe below. This sleep only
# runs once trust_ready is true, and gives the policy time to propagate
# before anything tries to assume the role.
resource "time_sleep" "wait_for_iam_propagation" {
  count           = var.trust_ready ? 1 : 0
  create_duration = "30s"
}

resource "snowflake_stage" "commerce_s3_stage" {
  count               = var.trust_ready ? 1 : 0
  name                = "commerce_s3_stage"
  database    = snowflake_database.db.name
  schema      = snowflake_schema.raw.name
  url                 = "s3://eventdriven-pipeline-processed/raw/commerce_events/"
  storage_integration = snowflake_storage_integration.s3_integration.name
  file_format         = "TYPE = PARQUET"

  depends_on = [
    snowflake_storage_integration.s3_integration, # gate on the 2nd apply's IAM trust update
    time_sleep.wait_for_iam_propagation,
  ]
}

resource "snowflake_table" "raw_commerce_events" {
  count    = var.trust_ready ? 1 : 0
  database    = snowflake_database.db.name
  schema      = snowflake_schema.raw.name
  name     = "RAW_COMMERCE_EVENTS"

  column {
    name = "event_id"
    type = "STRING"
  }
  column {
    name = "event_type"
    type = "STRING"
  }
  column {
    name = "event_timestamp"
    type = "TIMESTAMP_NTZ"
  }
  column {
    name = "user_id"
    type = "INT"
  }
  column {
    name = "product_id"
    type = "INT"
  }
  column {
    name = "order_id"
    type = "STRING"
  }
  column {
    name = "amount"
    type = "DOUBLE"
  }
  column {
    name = "currency"
    type = "STRING"
  }
  column {
    name = "event_date"
    type = "DATE"
  }
  column {
    name = "topic"
    type = "STRING"
  }
  column {
    name = "partition"
    type = "INT"
  }
  column {
    name = "offset"
    type = "BIGINT"
  }
  column {
    name = "kafka_timestamp"
    type = "TIMESTAMP_NTZ"
  }
}


resource "snowflake_pipe" "commerce_events_pipe" {
  count       = var.trust_ready ? 1 : 0
  database    = snowflake_database.db.name
  schema      = snowflake_schema.raw.name
  name        = "commerce_events_pipe"
  auto_ingest = true

  depends_on = [
    snowflake_stage.commerce_s3_stage,
    snowflake_table.raw_commerce_events,
  ]

  copy_statement = <<-SQL
    COPY INTO ${snowflake_database.db.name}.${snowflake_schema.raw.name}.${snowflake_table.raw_commerce_events[count.index].name}
    FROM @${snowflake_database.db.name}.${snowflake_schema.raw.name}."${snowflake_stage.commerce_s3_stage[count.index].name}"
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
  SQL
}


output "notification_channel" {
  # empty string when not yet created, so downstream module doesn't choke
  value = var.trust_ready ? snowflake_pipe.commerce_events_pipe[0].notification_channel : ""
}


# Event-Driven Commerce Pipeline

A streaming data pipeline that generates synthetic e-commerce events, pushes them through Kafka and Spark Structured Streaming, lands them in S3, and auto-ingests them into Snowflake via Snowpipe — fully provisioned with Terraform (including a bootstrapped remote state backend and a two-phase apply to resolve the Snowflake↔AWS IAM chicken-and-egg problem).

## Architecture

```
producer/producer.py  →  Kafka  →  streaming/job.py (Spark)  →  S3 (Parquet)
                                                                    │
                                                    S3 Event Notification (SQS)
                                                                    │
                                                                    ▼
                                                    Snowpipe (auto_ingest) → Snowflake table
```

1. **`producer/producer.py`** generates synthetic commerce events (`product_viewed`, `purchase`, etc.) as JSON and publishes them to a Kafka topic.
2. **Kafka** (via `docker-compose.yml`) buffers the event stream.
3. **`streaming/job.py`** is a Spark Structured Streaming job that reads from Kafka and writes Parquet files to S3.
4. **S3** stores the raw event files and, on object creation, fires an event notification to an SQS queue.
5. **Snowpipe** (`AUTO_INGEST = TRUE`), subscribed to that SQS queue, automatically copies new files into a Snowflake table.

## Repo layout

```
.
├── docker-compose.yml           # Kafka + Spark cluster for local dev
├── producer/
│   └── producer.py              # synthetic event generator → Kafka
├── streaming/
│   └── job.py                   # Spark job: Kafka → S3 (Parquet)
├── terraform-bootstrap/
│   └── main.tf                  # one-time: creates the Terraform remote state S3 bucket
└── terraform/
    ├── main.tf                  # root module, wires iam + s3 + snowflake together
    └── modules/
        ├── iam/main.tf          # IAM role/policy for Snowflake's storage integration
        ├── s3/main.tf           # data bucket + (2nd apply) S3 event notification → SQS
        └── snowflake/main.tf    # warehouse/db/schema/storage integration/stage/table/pipe
```

## Prerequisites

- Docker & Docker Compose
- Python 3.9+
- Terraform >= 1.x
- AWS account + credentials configured (`aws configure` or equivalent)
- Snowflake account + a role with sufficient privileges (`ACCOUNTADMIN` or `SYSADMIN` plus the grants the modules assume)

## Setup

### 1. Bootstrap remote state

Creates the S3 bucket that holds Terraform state for the main config. Only needs to be run once, ever, per environment.

```bash
cd terraform-bootstrap
terraform init
terraform apply
```

### 2. Provision infrastructure (two-phase apply)

The `snowflake_storage_integration` resource generates an AWS IAM user ARN and external ID that Snowflake needs to assume your S3 access role — but that role's trust policy needs those exact values to *exist first*. This is a genuine circular dependency, so provisioning happens in two passes:

**First apply** — creates the storage integration, IAM role/policy, S3 bucket, warehouse/db/schema. The Snowflake stage, table, pipe, and S3 event notification are all gated off (`count = 0`) at this point, since they depend on the IAM trust relationship being correct.

```bash
cd terraform
terraform init
terraform apply
```

**Retrieve the values Snowflake generated:**

```sql
DESC STORAGE INTEGRATION EVENTDRIVEN_PIPELINE_S3_INTEGRATION;
```
Grab `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` from the output.

**Second apply** — passes those values in, which flips the `trust_ready` gate to `true` and creates the stage, table, pipe, and wires the pipe's generated `notification_channel` (an SQS ARN) into the S3 bucket's event notification config.

```bash
terraform apply -auto-approve \
  -var="snowflake_storage_aws_iam_user_arn=arn:aws:iam::<account-id>:user/<generated-user>" \
  -var="snowflake_external_id=<generated-external-id>"
```

> **Note:** AWS IAM trust-policy updates are eventually consistent. If the second apply fails with `sts:AssumeRole ... not authorized`, wait a few seconds and re-run — a `time_sleep` resource is included to absorb most of this lag automatically, but propagation can occasionally take longer.

### 3. Start the streaming infrastructure

```bash
docker-compose up -d
```

### 4. Run the Spark job

```bash
docker exec -it commerce-spark \
  /opt/spark/bin/spark-submit \
  --master spark://spark:7077 \
  --conf spark.jars.ivy=/opt/spark-apps/.ivy2 \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.6,org.apache.hadoop:hadoop-aws:3.3.4,com.amazonaws:aws-java-sdk-bundle:1.12.262 \
  /opt/spark-apps/job.py
```

### 5. Run the producer

```bash
cd producer
python3 -m venv .venv
source .venv/bin/activate
pip install kafka-python
python producer.py
```

### 6. Verify

- Check S3 for new Parquet files landing under the configured prefix.
- In Snowflake:
  ```sql
  SELECT * FROM RAW_COMMERCE_EVENTS ORDER BY event_timestamp DESC LIMIT 10;
  SELECT SYSTEM$PIPE_STATUS('commerce_events_pipe');
  ```

## Sample event schema

```json
{
  "event_id": "09f790d2-88e4-4dc1-9e9b-b3f0c5dfce66",
  "event_type": "product_viewed",
  "event_timestamp": "2026-09-16T07:30:34.082796+00:00",
  "user_id": 402,
  "product_id": 90,
  "order_id": null,
  "amount": 417.38,
  "currency": "AUD"
}
```

## Teardown

```bash
docker-compose down -v
cd terraform && terraform destroy
cd ../terraform-bootstrap && terraform destroy   # only if you want to remove state storage too
```

---


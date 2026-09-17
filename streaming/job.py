import os

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, from_json, lit, struct, to_json, to_timestamp, when
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, DoubleType

AWS_REGION = os.environ.get("AWS_REGION", "ap-southeast-2")
S3_BUCKET = os.environ.get("S3_BUCKET", "eventdriven-pipeline-processed")

spark = (
    SparkSession.builder
    .appName("CommerceEventStream")
    .config("spark.hadoop.fs.s3a.access.key", os.environ["AWS_ACCESS_KEY_ID"])
    .config("spark.hadoop.fs.s3a.secret.key", os.environ["AWS_SECRET_ACCESS_KEY"])
    .config("spark.hadoop.fs.s3a.endpoint", f"s3.{AWS_REGION}.amazonaws.com")
    .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    .getOrCreate()
)
spark.sparkContext.setLogLevel("WARN")

schema = StructType([
    StructField("event_id", StringType(), False),
    StructField("event_type", StringType(), True),
    StructField("event_timestamp", StringType(), True),
    StructField("user_id", IntegerType(), True),
    StructField("product_id", IntegerType(), True),
    StructField("order_id", StringType(), True),
    StructField("amount", DoubleType(), True),
    StructField("currency", StringType(), True),
])

raw_events = (
    spark.readStream.format("kafka")
    .option("kafka.bootstrap.servers", "kafka:29092")
    .option("subscribe", "commerce_events")
    .option("startingOffsets", "earliest")
    .load()
)

parsed_events = (
    raw_events.select(
        col("topic"), col("partition"), col("offset"),
        col("timestamp").alias("kafka_timestamp"),
        col("value").cast("string").alias("raw_payload"),
        from_json(col("value").cast("string"), schema).alias("event")
    )
    .select("topic", "partition", "offset", "kafka_timestamp", "raw_payload", "event.*")
    .withColumn("parsed_event_timestamp", to_timestamp("event_timestamp"))
)

validated_events = (
    parsed_events.withColumn(
        "validation_error",
        when(col("event_id").isNull() | (col("event_id") == ""), lit("missing or invalid event_id"))
        .when(col("event_timestamp").isNull(), lit("missing event_timestamp"))
        .when(col("parsed_event_timestamp").isNull(), lit("invalid event_timestamp"))
        .when(col("event_type").isNull() | (col("event_type") == ""), lit("missing event_type"))
    )
)

def process_batch(batch_df, batch_id):
    invalid = batch_df.filter(col("validation_error").isNotNull()).select(
        to_json(struct(
            col("raw_payload").alias("original_payload"),
            col("validation_error").alias("error_reason"),
            current_timestamp().alias("error_timestamp"),
            col("topic").alias("kafka_topic"),
            col("partition").alias("kafka_partition"),
            col("offset").alias("kafka_offset"),
        )).alias("value")
    )

    if not invalid.isEmpty():
        (invalid.selectExpr("CAST(NULL AS STRING) AS key", "value")
         .write.format("kafka")
         .option("kafka.bootstrap.servers", "kafka:29092")
         .option("topic", "commerce_events_dlq")
         .save())

    valid = (batch_df.filter(col("validation_error").isNull())
             .withColumn("event_timestamp", col("parsed_event_timestamp"))
             .drop("parsed_event_timestamp", "validation_error", "raw_payload")
             .withColumn("event_date", col("event_timestamp").cast("date"))
             .dropDuplicates(["event_id"]))

    if not valid.isEmpty():
        (valid.write.mode("append")
         .partitionBy("event_date")
         .parquet(f"s3a://{S3_BUCKET}/raw/commerce_events/"))
        print(f"=== WROTE VALID EVENTS TO S3 | batch_id={batch_id} ===")
        valid.show(truncate=False)

query = (validated_events.writeStream.foreachBatch(process_batch)
         .option("checkpointLocation", "/tmp/commerce-checkpoint")
         .start())
query.awaitTermination()

import json
import random
import time
import uuid
from datetime import datetime, timezone

from kafka import KafkaProducer


EVENT_TYPES = [
    "product_viewed",
    "cart_created",
    "item_added_to_cart",
    "checkout_started",
    "payment_authorized",
    "order_created",
    "order_shipped",
]


def create_event():
    event_type = random.choice(EVENT_TYPES)

    event = {
        "event_id": str(uuid.uuid4()),
        "event_type": event_type,
        "event_timestamp": datetime.now(timezone.utc).isoformat(),
        "user_id": random.randint(1, 1000),
        "product_id": random.randint(1, 100),
        "order_id": str(uuid.uuid4()) if event_type.startswith("order") else None,
        "amount": round(random.uniform(10, 500), 2),
        "currency": "AUD",
    }

    return event


producer = KafkaProducer(
    bootstrap_servers="localhost:9092",
    value_serializer=lambda value: json.dumps(value).encode("utf-8"),
)


print("Starting event producer...")

while True:
    event = create_event()

    producer.send(
        "commerce_events",
        key=event["event_id"].encode("utf-8"),
        value=event,
    )

    producer.flush()

    print(json.dumps(event))

    time.sleep(1)


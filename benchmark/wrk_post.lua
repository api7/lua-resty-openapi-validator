-- wrk script for POST /users/42 benchmark
wrk.method = "POST"
wrk.headers["Content-Type"] = "application/json"
wrk.headers["X-Request-Id"] = "wrk-benchmark-001"

wrk.body = [[{
  "name": "Alice Johnson",
  "email": "alice@example.com",
  "age": 30,
  "role": "admin",
  "active": true,
  "tags": ["vip", "enterprise"],
  "address": {
    "street": "123 Main St",
    "city": "San Francisco",
    "zip": "94105"
  },
  "metadata": {"department": "Engineering", "level": "senior"},
  "score": 95.5,
  "notes": "Premium customer with extended support plan."
}]]

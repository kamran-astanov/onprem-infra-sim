# Phase 4 — Observability & Monitoring: Interview Questions

---

## Observability Concepts

**Q1: What are the three pillars of observability?**

| Pillar | What it answers | Tool in this project |
|--------|----------------|----------------------|
| **Metrics** | How is the system performing? (numbers over time) | Prometheus |
| **Logs** | What happened and when? (events) | Loki + Promtail |
| **Traces** | Where did this request go? (end-to-end path) | OpenTelemetry Collector |

All three are visualized in Grafana.

---

**Q2: What is the difference between monitoring and observability?**

- **Monitoring** — you know in advance what to watch (dashboards, thresholds, alerts). Tells you *something is wrong*.
- **Observability** — you can ask arbitrary questions about system state using metrics, logs, and traces. Tells you *why it is wrong*.

---

## Prometheus

**Q3: What is Prometheus and how does it collect metrics?**

Prometheus is a time-series metrics database. It uses a **pull model** — it scrapes HTTP endpoints (e.g., `/metrics`) on a configured interval. Services expose their metrics; Prometheus fetches them. This is opposite to push-based systems where services send metrics to a collector.

---

**Q4: What scrape targets are configured in this project?**

From `prometheus.yml`:
```yaml
- prometheus itself    → localhost:9090
- otel_collector       → otel_collector:8888
- jenkins              → jenkins:8080/prometheus
- kafka                → kafka:9092
```

Scrape interval is 15 seconds. Data is retained for 7 days (`--storage.tsdb.retention.time=7d`).

---

**Q5: What is a PromQL query and give an example?**

PromQL is Prometheus's query language for selecting and aggregating time-series data.

Examples:
```promql
# CPU usage rate over 5 minutes
rate(process_cpu_seconds_total[5m])

# JVM heap used
jvm_memory_used_bytes{area="heap"}

# HTTP request rate
rate(http_requests_total[1m])
```

Used in Grafana panels to build dashboards.

---

## Loki & Promtail

**Q6: What is Loki and how is it different from Elasticsearch?**

Loki is a log aggregation system by Grafana Labs. Key difference:

| | Loki | Elasticsearch |
|--|------|---------------|
| Indexing | Only indexes labels (metadata) | Full-text indexes all log content |
| Storage cost | Very low | High |
| Query speed | Fast for label queries | Fast for full-text search |
| Use case | Infrastructure logs | Application search, analytics |

Loki is designed to be cost-efficient for high-volume container logs.

---

**Q7: What is Promtail and what does it do in this project?**

Promtail is Loki's log shipping agent. In this project it:
1. Mounts `/var/lib/docker/containers` read-only to access all container log files
2. Mounts `/var/run/docker.sock` to query Docker metadata
3. Uses Docker service discovery to auto-detect running containers
4. Adds labels (`container_name`, `compose_service`) via relabeling
5. Ships log streams to Loki at `http://loki:3100`

No manual configuration is needed when new containers are added — Promtail discovers them automatically.

---

**Q8: What is log relabeling in Promtail?**

Relabeling transforms raw Docker metadata labels into meaningful Loki stream labels. For example:

```yaml
- source_labels: [__meta_docker_container_name]
  target_label: container_name
```

This extracts the container name from Docker metadata and attaches it as a Loki label, making it easy to filter logs by container in Grafana with `{container_name="order_service"}`.

---

## OpenTelemetry

**Q9: What is OpenTelemetry?**

OpenTelemetry (OTel) is a vendor-neutral open standard and SDK for collecting telemetry data (traces, metrics, logs). It provides:
- A unified API for instrumentation
- A Collector that receives, processes, and exports data to any backend
- SDKs for all major languages

In this project the OTel Collector receives traces via OTLP protocol and exports metrics to Prometheus.

---

**Q10: What ports does the OTel Collector expose and what are they for?**

```
4317 — OTLP gRPC receiver (apps send traces/metrics over gRPC)
4318 — OTLP HTTP receiver (apps send traces/metrics over HTTP)
8888 — Collector's own internal metrics (scraped by Prometheus)
```

Applications instrumented with the OTel SDK send telemetry to `otel_collector:4317` or `otel_collector:4318`.

---

**Q11: What is the difference between a trace and a span?**

- **Trace** — the full end-to-end journey of a single request across all services
- **Span** — a single operation within a trace (e.g., a DB query, an HTTP call, a Kafka publish)

A trace is a tree of spans. Each span has a start time, duration, status, and attributes.

---

## Grafana

**Q12: How are datasources configured in Grafana in this project?**

Via provisioning — `grafana-datasources.yml` is mounted into the container at `/etc/grafana/provisioning/datasources/`. Grafana reads it on startup and automatically configures:
- **Prometheus** as the default datasource for metrics
- **Loki** as the datasource for logs

This means datasources are version-controlled and not lost if the container is recreated.

---

**Q13: What is the difference between Grafana provisioning and manual configuration?**

| | Provisioning (file-based) | Manual (UI) |
|--|--------------------------|-------------|
| Version controlled | Yes | No |
| Survives container restart | Yes (from mounted file) | Only if volume persists |
| Reproducible | Yes | No |
| Use case | Infrastructure as code | Quick exploration |

---

**Q14: How would you create a dashboard in Grafana to monitor the order-service?**

1. Open Grafana → Create Dashboard → Add Panel
2. Select Prometheus datasource
3. Write PromQL: `rate(http_requests_total{job="order_service"}[1m])`
4. Add a second panel for Loki logs: `{container_name="order_service"} |= "ERROR"`
5. Save dashboard — optionally export as JSON and version-control it

---

**Q15: What is Grafana alerting and how would you set up an alert for order-service errors?**

Grafana can evaluate queries on a schedule and fire alerts when thresholds are breached.

Example:
1. Create a panel with query: `sum(rate(http_server_requests_seconds_count{status="500"}[5m]))`
2. Set alert condition: value > 5 for 1 minute
3. Configure notification channel (Slack, email, PagerDuty)
4. When errors exceed 5/min for 1 minute → alert fires

---

**Q16: What is the difference between `rate()` and `irate()` in PromQL?**

- `rate(metric[5m])` — average per-second rate over the last 5 minutes. Smooths out spikes. Best for dashboards and alerts.
- `irate(metric[5m])` — instantaneous rate based on the last two data points. Sensitive to spikes. Best for detecting sudden bursts.

For the order-service request rate `rate()` is preferred — it shows a stable trend rather than reacting to individual request spikes.

---

**Q17: What is a Prometheus counter vs gauge vs histogram?**

| Type | Description | Example |
|------|-------------|---------|
| **Counter** | Only increases (resets on restart) | Total requests, total errors |
| **Gauge** | Can go up and down | Active connections, memory usage, queue size |
| **Histogram** | Samples observations into buckets | Request duration, response size |
| **Summary** | Like histogram but calculates quantiles client-side | p50, p95, p99 latency |

Spring Boot Actuator exposes all four types for the JVM and HTTP metrics.

---

**Q18: What is Prometheus retention and what happens when it runs out?**

Prometheus stores data locally in a time-series database. In this project retention is set to 7 days (`--storage.tsdb.retention.time=7d`). When data exceeds the retention period, older blocks are automatically deleted.

For longer retention, options include:
- Increase disk and set `--storage.tsdb.retention.size`
- Use remote write to Thanos, Cortex, or Grafana Mimir for long-term storage

---

**Q19: What is Grafana Explore and when do you use it?**

Grafana Explore is an ad-hoc query interface — no dashboard needed. You pick a datasource (Prometheus or Loki), write a query, and see results immediately. It is used for:
- Live incident investigation
- Testing PromQL or LogQL queries before adding to a dashboard
- Correlating logs and metrics side-by-side during debugging

---

**Q20: What is LogQL and give an example query for the order-service?**

LogQL is Loki's query language. It filters log streams by labels then optionally applies expressions.

Examples:
```logql
# All logs from order_service
{container_name="order_service"}

# Only ERROR logs
{container_name="order_service"} |= "ERROR"

# Count error rate per minute
sum(rate({container_name="order_service"} |= "ERROR" [1m]))

# Parse JSON logs and filter by field
{container_name="order_service"} | json | status="500"
```

---

**Q21: What is the OTel Collector pipeline and what are its three components?**

The OTel Collector processes telemetry in a pipeline:

1. **Receivers** — accept incoming data (e.g., `otlp` receiver on ports 4317/4318 accepts traces/metrics from apps)
2. **Processors** — transform or batch data (e.g., `batch` processor groups spans before exporting to reduce network calls)
3. **Exporters** — send data to backends (e.g., `prometheus` exporter exposes metrics at `/metrics`, `logging` exporter writes traces to stdout)

In `otel-config.yml` the pipeline is: `otlp receiver → batch processor → prometheus + logging exporters`.

---

**Q22: What is distributed tracing and how would you instrument the order-service for it?**

Distributed tracing tracks a single request as it flows across multiple services, showing exactly where time is spent.

To instrument the order-service:
1. Add OpenTelemetry Java agent dependency or `spring-boot-starter-opentelemetry`
2. Set environment variables:
   ```
   OTEL_EXPORTER_OTLP_ENDPOINT=http://otel_collector:4317
   OTEL_SERVICE_NAME=order-service
   ```
3. The agent auto-instruments Spring MVC, JDBC, and Kafka — no code changes needed
4. Traces appear in Grafana Tempo (or via the logging exporter in this project)

---

**Q23: What is Grafana Tempo and how does it differ from the OTel Collector in this project?**

Grafana Tempo is a distributed tracing backend (stores and queries traces). In this project the OTel Collector exports traces via the `logging` exporter — traces are printed to stdout but not stored in a queryable backend.

To add full tracing:
1. Add Tempo to Phase 4 docker-compose.yml
2. Change the OTel Collector exporter to `otlp` pointing at Tempo
3. Add Tempo as a Grafana datasource
4. Then trace IDs in logs can be clicked to jump to the full trace in Grafana

---

**Q24: What is the `promtail` pipeline stages configuration and what can it do?**

Promtail pipeline stages process log lines before shipping to Loki:
- `docker` — parses Docker JSON log format
- `json` — extracts fields from JSON log lines
- `regex` — extracts fields using regex
- `labels` — promotes extracted fields to Loki labels
- `timestamp` — parses log timestamp
- `output` — sets the log line content

Example: extract the log level from Spring Boot logs and make it a Loki label for fast filtering.

---

**Q25: How would you set up a RED dashboard in Grafana for the order-service?**

RED (Rate, Errors, Duration) is the standard microservice health dashboard:

- **Rate** — requests per second: `rate(http_server_requests_seconds_count{job="order_service"}[1m])`
- **Errors** — error rate: `rate(http_server_requests_seconds_count{job="order_service",status=~"5.."}[1m])`
- **Duration** — p99 latency: `histogram_quantile(0.99, rate(http_server_requests_seconds_bucket{job="order_service"}[5m]))`

These three panels give an immediate health overview of any service.

---

**Q26: What is the difference between push-based and pull-based metrics collection?**

| | Pull (Prometheus) | Push (StatsD, Datadog agent) |
|--|------------------|------------------------------|
| Who initiates | Prometheus scrapes the service | Service sends metrics to collector |
| Service awareness | Prometheus must know service addresses | Service must know collector address |
| Service failure detection | Missing scrape = alert | Silence = assumed OK (riskier) |
| Firewall | Service must be reachable from Prometheus | Collector must be reachable from service |

Prometheus pull model is preferred for containerized environments where service discovery handles address management.

---

**Q27: What is Grafana dashboard provisioning and how would you version-control dashboards?**

Dashboard provisioning loads dashboards from JSON files at startup, similar to datasource provisioning:

1. Export dashboard JSON from Grafana UI → Share → Export
2. Save to `phase4/grafana-dashboards/order-service.json`
3. Mount into container:
   ```yaml
   - ./grafana-dashboards:/etc/grafana/provisioning/dashboards
   ```
4. Add a `dashboards.yml` provider config

Dashboard JSON is now in git — reproducible, reviewable, and not lost on container recreation.

---

**Q28: What is a Prometheus recording rule and when would you use it?**

A recording rule pre-computes expensive PromQL queries and stores the result as a new metric. Used when:
- A query is used in multiple dashboards (compute once, reuse)
- A query is slow due to high cardinality
- You need a derived metric for alerting

Example:
```yaml
rules:
  - record: job:http_requests:rate5m
    expr: rate(http_requests_total[5m])
```

Now dashboards use `job:http_requests:rate5m` instead of recomputing the rate every time.

---

**Q29: What is cardinality in Prometheus and why does high cardinality cause problems?**

Cardinality is the number of unique time series. It is determined by label combinations. High cardinality occurs when labels have many unique values (e.g., `user_id`, `request_id` as labels).

Problems:
- Prometheus stores one time series per label combination — millions of series exhaust RAM
- Queries become slow
- Prometheus can OOM and crash

Rule: never use unbounded values (IDs, IP addresses, UUIDs) as Prometheus labels.

---

**Q30: How do Loki, Prometheus, and OTel work together in an incident response workflow?**

1. **Alert fires** in Grafana — Prometheus detects high error rate on order-service
2. **Switch to logs** — click the alert panel → Explore → switch to Loki, filter `{container_name="order_service"} |= "ERROR"` to see error messages
3. **Find a trace ID** in the log line (if OTel is fully wired)
4. **Jump to trace** — click trace ID → Grafana Tempo shows the full request path: Apache → order-service → PostgreSQL, with timing on each hop
5. **Identify root cause** — the PostgreSQL span shows 4s latency → slow query is the problem

This is the full observability loop: metrics → logs → traces.

---

## Scenario-Based Questions

**S1: Prometheus is showing no data for the `jenkins` scrape job. How do you diagnose it?**

1. Check Prometheus targets: http://localhost:9090/targets → look for `jenkins` job status
2. If "connection refused": verify Jenkins is running and on the `infra` network
3. If "404": Jenkins metrics are exposed at `/prometheus` only with the Prometheus plugin installed — check Manage Jenkins → Plugins
4. Test manually: `curl http://jenkins:8080/prometheus` from inside the Prometheus container
5. Check `prometheus.yml` — ensure `metrics_path: /prometheus` is set for the Jenkins job
6. Restart Prometheus after config changes: `docker restart prometheus`

---

**S2: Grafana shows "No data" for Loki logs even though containers are running. How do you fix it?**

1. Check Promtail is running: `docker ps | grep promtail`
2. Check Promtail logs for errors: `docker logs promtail --tail 30`
3. Verify Promtail can reach Loki: `docker exec promtail wget -q -O- http://loki:3100/ready`
4. Check Loki is healthy: `curl http://localhost:3100/ready`
5. In Grafana Explore → select Loki → run `{job="docker"}` — if no results, check the label names in `promtail-config.yml`
6. Verify `/var/lib/docker/containers` is mounted correctly in the Promtail compose config

---

**S3: You need to add the order-service metrics to Prometheus. What changes do you make?**

1. Add Spring Boot Actuator and Micrometer Prometheus dependencies to `pom.xml`:
   ```xml
   <dependency>
     <groupId>org.springframework.boot</groupId>
     <artifactId>spring-boot-starter-actuator</artifactId>
   </dependency>
   <dependency>
     <groupId>io.micrometer</groupId>
     <artifactId>micrometer-registry-prometheus</artifactId>
   </dependency>
   ```
2. Enable the metrics endpoint in `application.properties`:
   ```
   management.endpoints.web.exposure.include=prometheus,health
   ```
3. Add a scrape job to `phase4/prometheus.yml`:
   ```yaml
   - job_name: order_service
     static_configs:
       - targets: ['order_service:8888']
     metrics_path: /actuator/prometheus
   ```
4. Reload Prometheus config or restart the container

---

**S4: The OTel Collector container keeps restarting. How do you debug it?**

1. Check logs: `docker logs otel_collector --tail 30` — look for config parsing errors
2. Validate `otel-config.yml` syntax — YAML indentation errors are common
3. Check port conflicts — port 8888 is used by both OTel Collector metrics and the order-service: verify no overlap in docker-compose.yml
4. Check if the receiver address is correct — `0.0.0.0:4317` not `localhost:4317` (localhost inside a container is not accessible from other containers)
5. Simplify the config to minimum (just one receiver + one exporter) to isolate the problem

---

**S5: An engineer says "the system was slow between 2pm and 3pm yesterday". You have Prometheus with 7-day retention. How do you investigate?**

1. Open Grafana → set time range to yesterday 2pm–3pm
2. Check the RED dashboard — which metric spiked? Request rate, error rate, or latency?
3. If latency spiked: drill into `histogram_quantile(0.99, ...)` — was it consistent or specific endpoints?
4. Switch to Loki logs for the same time range — filter errors: `{container_name="order_service"} |= "ERROR"`
5. Check infrastructure metrics — was CPU, memory, or DB connection pool exhausted during that window?
6. Correlate with Jenkins build history — was a new deployment made at 2pm that could have caused it?
7. Check Kafka consumer lag at that time — if lag grew, downstream processing was backed up

---

**S6: Grafana dashboards are loading slowly and timing out. Prometheus queries take 30+ seconds. How do you fix it?**

1. Check Prometheus resource usage: `docker stats prometheus` — is it CPU or memory starved?
2. Identify expensive queries: Prometheus UI → Status → Runtime & Build Information → check query stats
3. **Reduce query range** — dashboards using `[1h]` ranges on high-cardinality metrics are expensive; switch to `[5m]`
4. **Create recording rules** for frequently-used heavy queries — pre-compute them every 15s
5. **Add more RAM** to the Prometheus container via `mem_limit` in docker-compose.yml
6. **Increase scrape interval** from 15s to 30s to reduce ingestion load
7. **Enable query caching** — Grafana has a built-in query result cache (Enterprise feature) or use Thanos Query Frontend

---

**S7: You need to set up an on-call alert that only fires between 9am and 6pm on weekdays. How do you configure this in Grafana?**

1. Create the alert rule normally in Grafana Alerting
2. Create a **Mute Timing**: Alerting → Mute Timings → Add mute timing
   - Add time interval: days `saturday, sunday` — all day
   - Add time interval: weekdays `monday:friday`, time range `18:00–09:00`
3. Attach the mute timing to the **Notification Policy** that routes to the on-call channel
4. Alerts still fire and are recorded, but notifications are suppressed outside business hours
5. For critical alerts (e.g., total outage), create a separate policy without the mute timing

---

**S8: Loki is ingesting logs but Grafana shows logs from only some containers, not all. What do you check?**

1. Check which containers Promtail is discovering: `docker logs promtail | grep "discovered target"`
2. Verify the Docker socket is mounted: `docker exec promtail ls /var/run/docker.sock`
3. Check Promtail config — the `__meta_docker_container_name` label relabeling may filter out certain containers
4. Look for a `relabel_configs` rule with `action: keep` that may be whitelisting only specific containers
5. Check if newer containers started after Promtail — Promtail uses Docker service discovery which polls periodically; check `refresh_interval` in `promtail-config.yml`
6. Query Loki for all streams: `{job=~".+"}` — see which container labels actually exist

---

**S9: Prometheus scrape targets show the `order_service` job as "DOWN". How do you restore it?**

1. Prometheus UI → Status → Targets → click the failing target for the error message
2. Common errors:
   - `connection refused` — order_service is not running or wrong port in `prometheus.yml`
   - `context deadline exceeded` — service is too slow to respond; increase `scrape_timeout`
   - `404` — metrics path is wrong; should be `/actuator/prometheus` for Spring Boot
3. Test manually from Prometheus container: `docker exec prometheus wget -qO- http://order_service:8888/actuator/prometheus`
4. Verify order_service is on the `infra` network: `docker network inspect infra | grep order`
5. After fixing, reload Prometheus config without restart: `curl -X POST http://localhost:9090/-/reload`

---

**S10: You want to correlate a specific user's request across all services using distributed tracing. The user reports an error but only gives you the time it occurred. Walk through the investigation.**

1. Open Grafana Explore → Loki datasource
2. Query logs around the reported time: `{job="docker"} |= "ERROR"` — narrow by time range to ±5 min
3. Find the specific error log line — look for a `traceId` field if OTel instrumentation is active
4. Switch to Grafana Tempo datasource → search by `traceId`
5. The trace shows the full request path: Apache → order_service span → PostgreSQL span → Kafka publish span
6. Identify which span has the highest duration or error status
7. If no trace ID in logs: correlate by timestamp — find Prometheus metrics spike at that exact time and narrow down the service

---

**S11: The OTel Collector is dropping traces with "queue is full" errors. How do you fix it?**

The batch processor queue is saturated — more traces are arriving than can be exported.

1. Check OTel Collector logs: `docker logs otel_collector | grep -i "drop\|queue"`
2. Increase queue size in `otel-config.yml`:
   ```yaml
   processors:
     batch:
       send_batch_size: 1000
       timeout: 10s
       send_batch_max_size: 2000
   exporters:
     otlp:
       sending_queue:
         num_consumers: 10
         queue_size: 5000
   ```
3. Reduce trace volume — implement **head-based sampling**: only trace 10% of requests:
   ```yaml
   processors:
     probabilistic_sampler:
       sampling_percentage: 10
   ```
4. Scale the OTel Collector horizontally if volume is genuinely that high

---

**S12: A Prometheus alert fires saying "order_service is down" but the service is clearly responding. What could cause a false positive?**

1. **Scrape timeout too short** — if `scrape_timeout` is 10s but the `/actuator/prometheus` endpoint takes 11s to respond under load, Prometheus marks it as down. Increase `scrape_timeout`.
2. **Network blip** — a single missed scrape triggers the alert. Add `for: 2m` to the alert rule so it must be down for 2 consecutive minutes:
   ```yaml
   - alert: OrderServiceDown
     expr: up{job="order_service"} == 0
     for: 2m
   ```
3. **Metrics endpoint is slow** — the `/actuator/prometheus` endpoint itself is expensive. Disable unnecessary metrics in `application.properties`.
4. **Wrong alert threshold** — check the alert expression against current metric values in Prometheus UI

---

**S13: You need to add custom business metrics to Prometheus — specifically, track the number of orders created per minute by product type. How do you implement this in the order-service?**

1. Add Micrometer dependency to `pom.xml` (already included with Spring Boot Actuator)
2. Inject `MeterRegistry` and create a counter in `OrderController.java`:
   ```java
   @Autowired
   private MeterRegistry meterRegistry;

   @PostMapping
   public Order createOrder(@RequestBody Order order) {
       meterRegistry.counter("orders.created",
           "product", order.getProduct()).increment();
       // existing logic...
   }
   ```
3. Prometheus scrapes the metric automatically via `/actuator/prometheus`
4. Query in Grafana: `rate(orders_created_total[1m])` grouped by `product` label
5. Build a dashboard panel showing orders/min per product type

---

**S14: Grafana datasource for Loki is configured but all log queries return "parse error: unexpected end of input". What is wrong?**

This is a LogQL syntax error, not a connection issue.

Common causes:
1. **Empty query** — the query box is blank or has only a label selector with no closing `}`
2. **Unclosed braces** — `{container_name="order_service"` missing closing `}`
3. **Invalid filter syntax** — `|=` needs a string: `{...} |= ""` fails; must be `|= "ERROR"`
4. **Wrong label name** — check actual label names in Loki: run `{job=~".+"}` to see all available streams and their labels
5. Fix: run a minimal query first: `{job="docker"}` — if this works, the datasource is fine and the issue is query syntax

---

**S15: After adding a new container to Phase 3, it does not appear in Grafana logs despite Promtail being configured with Docker service discovery. How do you force Promtail to pick it up?**

1. Check Promtail's current targets: `GET http://localhost:9080/targets` — is the new container listed?
2. Check `refresh_interval` in `promtail-config.yml` — default is 5s but might be set higher; wait for the next discovery cycle
3. Verify the new container is on a Docker network Promtail can see — Promtail uses the Docker API, not network access, so any running container should be discovered
4. Check if the new container has `logging: driver: json-file` — Promtail reads the JSON log files; containers using `syslog` or `none` logging driver are invisible to it
5. Restart Promtail to force re-discovery: `docker restart promtail` — it will re-scan all running containers
6. Verify in Loki: `{container_name="<new_container>"}` — if no results after restart, check the container name in Docker vs the label in the Promtail config

# Phase 4 — Observability & Monitoring

## Overview

Phase 4 adds visibility into the running system. You can see logs from every container, metrics from every service, and distributed traces across microservice calls — all in one Grafana dashboard.

```
Applications → OpenTelemetry Collector → Prometheus (metrics)
Docker logs  → Promtail → Loki (logs)
                              ↓
                           Grafana (dashboards)
```

---

## Services

### Grafana
**Purpose:** Unified dashboard for logs, metrics, and traces. The single UI you use for all observability.

**Port:** `3000`  
**Image:** `grafana/grafana:10.4.0`  
**Login:** `admin` / `admin` (change on first login)

**Pre-configured datasources (grafana-datasources.yml):**
- **Loki** — for log queries
- **Prometheus** — for metrics queries

**Initial Setup:**
1. Open `http://localhost:3000`
2. Login: `admin` / `admin`
3. Datasources are pre-configured via `grafana-datasources.yml`
4. Create dashboards or import from grafana.com (e.g., Kafka dashboard ID 7589)

**Useful dashboards to create:**
- Kafka metrics (topics, consumer lag, throughput)
- Jenkins build success/failure rate
- Order service request rate and latency
- Log viewer for `order_service` container

---

### Prometheus
**Purpose:** Collects and stores time-series metrics. Scrapes metrics endpoints from services on a schedule.

**Port:** `9090`  
**Image:** `prom/prometheus:v2.51.0`  
**Config:** `prometheus.yml`

**Scrape targets (configured in prometheus.yml):**
| Target | Endpoint | What it collects |
|--------|----------|-----------------|
| Prometheus | `prometheus:9090` | Self-metrics |
| OTel Collector | `otel_collector:8888` | App metrics forwarded from services |
| Jenkins | `jenkins:8080/prometheus` | Build metrics (requires Prometheus plugin) |
| Kafka | `kafka:9092` | Broker metrics |

**Querying metrics:**
- Open `http://localhost:9090`
- Use PromQL: e.g., `up` to see all scraped targets, `kafka_server_BrokerTopicMetrics_MessagesInPerSec` for Kafka throughput

**Integration with Grafana:**
- Grafana datasource points to `http://prometheus:9090`
- All Prometheus metrics are queryable from Grafana dashboards

---

### OpenTelemetry Collector
**Purpose:** Receives telemetry data (traces, metrics) from applications, processes it, and forwards to backends (Prometheus, Loki, etc.).

**Ports:** `4317` (gRPC), `4318` (HTTP), `8888` (metrics)  
**Image:** `otel/opentelemetry-collector-contrib:0.98.0`  
**Config:** `otel-config.yml`

**How it works:**
1. Application instruments itself with OTel SDK (Java agent or Node.js SDK)
2. App sends telemetry to OTel Collector on port `4317` (gRPC) or `4318` (HTTP)
3. Collector processes and forwards to Prometheus and other backends

**Adding OTel to Order Service (Java):**
```bash
# Add Java agent at startup
-javaagent:opentelemetry-javaagent.jar
-Dotel.service.name=order-service
-Dotel.exporter.otlp.endpoint=http://otel_collector:4317
```

**Adding OTel to Frontend (Node.js):**
```bash
npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node
```

---

### Loki
**Purpose:** Log aggregation system. Stores logs from all containers and makes them searchable via LogQL.

**Port:** `3100` (internal)  
**Image:** `grafana/loki:2.9.0`

**Querying logs in Grafana:**
- Go to Explore → select Loki datasource
- Query: `{container="order_service"}` → all order service logs
- Query: `{container="jenkins"} |= "ERROR"` → Jenkins errors only

---

### Promtail
**Purpose:** Log shipper — reads Docker container logs and sends them to Loki.

**Image:** `grafana/promtail:2.9.0`  
**Config:** `promtail-config.yml`

**How it works:**
- Mounts Docker socket (`/var/run/docker.sock`) to discover running containers
- Automatically ships logs from all containers to Loki
- Labels logs with container name, image, and compose project

No manual configuration needed per container — Promtail discovers all containers automatically.

---

## End-to-End Observability Flow

### Tracing an Order Request:
1. User places order in browser → request hits Apache → forwarded to Frontend → forwarded to Order Service
2. Order Service logs the request → Promtail ships log → Loki stores it
3. Order Service emits OTel trace → Collector receives it → forwarded to backend
4. Metrics (request count, latency) → Prometheus scrapes from Collector
5. Grafana shows: logs in Loki explorer, metrics in dashboard, traces in trace viewer

### Checking Kafka Consumer Lag:
1. Prometheus collects Kafka metrics
2. In Grafana: query `kafka_consumergroup_lag` to see if consumers are keeping up
3. High lag = consumers processing slower than producers are publishing

---

## Starting Phase 4

```bash
cd /home/kastanov/infra-sim/phase4
docker compose up -d
```

**Access:**
- Grafana: `http://localhost:3000` — main dashboard UI
- Prometheus: `http://localhost:9090` — raw metrics and target health

**Verify all targets are up in Prometheus:**
Open `http://localhost:9090/targets` — all configured scrape targets should show `UP`.

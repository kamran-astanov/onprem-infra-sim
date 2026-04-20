# Phase 3 — Microservices & Application Stack

## Overview

Phase 3 deploys the actual application: a Java order service backend, a Node.js frontend, a message broker, a database, and a reverse proxy that ties it all together.

```
Browser → Apache (port 80)
             ├── / → Frontend (Node.js :3000)
             └── /api → Order Service (Java :8888)
                           ├── PostgreSQL (persist orders)
                           └── Kafka (publish events)
```

---

## Services

### Apache HTTP Server (Reverse Proxy)
**Purpose:** Single entry point for all traffic. Routes requests to the correct service without exposing internal ports.

**Port:** `80`  
**Image:** `httpd:2.4`  
**Config file:** `phase3/httpd.conf`

**Routing rules:**
- `http://localhost/` → frontend container on port 3000
- `http://localhost/api/` → order service container on port 8888

**Key config:**
```apache
ProxyPass        /api/ http://order_service:8888/
ProxyPassReverse /api/ http://order_service:8888/
ProxyPass        /    http://frontend:3000/
ProxyPassReverse /    http://frontend:3000/
```

**Required modules:** `mod_proxy`, `mod_proxy_http` — enabled in httpd.conf.

---

### Frontend (Node.js / Express)
**Purpose:** Web UI for the Order Management System. Handles user login via Keycloak and communicates with the order service API.

**Port:** `3000` (internal, accessed via Apache on port 80)  
**Image:** `kastanov7/frontend:latest` (built and pushed by Jenkins)  
**Source:** `phase3/frontend/`

**Environment variables:**
| Variable | Value | Purpose |
|----------|-------|---------|
| `KEYCLOAK_URL` | `http://localhost:8180` | Keycloak base URL (browser-facing) |
| `KEYCLOAK_REALM` | `infra-sim` | Realm name |
| `KEYCLOAK_CLIENT` | `order-app` | Client ID |
| `ORDER_SERVICE_URL` | `http://order_service:8888` | Backend API URL |

**Authentication flow:**
1. Page loads → Keycloak JS checks if user is logged in (silent SSO check)
2. If not logged in → shows login screen with "Login with Keycloak" button
3. User logs in → Keycloak issues JWT token
4. All API calls include `Authorization: Bearer <token>`
5. Token refreshed every 20 seconds automatically

**Role-based UI:**
- `admin` role → sees "Ship" button on PENDING orders
- `customer` role → read-only view

**API proxy routes (in index.js):**
- `GET /api/orders` → forwards to order service with Bearer token
- `POST /api/orders` → forwards with Bearer token
- `PUT /api/orders/:id/ship` → forwards with Bearer token

**CI/CD Pipeline (`Jenkinsfile`):**
1. Checkout from GitHub
2. `npm install` + `npm test`
3. SonarQube scan (token from Vault)
4. Docker build + push to Docker Hub (credentials from Vault)
5. Ansible deploys to WSL host via SSH

---

### Order Service (Java / Spring Boot)
**Purpose:** REST API that manages orders. Validates JWT tokens, persists data to PostgreSQL, and publishes events to Kafka.

**Port:** `8888` (internal, accessed via Apache)  
**Image:** `kastanov7/order-service:latest` (built and pushed by Jenkins)  
**Source:** `phase3/order-service/`

**Environment variables:**
| Variable | Value | Purpose |
|----------|-------|---------|
| `SPRING_DATASOURCE_URL` | `jdbc:postgresql://app_db:5432/appdb` | PostgreSQL connection |
| `SPRING_DATASOURCE_USERNAME` | `appuser` | DB username |
| `SPRING_DATASOURCE_PASSWORD` | `apppass123` | DB password |
| `SPRING_KAFKA_BOOTSTRAP_SERVERS` | `kafka:29092` | Kafka broker |
| `KEYCLOAK_JWK_URI` | `http://keycloak:8080/realms/infra-sim/...` | JWT validation keys |

**API Endpoints:**
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/orders` | authenticated | List all orders |
| POST | `/orders` | authenticated | Create a new order |
| PUT | `/orders/:id/ship` | admin role | Ship a PENDING order |

**Security:**
- Uses Spring Security OAuth2 Resource Server
- Validates JWT signature using Keycloak's public JWK keys
- Uses `jwk-set-uri` (not `issuer-uri`) to avoid container vs. browser URL mismatch

**Kafka events:**
- On `POST /orders` → publishes to topic `order.created`
- Payload: order JSON
- Downstream consumers (NotificationService, InventoryService) subscribe to this topic

**Database schema (init-db.sql):**
```sql
CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  customer VARCHAR(255),
  product VARCHAR(255),
  quantity INT,
  status VARCHAR(50) DEFAULT 'PENDING',
  created_at TIMESTAMP DEFAULT NOW()
);
```
Orders are never deleted — status transitions from `PENDING` → `SHIPPED`.

**CI/CD Pipeline (`Jenkinsfile`):**
1. Checkout from GitHub
2. `mvn clean package -DskipTests`
3. `mvn test` + publish JUnit results
4. SonarQube scan (token from Vault)
5. Docker build + push to Docker Hub (credentials from Vault)
6. Ansible deploys to WSL host via SSH

---

### PostgreSQL (app_db)
**Purpose:** Main application database for the order service.

**Port:** `5432`  
**Credentials:** `appuser` / `apppass123` / database `appdb`  
**Initialized by:** `init-db.sql` (creates tables and seed data on first start)

---

### Apache Kafka
**Purpose:** Event streaming. Decouples the order service from downstream consumers — order service publishes events, consumers process them independently.

**Port:** `9092` (external), `29092` (internal between containers)  
**Image:** `confluentinc/cp-kafka:7.6.0`

**Key concepts:**
- **Topic:** A named channel (e.g., `order.created`). Like a table in a database but for events.
- **Producer:** The order service — publishes messages to topics.
- **Consumer:** Any service that reads from a topic (e.g., NotificationService, InventoryService).
- **Broker:** The Kafka server itself — stores messages and serves producers/consumers.
- **Partition:** A topic is split into partitions for parallelism. More partitions = more throughput.
- **Consumer group:** Multiple consumer instances sharing a topic — each message goes to one instance in the group.

**Topic created by order service:** `order.created`  
Auto-creation is enabled (`KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"`).

**Integration with Zookeeper:**
- Kafka 7.6 (pre-KRaft) requires Zookeeper for broker coordination and leader election.
- Zookeeper runs automatically alongside Kafka — no manual management needed.

---

### Kafka UI
**Purpose:** Visual dashboard to inspect topics, browse messages, monitor consumer groups.

**Port:** `8090`  
**URL:** `http://localhost:8090`  
**No login required.**

**What you can verify:**
- Topics list → `order.created` appears after first order is placed
- Click topic → Messages tab → see published order JSON payloads
- Consumer Groups → see `order-service` group offset
- Brokers tab → health status

---

## Ansible Deployment

Both frontend and order-service use Ansible to deploy to the WSL host.

**inventory.ini:**
```ini
[app_servers]
wsl_host ansible_host=172.18.0.1 ansible_user=kastanov ansible_ssh_private_key_file=/var/jenkins_home/.ssh/id_rsa

[app_servers:vars]
compose_dir=/home/kastanov/infra-sim/phase3
```

**playbook.yml** pulls the new image and runs `docker compose up -d` on the WSL host.

**SSH setup (one-time):**
```bash
# Copy Jenkins public key to WSL authorized_keys
docker exec jenkins cat /var/jenkins_home/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
# Add WSL host to Jenkins known_hosts
docker exec -u jenkins jenkins ssh-keyscan -H 172.18.0.1 >> /var/jenkins_home/.ssh/known_hosts
```

---

## Starting Phase 3

```bash
cd /home/kastanov/infra-sim/phase3
docker compose up -d
```

**Startup order matters:** `app_db` must be healthy before `order_service` starts (enforced by `depends_on` with healthcheck).

**Accessing the app:** `http://localhost` → login with Keycloak user (e.g., `alice` / `Test1234!`)

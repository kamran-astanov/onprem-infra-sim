# Phase 3 — Application Services: Interview Questions

---

## Order Service (Spring Boot)

**Q1: What does the order-service do?**

It is a Spring Boot REST API that manages orders. It exposes three endpoints:
- `GET /orders` — list all orders
- `POST /orders` — create a new order, publishes `order.created` Kafka event
- `PUT /orders/{id}/ship` — mark order as shipped, publishes `order.shipped` Kafka event

It persists data to PostgreSQL via JPA and communicates events via Kafka.

---

**Q2: What is Spring Data JPA and what does it replace?**

Spring Data JPA is an abstraction over JPA (Java Persistence API) / Hibernate. It eliminates boilerplate JDBC code — you define a repository interface extending `JpaRepository` and Spring generates the SQL at runtime. No manual `Connection`, `PreparedStatement`, or `ResultSet` handling.

---

**Q3: How does the order-service connect to PostgreSQL?**

Via environment variables injected at container startup:
```
DB_URL=jdbc:postgresql://app_db:5432/appdb
DB_USER=appuser
DB_PASS=apppass123
```
These override the defaults in `application.properties`. The hostname `app_db` resolves via Docker's internal DNS on the `infra` network.

---

**Q4: What is `@CrossOrigin("*")` and what are its security implications?**

It allows any domain to make browser-based HTTP requests to the API (CORS). `"*"` means no restriction — any website can call your API from a browser. In production this should be locked down to specific allowed origins (e.g., `@CrossOrigin("https://myapp.com")`). Used here for dev convenience.

---

**Q5: What is the outbox table in the database and why is it not used?**

The outbox table implements the **Transactional Outbox Pattern** — instead of publishing Kafka events directly (which can fail independently of the DB transaction), you write the event to an outbox table within the same DB transaction, then a separate process reads and publishes it. It guarantees at-least-once delivery. The schema was prepared but the publisher logic was not implemented in this simulation.

---

## Kafka

**Q6: What is Kafka and why is it used here?**

Kafka is a distributed event streaming platform. It decouples services — the order-service publishes events (`order.created`, `order.shipped`) without knowing who consumes them. Future services (inventory, notification) subscribe independently. This is the event-driven architecture pattern.

---

**Q7: What is the role of Zookeeper in this project?**

Zookeeper manages Kafka broker metadata — leader election, topic partition assignments, and broker registration. In newer Kafka versions (KRaft mode) Zookeeper is no longer required, but this project uses Confluent 7.6.0 which still depends on it.

---

**Q8: What do these Kafka environment variables configure?**

```yaml
KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:29092,PLAINTEXT_HOST://localhost:9092
```

- `PLAINTEXT://kafka:29092` — internal listener, used by other containers on the `infra` network
- `PLAINTEXT_HOST://localhost:9092` — external listener, used by tools on the host machine (e.g., a local Kafka CLI)

Two listeners are needed because the hostname `kafka` only resolves inside Docker, not on the host.

---

**Q9: What is `KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"` and its tradeoff?**

It allows Kafka to automatically create topics when a producer first publishes to them. Convenient for development — no manual topic creation needed. In production it is usually disabled to prevent accidental topic creation with wrong partition/replication settings.

---

**Q10: What is Kafka UI and what can you do with it?**

Kafka UI (http://localhost:8090) is a web interface to inspect the Kafka cluster. You can:
- Browse topics and their messages
- See consumer groups and their lag
- Publish test messages manually
- View topic configuration (partitions, replication)

---

## Frontend (Node.js)

**Q11: What does the frontend service do and how does it communicate with the order-service?**

It is an Express.js web app that serves an HTML order management UI. It proxies API calls to `order_service:8888` using Axios. The page auto-refreshes every 5 seconds to show updated order status.

---

**Q12: Why does the frontend not call the order-service directly from the browser?**

Because `order_service` is only reachable on the internal Docker network (`infra`), not from the user's browser. The Node.js frontend acts as a backend-for-frontend (BFF) proxy — the browser calls the Node.js server, which forwards requests to `order_service` on the internal network.

---

## Apache Reverse Proxy

**Q13: What is Apache doing in this project?**

Apache httpd acts as a reverse proxy on port 80. It routes:
- `/api/*` → `order_service:8888`
- `/` → `frontend:3000`

This means users access everything through a single port (80) without knowing the internal service topology.

---

**Q14: Why was `mod_unixd` missing from the original httpd.conf?**

The custom `httpd.conf` only loaded the minimum required modules. Apache requires `mod_unixd` to drop root privileges after binding to port 80. Without it Apache refuses to start with `AH00136: Server MUST relinquish startup privileges`.

---

## Ansible Deployment

**Q15: Why use Ansible for deployment instead of raw docker commands in the Jenkinsfile?**

| Raw docker commands | Ansible |
|---------------------|---------|
| Only works on same machine | Works on any SSH-reachable server |
| Not idempotent | Idempotent by design |
| Hard to scale to multiple servers | Single playbook deploys to N servers |
| No inventory management | Inventory file manages server groups |

In this project `inventory.ini` currently targets the local WSL2 host but can be extended to remote servers by adding entries under `[app_servers]`.

---

**Q16: How does Ansible connect to the target server in this project?**

Via SSH using a private key:
```ini
wsl_host ansible_host=172.18.0.1 ansible_user=kastanov ansible_ssh_private_key_file=/var/jenkins_home/.ssh/id_rsa
```

The Jenkins container has an SSH key at `/var/jenkins_home/.ssh/id_rsa`. The public key must be in `~/.ssh/authorized_keys` on the target host (`kastanov@172.18.0.1`).

---

**Q17: What does `community.docker.docker_compose_v2` do in the playbook?**

It is an Ansible module from the `community.docker` collection that manages Docker Compose projects. With `recreate: always` it pulls the new image and recreates the container, equivalent to `docker compose up -d --no-deps --force-recreate`.

---

**Q18: What is the difference between `docker compose up`, `docker compose restart`, and `docker compose recreate`?**

| Command | What it does |
|---------|-------------|
| `up -d` | Creates and starts containers; skips if already running with same config |
| `restart` | Restarts running containers without recreating them (no config/image changes) |
| `up -d --force-recreate` | Stops, removes, and recreates containers even if nothing changed |
| `up -d --no-deps` | Only affects specified service, ignores dependencies |

In CI/CD `--force-recreate` is used to guarantee the new image is applied.

---

**Q19: What is a Docker healthcheck and how is it used in this project?**

A healthcheck is a command Docker runs inside the container to determine if it is healthy. In this project `app_db` uses:
```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U appuser -d appdb"]
  interval: 10s
  timeout: 5s
  retries: 5
```

`pg_isready` checks if PostgreSQL is accepting connections. The `order_service` and `keycloak` services use `condition: service_healthy` to wait for this before starting.

---

**Q20: What is the difference between `EXPOSE` in a Dockerfile and `ports` in docker-compose.yml?**

- `EXPOSE` — documents which port the container listens on internally. It does not publish the port to the host. It is metadata for developers and tooling.
- `ports: "8888:8888"` — actually maps host port 8888 to container port 8888, making it accessible from outside Docker.

A container without `ports` is only reachable by other containers on the same Docker network.

---

**Q21: What is an init SQL file and how does `app_db` use it?**

```yaml
volumes:
  - ./init-db.sql:/docker-entrypoint-initdb.d/init.sql
```

PostgreSQL's official Docker image automatically runs SQL files placed in `/docker-entrypoint-initdb.d/` when the database is first created. In this project `init-db.sql` creates the `orders` and `outbox` tables and inserts seed data (Alice, Bob). It only runs once — on first container startup with an empty volume.

---

**Q22: What is consumer group lag in Kafka and why does it matter?**

Consumer group lag is the number of messages in a Kafka topic partition that a consumer group has not yet processed. A growing lag means consumers are falling behind producers.

In Kafka UI you can see lag per consumer group. High lag indicates:
- Consumer is slow or crashed
- Topic partitions need scaling
- A downstream dependency (e.g., database) is a bottleneck

---

**Q23: What is a Kafka topic partition and how does it affect throughput?**

A partition is an ordered, immutable log within a topic. Kafka parallelizes consumption by partition — each partition can be consumed by one consumer in a group simultaneously.

More partitions = higher throughput potential. In this project topics are auto-created with default settings (1 partition). For production, `order.created` and `order.shipped` would be created with multiple partitions to allow parallel consumers.

---

**Q24: What is at-least-once delivery in Kafka and what problem does it create?**

Kafka's default delivery guarantee — a message will be delivered at least once but may be delivered more than once if the consumer crashes after processing but before committing the offset.

Problem: the consumer (e.g., inventory service) may process the same `order.created` event twice, decrementing stock twice.

Solution: **idempotent consumers** — each event has a unique ID; the consumer checks if it was already processed before acting.

---

**Q25: What is the role of `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1` in this project?**

The internal `__consumer_offsets` topic (which tracks consumer positions) requires a replication factor. The default is 3, which requires at least 3 Kafka brokers. Since this project runs a single broker, setting it to 1 allows the cluster to start successfully. In production with 3+ brokers this would be set to 3 for fault tolerance.

---

**Q26: What is a reverse proxy and what advantages does Apache provide over direct service exposure?**

A reverse proxy sits in front of backend services and forwards client requests to them. Advantages:
- **Single entry point** — clients only know port 80, not internal ports
- **SSL termination** — Apache handles HTTPS, backends use plain HTTP
- **Load balancing** — distribute traffic across multiple backend instances
- **Security** — backend services are not directly exposed to the internet
- **URL routing** — `/api/*` → order-service, `/` → frontend

---

**Q27: What is idempotency and why is it important for the ship order endpoint?**

An idempotent operation produces the same result no matter how many times it is called. `PUT /orders/{id}/ship` should be idempotent — calling it twice should not ship the order twice or publish two `order.shipped` events.

Implementation: check the current status before acting:
```java
if (order.getStatus().equals("SHIPPED")) return order; // already done
```

This protects against duplicate requests from retries, network timeouts, or at-least-once delivery.

---

**Q28: What is the Backend for Frontend (BFF) pattern and how does the Node.js frontend implement it?**

BFF is a pattern where each client type (web, mobile) has a dedicated backend service tailored to its needs. The Node.js frontend in this project acts as a BFF:
- Receives browser requests
- Translates and forwards them to `order_service` on the internal network
- Returns a response formatted for the browser UI

This prevents exposing the Java API directly to the browser and allows frontend-specific logic (e.g., data shaping, auth handling) to live in the BFF layer.

---

**Q29: How would you add a new microservice (e.g., notification-service) to this stack?**

1. Create a new service directory: `phase3/notification-service/`
2. Add a `Dockerfile`, `Jenkinsfile`, `playbook.yml`, `inventory.ini`
3. Add the service to `phase3/docker-compose.yml`:
   ```yaml
   notification_service:
     image: kastanov7/notification-service:latest
     networks:
       - infra
   ```
4. Configure it as a Kafka consumer on the `order.created` topic (consumer group: `notification-service`)
5. Create a Jenkins pipeline job pointing to the new repo
6. Update Apache `httpd.conf` if the service needs an HTTP endpoint

---

**Q30: What is Docker Compose's `restart: unless-stopped` policy and when would you change it?**

`unless-stopped` means the container automatically restarts after crashes or Docker daemon restarts, unless it was explicitly stopped by the user (`docker stop`). Other policies:

| Policy | Behavior |
|--------|----------|
| `no` | Never restart (default) |
| `always` | Always restart, even after `docker stop` on daemon restart |
| `unless-stopped` | Restart on crash/daemon restart, not after manual stop |
| `on-failure[:n]` | Restart only on non-zero exit, max n times |

`unless-stopped` is the right choice for production services in this stack.

---

**Q31: What is the difference between `CMD` and `ENTRYPOINT` in a Dockerfile?**

- `ENTRYPOINT` — the main executable that always runs. Cannot be overridden without `--entrypoint` flag.
- `CMD` — default arguments passed to `ENTRYPOINT`, or the default command if no `ENTRYPOINT`. Easily overridden at `docker run`.

Common pattern:
```dockerfile
ENTRYPOINT ["java", "-jar"]
CMD ["app.jar"]
```
Allows `docker run myimage custom.jar` to override the JAR name while keeping `java -jar` as the entrypoint.

---

**Q32: How does Ansible ensure idempotency in the deployment playbook?**

Ansible modules are designed to be idempotent — running the same playbook multiple times produces the same end state without side effects. The `docker_compose_v2` module checks the current state of the container and only recreates it if needed. The `docker_image` module only pulls if the image tag doesn't exist locally or `force_source: true` is set. This makes it safe to run the playbook repeatedly.

---

## Scenario-Based Questions

**S1: The order-service starts but immediately exits with "Connection refused" to PostgreSQL. How do you fix it?**

1. Check `app_db` is running and healthy: `docker ps | grep app_db`
2. Verify the `depends_on: condition: service_healthy` is set in docker-compose.yml for order_service
3. Check PostgreSQL logs: `docker logs app_db --tail 30`
4. Verify env vars are correct: `docker inspect order_service | grep -A5 Env`
5. Test connectivity from another container: `docker exec -it order_service ping app_db`
6. If the DB hostname resolves but connection is refused, PostgreSQL may still be initializing — add a retry loop or startup probe in the application

---

**S2: A Kafka consumer is showing 50,000 messages of lag on the `order.created` topic. What do you do?**

1. Check if the consumer service is running: `docker ps | grep notification`
2. Check consumer logs for errors: `docker logs notification_service --tail 100`
3. Check Kafka UI → Consumer Groups → see which partition has the lag
4. If the consumer is healthy but slow: scale horizontally by adding more consumer instances (must not exceed partition count)
5. If the topic has 1 partition: increase partitions to allow parallel consumption
6. If the lag is from a backfill: temporarily increase consumer `max.poll.records` to process more messages per batch

---

**S3: You need to deploy order-service to 3 production servers simultaneously. How do you update the Ansible setup?**

Update `inventory.ini`:
```ini
[app_servers]
prod1 ansible_host=10.0.1.10 ansible_user=deploy ansible_ssh_private_key_file=/var/jenkins_home/.ssh/id_rsa
prod2 ansible_host=10.0.1.11 ansible_user=deploy ansible_ssh_private_key_file=/var/jenkins_home/.ssh/id_rsa
prod3 ansible_host=10.0.1.12 ansible_user=deploy ansible_ssh_private_key_file=/var/jenkins_home/.ssh/id_rsa
```

Ansible runs the playbook on all 3 servers in parallel by default. To do a rolling deployment (one at a time to avoid downtime), add `serial: 1` to the playbook:
```yaml
- name: Deploy order-service
  hosts: app_servers
  serial: 1
```

---

**S4: The Apache reverse proxy returns 502 Bad Gateway for `/api/` requests. What do you investigate?**

502 means Apache reached `order_service` but got no valid response. Steps:
1. Check order_service is running: `docker ps | grep order_service`
2. Check order_service logs: `docker logs order_service --tail 30`
3. Test direct connectivity: `docker exec apache curl -s http://order_service:8888/orders`
4. Check Apache config — verify `ProxyPass /api/ http://order_service:8888/` is correct
5. Check if port 8888 is the correct internal port for the service
6. Verify both `apache` and `order_service` are on the `infra` network: `docker network inspect infra`

---

**S5: After deploying a new version of order-service, existing orders show corrupted data. How do you roll back and prevent this in the future?**

**Immediate rollback:**
```bash
ansible-playbook -i inventory.ini playbook.yml -e image_tag=<last_good_build>
```

**Investigation:**
1. Check if a database migration ran and altered the schema
2. Check the Liquibase/Flyway migration history if used
3. Diff the `Order.java` entity between the bad and good commits

**Prevention:**
1. Add database migration tests to the pipeline
2. Use backward-compatible schema changes (add columns, never remove/rename)
3. Test migrations against a copy of production data in staging before production deploy
4. Keep the previous Docker image tag available for at least 5 builds

---

**S6: The order-service is responding slowly (5s+ per request) under load. How do you diagnose and fix it?**

Diagnosis:
1. Check container resources: `docker stats order_service` — is CPU or memory maxed?
2. Check Grafana/Prometheus — is latency spiking on all endpoints or just one?
3. Check PostgreSQL slow query log: `docker exec app_db psql -U appuser -c "SELECT query, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"`
4. Check Kafka consumer lag — is Kafka blocking request threads?
5. Enable Spring Boot Actuator thread dump: `GET /actuator/threaddump` — look for blocked threads

Fixes:
- Add DB indexes on frequently queried columns (e.g., `status`, `customer`)
- Enable connection pooling (HikariCP is default in Spring Boot) — increase `maximum-pool-size`
- Make Kafka publishing async so it doesn't block the HTTP response thread

---

**S7: A `POST /orders` request succeeds but no Kafka event appears in Kafka UI. How do you debug it?**

1. Check Kafka UI → Topics → `order.created` — is the topic created at all?
2. Check order-service logs for Kafka producer errors: `docker logs order_service | grep -i kafka`
3. Verify Kafka is running: `docker ps | grep kafka`
4. Test Kafka connectivity from order_service container: `docker exec order_service nc -zv kafka 29092`
5. Check the `KAFKA_BOOTSTRAP` environment variable is set to `kafka:29092` not `localhost:9092`
6. Check if `KAFKA_AUTO_CREATE_TOPICS_ENABLE` is true — topic may not have been created yet
7. Look for producer exceptions in the Spring Boot logs — a `SerializationException` would silently swallow the event

---

**S8: The frontend auto-refresh every 5 seconds is causing noticeable load on the order-service. How do you optimize it?**

Short-term:
1. Increase the refresh interval from 5s to 30s in the frontend code
2. Add HTTP caching headers to `GET /orders`: `Cache-Control: max-age=10` — browser caches the response for 10 seconds

Medium-term:
1. Replace polling with **Server-Sent Events (SSE)** — order-service pushes updates to the browser only when an order changes
2. Or use **WebSockets** for real-time updates

Long-term:
1. Add a Redis cache in front of the DB for `GET /orders` — reduces DB hits
2. Implement pagination so the frontend only loads recent orders, not the entire table

---

**S9: Apache returns 504 Gateway Timeout on `/api/` requests during peak load. How do you fix it?**

504 means Apache is waiting too long for a response from `order_service`. Steps:
1. Increase Apache proxy timeout in `httpd.conf`:
   ```apache
   ProxyTimeout 120
   ```
2. Check order_service — is it actually processing slowly? Check logs and resource usage
3. Add `ProxyPass` retry/timeout settings:
   ```apache
   ProxyPass /api/ http://order_service:8888/ timeout=120 retry=1
   ```
4. If order_service is overloaded: scale horizontally — run 2 instances and load balance via Apache:
   ```apache
   <Proxy balancer://order_cluster>
     BalancerMember http://order_service_1:8888
     BalancerMember http://order_service_2:8888
   </Proxy>
   ProxyPass /api/ balancer://order_cluster/
   ```

---

**S10: The `app_db` PostgreSQL container was accidentally deleted along with its volume. Orders data is lost. How could this have been prevented?**

Prevention strategies:
1. **Regular backups** — add a cron job to dump the database:
   ```bash
   docker exec app_db pg_dump -U appuser appdb > backup_$(date +%Y%m%d).sql
   ```
2. **Never use `docker compose down -v`** in production — the `-v` flag deletes volumes; use `docker compose down` only
3. **Named volumes with external backing** — use a volume driver that maps to a persistent path outside Docker
4. **Point-in-time recovery** — enable PostgreSQL WAL archiving to a remote location
5. **Protect volumes explicitly**: in CI/CD scripts, require confirmation before any `docker volume rm` command

Recovery (if backups exist):
```bash
docker compose up -d app_db
docker exec -i app_db psql -U appuser appdb < backup_20260420.sql
```

---

**S11: You need to add a health endpoint to the order-service so Apache can remove it from load balancing when it is unhealthy. How do you implement it?**

Spring Boot Actuator already provides a health endpoint:
1. Expose it in `application.properties`:
   ```properties
   management.endpoints.web.exposure.include=health
   management.endpoint.health.show-details=always
   ```
2. `GET /actuator/health` returns `{"status":"UP"}` when healthy

Configure Apache to check it:
```apache
<Proxy balancer://order_cluster>
  BalancerMember http://order_service:8888 route=1
</Proxy>
ProxyPass /api/ balancer://order_cluster/
```

Add a Docker healthcheck in docker-compose.yml:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8888/actuator/health"]
  interval: 10s
  timeout: 5s
  retries: 3
```

---

**S12: Kafka messages are being consumed out of order. A `order.shipped` event is processed before the corresponding `order.created`. What causes this and how do you fix it?**

Cause: Kafka only guarantees ordering **within a single partition**. If `order.created` and `order.shipped` for the same order land on different partitions, they can be consumed out of order.

Fix:
1. **Use the order ID as the partition key** when producing messages:
   ```java
   kafkaTemplate.send("order.created", order.getId().toString(), event);
   ```
2. Kafka hashes the key to always route the same order ID to the same partition
3. All events for a given order now arrive in order to the same consumer

Additionally: make consumers idempotent so they can handle out-of-order delivery gracefully as a fallback.

---

**S13: The Node.js frontend crashes with "ECONNREFUSED" when trying to proxy to order_service. The order-service is healthy. What is wrong?**

1. Check the `ORDER_SERVICE_URL` environment variable in the frontend container: `docker exec frontend env | grep ORDER`
2. Should be `http://order_service:8888` — not `http://localhost:8888` (localhost inside the container is the frontend itself)
3. Verify both containers are on the same Docker network: `docker network inspect infra`
4. Test connectivity from frontend container: `docker exec frontend curl -s http://order_service:8888/orders`
5. Check if `order_service` container name matches exactly — Docker DNS is case-sensitive
6. If using `docker compose`, ensure both services are in the same compose project or both declare the `infra` network as external

---

**S14: You need to run a database migration (add a new column) without downtime. How do you approach it with the current stack?**

Zero-downtime migration follows the **expand-contract pattern**:

Phase 1 (expand — deploy this first):
1. Add the new column as nullable with no application code using it yet
2. Run migration: `ALTER TABLE orders ADD COLUMN priority VARCHAR(10);`
3. Old and new application versions both work — old ignores the column, new can write to it

Phase 2 (migrate data):
1. Backfill existing rows: `UPDATE orders SET priority = 'normal' WHERE priority IS NULL;`

Phase 3 (contract — later deployment):
1. Add `NOT NULL` constraint after all rows are populated
2. Remove fallback code that handled the missing column

Tooling: use Flyway or Liquibase to version and automate migrations, integrated into the Jenkins pipeline before the deploy stage.

---

**S15: Your Ansible playbook succeeds but the new Docker image is not running — the old container is still serving traffic. How do you diagnose it?**

1. Check what image the running container uses: `docker inspect order_service | grep Image`
2. Verify the new image was actually pulled: `docker images | grep order-service`
3. Check if `recreate: always` is set in the playbook — without it, Ansible may skip recreation if the container is already running
4. Check if the `image_tag` variable was passed correctly to the playbook: add `-v` flag for verbose output
5. Manually force recreate: `docker compose up -d --force-recreate order_service`
6. Check if the docker-compose.yml `image:` field references the correct Docker Hub repo and tag — if it still points to `localhost:8082/...` from the old Artifactory config, it will pull the wrong image

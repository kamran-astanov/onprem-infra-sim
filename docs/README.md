# infra-sim Documentation

Full-stack infrastructure simulation across 4 phases. Each phase builds on the previous one using a shared Docker network (`infra`).

## Phases

| Phase | Focus | Services |
|-------|-------|---------|
| [Phase 1](phase1-cicd.md) | CI/CD & Code Quality | Jenkins, SonarQube, Docker Hub |
| [Phase 2](phase2-security.md) | Security & Identity | HashiCorp Vault, Keycloak |
| [Phase 3](phase3-microservices.md) | Microservices & App Stack | Order Service, Frontend, Kafka, PostgreSQL, Apache |
| [Phase 4](phase4-observability.md) | Observability & Monitoring | Grafana, Prometheus, Loki, Promtail, OpenTelemetry |

## Quick Start

```bash
# 1. Bootstrap network and kernel params (run once)
cd /home/kastanov/infra-sim
./setup.sh

# 2. Start each phase in order
cd phase1 && docker compose up -d && cd ..
cd phase2 && docker compose up -d && cd ..
cd phase3 && docker compose up -d && cd ..
cd phase4 && docker compose up -d && cd ..
```

## Service URLs

| Service | URL | Login |
|---------|-----|-------|
| Jenkins | http://localhost:8080 | admin (set on first run) |
| SonarQube | http://localhost:9000 | admin / admin |
| Docker Hub | https://hub.docker.com | kastanov7 account |
| Vault | http://localhost:8200 | token: root |
| Keycloak | http://localhost:8180 | admin / admin123 |
| Kafka UI | http://localhost:8090 | none |
| Order App | http://localhost | alice / Test1234! |
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | none |

## Architecture

```
                          ┌─────────────────────────────────────┐
                          │           Phase 1 (CI/CD)           │
                          │  Jenkins → SonarQube → JFrog        │
                          └──────────────┬──────────────────────┘
                                         │ builds & pushes images
                          ┌──────────────▼──────────────────────┐
                          │         Phase 2 (Security)          │
                          │    Vault (secrets) + Keycloak (IAM) │
                          └──────────────┬──────────────────────┘
                                         │ secrets + JWT tokens
                          ┌──────────────▼──────────────────────┐
                          │       Phase 3 (Applications)        │
 Browser ──► Apache :80 ──┤  Frontend :3000 ←→ OrderSvc :8888  │
                          │         PostgreSQL + Kafka          │
                          └──────────────┬──────────────────────┘
                                         │ logs + metrics
                          ┌──────────────▼──────────────────────┐
                          │      Phase 4 (Observability)        │
                          │  Grafana ← Prometheus + Loki        │
                          └─────────────────────────────────────┘
```

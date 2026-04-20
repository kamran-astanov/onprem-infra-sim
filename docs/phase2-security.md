# Phase 2 — Security & Identity Management

## Overview

Phase 2 adds two critical security services: a secrets manager and an identity provider. Every service that needs a password, API key, or user login goes through these.

```
Apps/Pipelines → Vault (secrets)
Users → Keycloak (login/SSO) → JWT token → Apps
```

---

## Services

### HashiCorp Vault
**Purpose:** Centralized secrets store. Jenkins pipelines, applications, and services fetch credentials from Vault at runtime — no secrets hardcoded in code or config files.

**Port:** `8200`  
**Image:** `hashicorp/vault:latest`  
**Mode:** Dev mode (in-memory, auto-unsealed, root token = `root`)

> Dev mode is fine for simulation. In production, use production mode with proper unseal keys and persistent storage.

**Initial Setup:**
1. Open `http://localhost:8200`
2. Login with token: `root`
3. The KV v1 secrets engine is enabled at `secret/` by default in dev mode

**Storing Secrets (CLI):**
```bash
# Store all Jenkins secrets at once
docker exec -it vault vault kv put secret/jenkins \
  sonar_token=<your_sonar_token> \
  dockerhub_user=<your_dockerhub_username> \
  dockerhub_pass=<your_dockerhub_token>

# Add or update a single key
docker exec -it vault vault kv patch secret/jenkins dockerhub_pass=<token>

# Read stored secrets
docker exec -it vault vault kv get secret/jenkins
```

**Secrets stored at `secret/jenkins`:**
| Key | Used by | Purpose |
|-----|---------|---------|
| `sonar_token` | Jenkinsfile (`withVault`) | SonarQube scan authentication |
| `dockerhub_user` | Jenkinsfile (`withVault`) | Docker Hub login username |
| `dockerhub_pass` | Jenkinsfile (`withVault`) | Docker Hub access token |

> **GitHub token is not in Vault.** It must be stored directly in Jenkins credentials because `checkout scm` and the GitHub Server connection run before any Jenkinsfile code — Vault cannot be called that early. See [Phase 1 docs](phase1-cicd.md) for setup.

**Integration with Jenkins:**
1. Install HashiCorp Vault plugin in Jenkins
2. Jenkins → Manage Jenkins → System → Vault Plugin:
   - Vault URL: `http://vault:8200`
3. Add credential in Jenkins: Secret Text → value `root` → ID `vault-token`
4. In Jenkinsfile, wrap steps with `withVault()`:
   ```groovy
   withVault(configuration: [vaultUrl: 'http://vault:8200', vaultCredentialId: 'vault-token'],
             vaultSecrets: [[path: 'secret/jenkins', secretValues: [
                 [envVar: 'SONAR_TOKEN', vaultKey: 'sonar_token']
             ]]]) {
       sh "npx sonar-scanner -Dsonar.login=${SONAR_TOKEN} ..."
   }
   ```
   Vault is called at the start of each `withVault()` block. Variables are injected into the shell environment and discarded after the block.

**Integration with Applications:**
- Order service and frontend don't call Vault directly — Jenkins injects secrets as environment variables during deployment via Ansible.

---

### Keycloak
**Purpose:** Identity and access management (IAM). Handles user login, SSO, and issues JWT tokens. Applications delegate authentication entirely to Keycloak instead of managing passwords themselves.

**Port:** `8180`  
**Image:** `quay.io/keycloak/keycloak:24.0`  
**Database:** PostgreSQL (`keycloak_db`)

**Key Concepts:**
- **Realm:** A tenant/namespace. All users, clients, and roles for your app live in one realm.
- **Client:** Represents an application (e.g., the frontend). Each client has its own client ID and secret.
- **Role:** A permission label (e.g., `admin`, `customer`) assigned to users.
- **JWT Token:** A signed token Keycloak issues after login. Applications validate this token to authenticate requests.

**Initial Setup:**
1. Open `http://localhost:8180`
2. Login: `admin` / `admin123`

**Create Realm:**
1. Top-left dropdown → Create Realm
2. Name: `infra-sim` → Create

**Create Client (for frontend):**
1. Clients → Create Client
2. Client ID: `order-app`
3. Client type: OpenID Connect
4. Enable: Standard flow, Direct access grants
5. Valid redirect URIs: `http://localhost/*`
6. Web origins: `http://localhost`
7. Save

**Create Roles:**
1. Realm roles → Create role → `admin`
2. Realm roles → Create role → `customer`

**Create Users:**
1. Users → Add User → username: `alice` → Save
2. Credentials tab → Set Password → `Test1234!` → Temporary: OFF
3. Role Mappings → Assign role → `admin`
4. Repeat for user `bob` with role `customer`

**Disable Email Verification (for dev):**
1. Realm Settings → Login tab
2. Turn off: Email as username, Verify email
3. Authentication → Required Actions → uncheck "Verify Profile"

**Fix "Account not fully set up" error:**
- Users must have firstName, lastName, and email set, OR remove the VERIFY_PROFILE required action via admin API:
```bash
curl -s -X GET "http://localhost:8180/admin/realms/infra-sim/users" \
  -H "Authorization: Bearer <admin_token>" | jq '.[].id'

curl -X PUT "http://localhost:8180/admin/realms/infra-sim/users/<user_id>" \
  -H "Authorization: Bearer <admin_token>" \
  -H "Content-Type: application/json" \
  -d '{"requiredActions": []}'
```

**Integration with Frontend (Keycloak JS):**
```javascript
const keycloak = new Keycloak({
  url: 'http://localhost:8180',
  realm: 'infra-sim',
  clientId: 'order-app'
});
keycloak.init({ onLoad: 'check-sso' });
// All API calls include: Authorization: Bearer <keycloak.token>
```

**Integration with Order Service (JWT Validation):**

`application.properties`:
```properties
spring.security.oauth2.resourceserver.jwt.jwk-set-uri=http://keycloak:8080/realms/infra-sim/protocol/openid-connect/certs
```

> Use `jwk-set-uri` (not `issuer-uri`) to avoid issuer URL mismatch — the browser hits `localhost:8180` but the token issuer is `keycloak:8080` (container-internal). Using `jwk-set-uri` validates only the JWT signature, bypassing the issuer check.

`SecurityConfig.java`:
```java
http.oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt -> {}));
// Roles: GET /orders → authenticated, PUT /orders/*/ship → hasRole("admin")
```

---

## Starting Phase 2

```bash
cd /home/kastanov/infra-sim/phase2
docker compose up -d
```

Keycloak takes ~30–60 seconds to initialize. Vault is available immediately.

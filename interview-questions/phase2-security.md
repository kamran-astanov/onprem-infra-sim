# Phase 2 — Security & Identity Management: Interview Questions

---

## HashiCorp Vault

**Q1: What is HashiCorp Vault and what problem does it solve?**

Vault is a secrets management tool. It centralizes storage, access control, and auditing of sensitive values like passwords, tokens, and API keys. Without it, secrets are hardcoded in code or environment variables, making rotation and access control difficult.

---

**Q2: What is Vault dev mode and why is it not for production?**

Dev mode (`vault server -dev`) starts Vault with:
- Everything stored in-memory (no persistence across restarts)
- TLS disabled
- Root token hardcoded as `root`
- All secrets auto-unsealed

It is only for local development and testing. Production requires a proper storage backend (e.g., Consul, PostgreSQL) and a proper unseal mechanism.

---

**Q3: How does Jenkins fetch secrets from Vault in this project?**

Via the **HashiCorp Vault Plugin** for Jenkins using `withVault()` in the Jenkinsfile:

```groovy
withVault(configuration: [vaultUrl: 'http://vault:8200', vaultCredentialId: 'vault-token'],
          vaultSecrets: [[path: 'secret/jenkins', secretValues: [
              [envVar: 'DH_USER', vaultKey: 'dockerhub_user'],
              [envVar: 'DH_PASS', vaultKey: 'dockerhub_pass']
          ]]]) {
    // DH_USER and DH_PASS are now available as env vars
}
```

The `vault-token` credential in Jenkins holds the root token. Vault returns the secret values which Jenkins injects as environment variables for the duration of the block.

---

**Q4: What secrets are stored in Vault for this project?**

At path `secret/jenkins`:
- `sonar_token` — SonarQube analysis token
- `dockerhub_user` — Docker Hub username
- `dockerhub_pass` — Docker Hub password or access token

---

**Q5: What is the Vault token and how is it stored in Jenkins?**

The Vault token (`root` in dev mode) is stored as a `Secret text` credential in Jenkins with ID `vault-token`. Jenkins presents it to Vault on each request to authenticate and retrieve secrets.

---

**Q6: What is the difference between `VAULT_DEV_ROOT_TOKEN_ID` and `VAULT_DEV_LISTEN_ADDRESS`?**

- `VAULT_DEV_ROOT_TOKEN_ID: root` — sets the root token value in dev mode instead of auto-generating one
- `VAULT_DEV_LISTEN_ADDRESS: 0.0.0.0:8200` — makes Vault listen on all interfaces inside the container, not just localhost, so other containers can reach it

---

**Q7: Why did Vault fail on WSL2 and how was it fixed?**

Vault tries to set `CAP_SETFCAP` at startup to lock memory pages and prevent secrets from being swapped to disk. WSL2's restricted kernel does not allow containers to set this capability, causing Vault to crash in a restart loop.

Fix: added `SKIP_SETCAP: "true"` to the environment, which instructs the Vault entrypoint script to skip the `setcap` call. In dev mode on WSL2 this is acceptable since memory locking is not critical.

---

## Keycloak

**Q8: What is Keycloak and what does it provide?**

Keycloak is an open-source Identity and Access Management (IAM) solution. It provides:
- Single Sign-On (SSO) across multiple applications
- OAuth2 / OpenID Connect (OIDC) token-based authentication
- User federation (LDAP, Active Directory)
- Role-based access control (RBAC)

---

**Q9: What database does Keycloak use in this project and why?**

PostgreSQL (`keycloak_db`). Keycloak requires a relational database to persist realms, users, clients, roles, and sessions. The compose file uses a `healthcheck` on the database and `depends_on: condition: service_healthy` to ensure Keycloak only starts after PostgreSQL is ready.

---

**Q10: What is a Keycloak realm?**

A realm is an isolated namespace in Keycloak. Each realm has its own users, roles, clients, and SSO sessions. In this project a realm named `infra-sim` was created to represent the application's identity domain. The `master` realm is Keycloak's admin realm and should not be used for applications.

---

**Q11: What do these Keycloak environment variables do?**

```yaml
KC_HOSTNAME_STRICT: "false"
KC_HTTP_ENABLED: "true"
```

- `KC_HOSTNAME_STRICT: false` — allows Keycloak to accept requests from any hostname, not just a configured one. Required in local/dev environments without a fixed domain.
- `KC_HTTP_ENABLED: true` — enables plain HTTP. By default Keycloak 24+ enforces HTTPS. Disabled for local dev.

---

**Q12: What is the difference between OAuth2 and OpenID Connect?**

- **OAuth2** — authorization framework. Grants an app access to resources on behalf of a user (e.g., "allow this app to read your GitHub repos"). Returns an access token.
- **OpenID Connect (OIDC)** — identity layer on top of OAuth2. Also returns an ID token (JWT) containing user identity information (name, email, roles).

Keycloak supports both. OIDC is used when you want SSO login with user identity.

---

**Q13: How would you integrate Keycloak with the order-service?**

Add Spring Security + Keycloak adapter to the order-service:
1. Add `spring-boot-starter-security` and `keycloak-spring-boot-starter` dependencies
2. Configure `application.properties` with the Keycloak realm URL and client ID
3. Annotate endpoints with `@PreAuthorize` or configure `SecurityFilterChain`
4. Users must obtain a JWT token from Keycloak before calling the API

---

**Q14: What is the Vault KV secrets engine?**

KV (Key-Value) is the simplest Vault secrets engine. It stores arbitrary key-value pairs at a path. Version 1 (used in this project at `secret/jenkins`) stores the latest value only. Version 2 adds versioning — you can retrieve or roll back to previous secret versions. In production KV v2 is preferred for auditability.

---

**Q15: What is secret rotation and how would you implement it with Vault?**

Secret rotation is periodically changing a secret value (e.g., database password, API key) to limit the damage window if a credential is compromised.

With Vault:
1. Vault's **dynamic secrets** engine can generate short-lived credentials automatically (e.g., a PostgreSQL password valid for 1 hour)
2. The application requests a new credential from Vault on each startup
3. No long-lived passwords exist — when the lease expires Vault revokes the credential

In this project credentials are static (KV store), but switching `app_db` to use Vault's PostgreSQL dynamic secrets engine would enable full rotation.

---

**Q16: What is the difference between authentication and authorization in the context of Keycloak?**

- **Authentication** — verifying identity: "who are you?" → Keycloak issues a JWT after verifying username/password or SSO session
- **Authorization** — verifying permissions: "what can you do?" → the order-service validates the JWT and checks roles/scopes before allowing access to endpoints

Keycloak handles both. The JWT contains both identity claims and role assignments.

---

**Q17: What is a JWT and what does it contain?**

JWT (JSON Web Token) is a compact, self-contained token in three Base64-encoded parts: `header.payload.signature`.

Payload contains claims:
```json
{
  "sub": "user-id-123",
  "preferred_username": "kastanov",
  "email": "kastanov@eunasolutions.com",
  "realm_access": { "roles": ["admin", "user"] },
  "exp": 1713556800
}
```

The signature is verified using Keycloak's public key — the service never needs to call Keycloak to validate a token.

---

**Q18: What is the difference between a Keycloak client and a user?**

- **Client** — an application registered in Keycloak that can request tokens (e.g., `order-service`, `frontend`). Has a client ID and optionally a secret.
- **User** — a human identity with credentials, roles, and attributes stored in Keycloak.

A user authenticates to Keycloak and receives a token scoped to a specific client.

---

**Q19: What is the Vault unsealing process and why is it needed?**

When Vault starts it is in a **sealed** state — all data is encrypted and inaccessible. Unsealing requires presenting a threshold number of **unseal keys** (Shamir's Secret Sharing). For example, 3 of 5 key holders must each provide their key to unseal.

In dev mode (`server -dev`) Vault auto-unseals and stores everything in memory. In production the unseal process is a deliberate security checkpoint — if Vault restarts it must be manually or automatically unsealed before serving secrets.

---

**Q20: How would you audit who accessed a secret in Vault?**

Enable the Vault audit log:
```bash
vault audit enable file file_path=/vault/logs/audit.log
```

Every request (read, write, token creation) is logged with:
- Timestamp
- Token identity
- Secret path accessed
- Operation (read/write/delete)
- Client IP

This provides a full tamper-evident audit trail of secret access.

---

**Q21: What is the principle of least privilege and how does it apply to Vault?**

Least privilege means granting only the minimum permissions needed for a task. In Vault this is enforced via policies:

```hcl
path "secret/jenkins/*" {
  capabilities = ["read"]
}
```

Jenkins only gets `read` on `secret/jenkins/*`. It cannot write secrets, access other paths, or manage Vault itself. In this project the root token bypasses all policies — a production setup would create a dedicated Jenkins policy and token.

---

**Q22: What is Keycloak's `start-dev` command vs `start`?**

- `start-dev` — development mode: HTTP enabled, strict hostname checks off, verbose logging, embedded caches. Not for production.
- `start` — production mode: requires HTTPS, strict hostname, optimized startup (requires a prior `build` step to pre-compile configuration).

This project uses `start-dev` because it runs over HTTP without a domain name.

---

**Q23: What is PKCE and why is it important for frontend apps?**

PKCE (Proof Key for Code Exchange) is an OAuth2 extension for public clients (apps that cannot keep a client secret, like SPAs or mobile apps). Instead of a static client secret, the app generates a random `code_verifier` and sends a hashed `code_challenge` with the auth request. The original verifier is sent when exchanging the code for a token — proving the same client initiated both requests.

For the Node.js frontend, PKCE would be used to authenticate users via Keycloak without embedding a client secret in the browser.

---

**Q24: How does Vault handle the case where a secret is requested but does not exist?**

Vault returns a `404 Not Found` HTTP response with an error body:
```json
{"errors": []}
```

In the Jenkins pipeline with `withVault()`, if a key is missing from the path, the environment variable will be empty and the subsequent shell command will likely fail (e.g., `docker login` with an empty password). Proper handling requires either a default value or explicit error checking before using the variable.

---

**Q25: What is the difference between symmetric and asymmetric encryption in the context of JWT signing?**

| | Symmetric (HS256) | Asymmetric (RS256) |
|--|-------------------|-------------------|
| Algorithm | HMAC-SHA256 | RSA |
| Keys | Same key signs and verifies | Private key signs, public key verifies |
| Key sharing | Both parties need the secret | Only public key needs sharing |
| Keycloak default | No | Yes (RS256) |

Keycloak uses RS256 by default. The order-service only needs Keycloak's public key to verify tokens — it never sees the private key.

---

**Q26: What is RBAC in Keycloak and how would you restrict the `/orders/{id}/ship` endpoint to admin users only?**

RBAC (Role-Based Access Control) assigns permissions via roles. In Keycloak:
1. Create a realm role `order-admin`
2. Assign it to specific users
3. Configure the Keycloak client to include roles in the JWT (`realm_access.roles`)
4. In the order-service, annotate the endpoint:

```java
@PreAuthorize("hasRole('order-admin')")
@PutMapping("/{id}/ship")
public Order shipOrder(@PathVariable Long id) { ... }
```

Users without the `order-admin` role receive a 403 Forbidden response.

---

**Q27: What is the `depends_on: condition: service_healthy` pattern in Docker Compose and why is it used for Keycloak?**

It tells Docker Compose to wait for a service to pass its healthcheck before starting the dependent service. For Keycloak:

```yaml
depends_on:
  keycloak_db:
    condition: service_healthy
```

Without this, Keycloak starts before PostgreSQL is ready, immediately fails to connect to the database, and exits. The healthcheck (`pg_isready`) ensures the DB is accepting connections before Keycloak attempts to connect.

---

## Scenario-Based Questions

**S1: The Jenkins build fails with "permission denied" when trying to read a secret from Vault. How do you diagnose it?**

1. Check the Vault token in Jenkins: Manage Jenkins → Credentials → vault-token — is it the correct token?
2. Test the token manually: `curl -H "X-Vault-Token: root" http://localhost:8200/v1/secret/jenkins`
3. Check if the secret path exists: log into Vault UI → `secret/jenkins`
4. Verify the Vault container is running: `docker ps | grep vault`
5. Check Vault audit log if enabled for the exact permission denied error
6. In production: check the Vault policy attached to the token — it may lack `read` capability on the path

---

**S2: You need to rotate the Docker Hub password. What steps do you take to ensure zero pipeline downtime?**

1. Generate a new Docker Hub access token (do not delete the old one yet)
2. Update the secret in Vault: `vault kv put secret/jenkins dockerhub_pass=<new_token>`
3. Trigger a test Jenkins build to confirm the new secret works
4. Delete the old Docker Hub token
5. No Jenkins restart or credential UI change needed — Vault is the single source of truth

---

**S3: Keycloak is up but users cannot log in. The error is "Invalid client credentials". How do you troubleshoot?**

1. Check the realm name — is the app configured for `infra-sim` realm, not `master`?
2. Check the client ID in the app config matches what's registered in Keycloak
3. Check if the client has the correct protocol (OpenID Connect vs SAML)
4. Check the client secret — if confidential client, it must match in both Keycloak and app config
5. Check `KC_HTTP_ENABLED` and `KC_HOSTNAME_STRICT` settings — misconfiguration can cause redirect URI mismatches
6. Check Keycloak logs: `docker logs keycloak --tail 50`

---

**S4: A security audit finds that the Vault root token is stored in plain text in a Jenkins credential. What is the proper fix?**

1. Create a dedicated Vault policy with minimum permissions:
   ```hcl
   path "secret/jenkins/*" { capabilities = ["read"] }
   ```
2. Create a non-root token bound to that policy:
   ```bash
   vault token create -policy=jenkins-policy -ttl=8760h
   ```
3. Replace the root token in the Jenkins `vault-token` credential with the scoped token
4. Revoke the root token from Jenkins entirely
5. Store the root token in a secure offline location (break-glass procedure only)

---

**S5: Your team is onboarding 5 new microservices. Each needs its own Vault secrets but you don't want to give them all the same token. How do you structure this?**

Use **AppRole authentication** in Vault:
1. Create a policy per service: `secret/service-a/*`, `secret/service-b/*`, etc.
2. Create an AppRole per service with its policy attached
3. Each service authenticates with its `role_id` + `secret_id` to get a short-lived token scoped only to its own secrets
4. Tokens auto-expire and rotate — no long-lived credentials
5. Jenkins can manage `secret_id` injection at deploy time via the Vault plugin

---

**S6: Vault restarts and all secrets become inaccessible. Pipelines start failing. What is the recovery procedure?**

In dev mode Vault data is lost on restart — this is by design. In production:
1. **Unseal Vault** — present the required number of unseal keys (or use auto-unseal with AWS KMS/Azure Key Vault)
2. **Verify health**: `curl http://localhost:8200/v1/sys/health`
3. **Check seal status**: `vault status`
4. For dev mode recovery: re-run `vault kv put secret/jenkins ...` to repopulate secrets
5. Long-term fix: switch from dev mode to a persistent backend (file or PostgreSQL storage) so secrets survive restarts

---

**S7: A Keycloak user reports they are logged out every 5 minutes. How do you fix it?**

This is a session timeout configuration issue:
1. Log into Keycloak admin → select `infra-sim` realm
2. Go to **Realm Settings → Sessions**
3. Increase **SSO Session Idle** (e.g., 30 minutes) — time of inactivity before logout
4. Increase **SSO Session Max** (e.g., 8 hours) — absolute session duration
5. For access tokens: go to **Realm Settings → Tokens** → increase **Access Token Lifespan**
6. Distinguish between token expiry (short, by design) and session expiry (user-facing)

---

**S8: You need to allow only users from a specific IP range to access the Vault UI. How do you implement this?**

Several layers:
1. **Network level** — configure firewall rules (iptables, cloud security group) to allow port 8200 only from the allowed IP range
2. **Apache reverse proxy** — put Apache in front of Vault with `Allow from 10.0.0.0/8` in the VirtualHost config
3. **Vault policies** — Vault itself does not natively filter by IP at the UI level, but token creation policies can include CIDR restrictions:
   ```bash
   vault token create -policy=jenkins -bound-cidr=10.0.0.0/8
   ```
4. This ensures tokens created for that policy only work from the allowed IP range

---

**S9: A JWT token issued by Keycloak is being rejected by the order-service with "Token signature verification failed". What are the causes?**

1. **Clock skew** — order-service and Keycloak clocks differ by more than the token's `nbf`/`exp` tolerance. Sync clocks with NTP.
2. **Wrong public key** — the order-service is using a cached old public key after Keycloak key rotation. Clear the JWKS cache or restart the service.
3. **Wrong realm** — token was issued for `master` realm but service is validating against `infra-sim` realm
4. **Algorithm mismatch** — Keycloak uses RS256 but service is configured for HS256
5. **Token tampered** — the payload was modified after signing (rare but possible in man-in-the-middle scenarios)

---

**S10: You discover that the Vault root token has been in use as a service token for 6 months. The token cannot be revoked (it would break everything). How do you safely migrate away from it?**

1. **Create a scoped policy** with only the permissions services actually need
2. **Create a new periodic token** bound to that policy: `vault token create -policy=app-policy -period=24h`
3. **Update Jenkins credentials** to use the new token (test in a non-production pipeline first)
4. **Update each service** that uses the root token one by one
5. **Validate** all pipelines pass with the new token
6. **Revoke the root token** — this is the only step that is irreversible, so do it last with a backup plan
7. **Store the new root token** (generated from `vault operator init`) offline in a secure location

---

**S11: Keycloak is showing "Too many requests" errors during peak login hours. How do you address this?**

1. **Check resource usage**: `docker stats keycloak` — is it CPU or memory bound?
2. **Increase container resources**: add `mem_limit` and CPU limits in docker-compose.yml
3. **Enable Keycloak caching**: Infinispan cache settings in `standalone.xml` — user sessions should be cached in memory
4. **Session clustering**: for high availability, run multiple Keycloak instances behind a load balancer sharing the same PostgreSQL
5. **Increase DB connection pool**: configure `KC_DB_POOL_MAX_SIZE` environment variable
6. **Enable brute force protection** to rate-limit failed login attempts per user without affecting legitimate logins

---

**S12: A security scan finds that secrets are visible in Jenkins build logs. What do you do to mask them?**

1. **Use `withCredentials`** — Jenkins automatically masks credential values in logs when injected this way
2. **Use `withVault`** — similarly masks Vault-fetched secrets
3. **Never `echo` secret variables** — remove any `sh "echo $SECRET"` debug statements
4. **Enable log masking globally** — Jenkins masks values of credentials defined in the credentials store
5. **Audit existing build logs** — go through recent builds and check if secrets appear; rotate any exposed credentials immediately
6. **Use `set +x`** in shell steps to prevent command echoing: `sh 'set +x; docker login ...'`

---

**S13: You need to implement short-lived database credentials for the order-service using Vault. Walk through the setup.**

1. Enable the Vault database secrets engine:
   ```bash
   vault secrets enable database
   ```
2. Configure the PostgreSQL plugin:
   ```bash
   vault write database/config/appdb \
     plugin_name=postgresql-database-plugin \
     connection_url="postgresql://{{username}}:{{password}}@app_db:5432/appdb" \
     allowed_roles="order-service" \
     username="vault_admin" password="vaultpass"
   ```
3. Create a role with a TTL:
   ```bash
   vault write database/roles/order-service \
     db_name=appdb \
     creation_statements="CREATE ROLE ... WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'" \
     default_ttl="1h" max_ttl="24h"
   ```
4. Order-service requests credentials on startup: `vault read database/creds/order-service`
5. Vault creates a unique PostgreSQL user valid for 1 hour — automatically revoked after expiry

---

**S14: A former employee's Keycloak account must be disabled immediately. What is the fastest way and what are the side effects?**

Fastest way:
1. Keycloak Admin → `infra-sim` realm → Users → find the user → **Disable** the account
2. This prevents new logins immediately

Side effects:
1. **Existing active sessions remain valid** until the token expires — to invalidate immediately: Users → Sessions → Log out all sessions
2. **Revoke all active tokens**: Users → Consents → Revoke all
3. Existing JWTs that are already issued remain valid until their `exp` claim — the order-service will still accept them until expiry
4. To prevent this: implement token introspection (the service calls Keycloak to validate every token) instead of just checking the JWT signature locally

---

**S15: Vault audit logs show thousands of requests per minute from Jenkins. You suspect a misconfigured pipeline is requesting secrets on every build step. How do you find and fix it?**

Investigation:
1. Check audit log: `cat /vault/logs/audit.log | jq '.request.path' | sort | uniq -c | sort -rn` — identify which path is hit most
2. Check Jenkins pipeline — is `withVault` wrapping individual steps instead of the whole stage?

Problem pattern (inefficient):
```groovy
sh "withVault ... { docker build }"  // fetches secret
sh "withVault ... { docker push }"   // fetches secret again
```

Fix — fetch once per stage:
```groovy
withVault(...) {
    sh "docker build ..."
    sh "docker login ..."
    sh "docker push ..."
}
```
3. Cache the token at the pipeline level using `environment {}` block if the same secret is used across multiple stages
4. Set a reasonable token TTL so even if fetched multiple times, Vault doesn't create new tokens each time

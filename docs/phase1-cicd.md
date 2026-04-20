# Phase 1 — CI/CD & Code Quality

## Overview

Phase 1 sets up the core developer toolchain: a CI/CD server and a code quality scanner. Built Docker images are pushed directly to Docker Hub.

```
GitHub → Jenkins → SonarQube (scan) → Docker Hub (push image) → Ansible Deploy
```

---

## Services

### Jenkins
**Purpose:** Orchestrates the entire build pipeline — pulls code from GitHub, runs tests, triggers scans, builds Docker images, pushes to Docker Hub, and deploys via Ansible.

**Port:** `8080`  
**Image:** `jenkins/jenkins:lts`

---

#### 1. Initial Setup

1. Get the unlock password:
   ```bash
   docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
   ```
2. Open `http://localhost:8080` → paste the password
3. Select **Install suggested plugins**
4. Create your admin user → Save and Finish

---

#### 2. Install Required Plugins

Go to **Manage Jenkins → Plugins → Available plugins**, search and install each:

| Plugin | Purpose |
|--------|---------|
| HashiCorp Vault | Fetch secrets from Vault in pipelines |
| SonarQube Scanner | Run SonarQube analysis from Jenkins |
| Docker Pipeline | `docker build`, `docker push` in pipelines |
| Ansible | Run Ansible playbooks from Jenkins |

After installing → **Restart Jenkins** when prompted.

---

#### 3. Manage Jenkins → System

Go to **Manage Jenkins → System**. Configure the following two sections on this single page:

**SonarQube servers:**
1. Scroll to **SonarQube servers** section
2. Check **Environment variables**
3. Click **Add SonarQube**
4. Name: `sonarqube`
5. Server URL: `http://sonarqube:9000`
6. Server authentication token: leave blank (fetched from Vault at runtime)

**Vault Plugin:**
1. Scroll to **Vault Plugin** section
2. Vault URL: `http://vault:8200`
3. Vault Credential: select `vault-token`

Click **Save** at the bottom.

---

#### 4. Manage Jenkins → Tools

Go to **Manage Jenkins → Tools**:

1. Scroll to **SonarQube Scanner installations**
2. Click **Add SonarQube Scanner**
3. Name: `sonarqube-scanner`
4. Check **Install automatically**

Click **Save**.

---

#### 5. Install System Dependencies (inside Jenkins container)

These are installed directly into the Jenkins container, not via the plugin UI.

**Node.js** (required for frontend pipeline):
```bash
docker exec -u root jenkins bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs"
```

**Docker** (required to build and push images):
```bash
docker exec -u root jenkins bash -c "apt-get install -y docker.io"
docker exec -u root jenkins bash -c "usermod -aG docker jenkins"
chmod 666 /var/run/docker.sock
```

**Docker Compose plugin**:
```bash
docker exec -u root jenkins bash -c "mkdir -p /usr/local/lib/docker/cli-plugins && curl -SL https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose"
```

**SSH key** (required for Ansible to SSH into WSL host):
```bash
# Generate key inside Jenkins container
docker exec -u jenkins jenkins ssh-keygen -t rsa -b 4096 -f /var/jenkins_home/.ssh/id_rsa -N ""

# Authorize Jenkins on WSL host
docker exec jenkins cat /var/jenkins_home/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# Trust the WSL host (avoid host key prompt)
docker exec -u jenkins jenkins ssh-keyscan -H 172.18.0.1 >> /var/jenkins_home/.ssh/known_hosts
```

---

#### 4. Configure GitHub Integration

**Step 1 — Generate GitHub Token:**
1. Go to `github.com` → Settings → Developer Settings → Personal Access Tokens → Tokens (classic)
2. Click **Generate new token (classic)**
3. Set a note (e.g., `jenkins`) and expiration
4. Select the following permissions:
   - `repo` → Full control of private repositories (read code, commit status, webhooks)
   - `admin:repo_hook` → Manage webhooks (so Jenkins can auto-create webhooks on repos)
   - `write:packages` → Push Docker images to GitHub Container Registry (ghcr.io)
   - `user:email` → Read user email (required by some Jenkins GitHub plugins)
5. Click **Generate Token** → copy it (shown only once)

> **Why not Vault for this token?** The GitHub token is used outside the Jenkinsfile — for `checkout scm` and the GitHub Server connection, both of which are configured in Jenkins system settings. These run before any Jenkinsfile code executes, so Vault cannot be called at that point. This is the one credential that must live directly in Jenkins.

**Step 2 — Add credential in Jenkins:**
1. Jenkins → **Credentials → Global → Add Credentials**
2. Kind: **Secret text**
3. Secret: paste the token
4. ID: `github-token`
5. Save

**Step 3 — Configure GitHub Server:**
1. Jenkins → **Manage Jenkins → System**
2. Scroll to **GitHub** section → **Add GitHub Server**
3. API URL: `https://api.github.com`
4. Credentials: select `github-token`
5. Click **Test connection** → should show `Credentials verified for user kastanov7`
6. Save

---

#### 5. Configure Vault Integration

**Step 1 — Add Vault token as Jenkins credential:**
1. Jenkins → **Credentials → Global → Add Credentials**
2. Kind: **Secret text**
3. Secret: `root` (Vault dev mode root token)
4. ID: `vault-token`
5. Save

**Step 2 — Configure Vault Plugin:**
1. Jenkins → **Manage Jenkins → System**
2. Scroll to **Vault Plugin** section
3. Vault URL: `http://vault:8200`
4. Vault Credential: select `vault-token`
5. Save

Pipelines now use `withVault()` in Jenkinsfiles to fetch `sonar_token`, `dockerhub_user`, `dockerhub_pass` at runtime. No further UI config needed.

---

#### 6. Configure SonarQube Integration

**Step 1 — Configure SonarQube server in Jenkins:**
1. Jenkins → **Manage Jenkins → System**
2. Scroll to **SonarQube servers** section
3. Check **Environment variables** checkbox
4. Click **Add SonarQube**:
   - Name: `sonarqube`
   - Server URL: `http://sonarqube:9000`
   - Server authentication token: leave blank (token is fetched from Vault in pipeline)
5. Save

**Step 2 — Configure SonarQube Scanner tool:**
1. Jenkins → **Manage Jenkins → Tools**
2. Scroll to **SonarQube Scanner installations**
3. Click **Add SonarQube Scanner**:
   - Name: `sonarqube-scanner`
   - Check **Install automatically**
4. Save

> The scanner is used only for the frontend (Node.js). The order service uses `mvn sonar:sonar` directly via Maven, so no separate tool config is needed for it.

---

#### 7. Create Multibranch Pipelines

Repeat for both `frontend` and `order-service`:

1. Jenkins → **New Item**
2. Name: `frontend` (or `order-service`)
3. Type: **Multibranch Pipeline** → OK
4. Branch Sources → **Add source → GitHub**:
   - Credentials: select `github-token`
   - Repository HTTPS URL: `https://github.com/kastanov7/<repo-name>`
5. Build Configuration:
   - Mode: **by Jenkinsfile**
   - Script Path: `Jenkinsfile`
6. Scan Multibranch Pipeline Triggers → check **Periodically if not otherwise run** → interval: `1 minute`
7. Save → Jenkins will scan the repo and create a pipeline for each branch that has a Jenkinsfile

---

### SonarQube
**Purpose:** Static code analysis — detects bugs, vulnerabilities, and code smells. Pipelines fail if quality gate is not passed.

**Port:** `9000`  
**Image:** `sonarqube:community`  
**Database:** PostgreSQL (`sonar_db`)

**Initial Setup:**
1. Open `http://localhost:9000`
2. Login: `admin` / `admin` → change password when prompted
3. Skip tutorial

**Create Token (for Jenkins pipeline):**
1. Top-right avatar → My Account → Security
2. Generate Token → name it `jenkins` → type: Global Analysis Token
3. Copy the token (shown only once)
4. Store in Vault:
   ```bash
   docker exec -it vault vault kv patch secret/jenkins sonar_token=<token>
   ```

**Project Creation:**
- Projects are auto-created on first scan using `sonar.projectKey` from the pipeline
- No manual project setup needed

**How scanning works per service:**
- Frontend (Node.js): `npx sonar-scanner -Dsonar.projectKey=frontend ...`
- Order Service (Java): `mvn sonar:sonar -Dsonar.projectKey=order-service ...`
- Token is injected from Vault via `withVault()` in each Jenkinsfile

---

## Docker Hub (Image Registry)

Docker Hub (`hub.docker.com`) is used as the container image registry. Jenkins builds images and pushes them; Ansible pulls them on the WSL host during deployment.

**Repositories used:**
- `kastanov7/frontend` — Node.js frontend image
- `kastanov7/order-service` — Java Spring Boot order service image

**Credentials stored in Vault:**
```bash
docker exec -it vault vault kv put secret/jenkins \
  sonar_token=<sonar_token> \
  dockerhub_user=kastanov7 \
  dockerhub_pass=<dockerhub_access_token>
```

> Use a Docker Hub **Access Token** (not your password). Create one at hub.docker.com → Account Settings → Personal Access Tokens. Token must have **Read & Write** scope.

**Jenkinsfile push step:**
```groovy
withVault(..., vaultSecrets: [[path: 'secret/jenkins', secretValues: [
    [envVar: 'DH_USER', vaultKey: 'dockerhub_user'],
    [envVar: 'DH_PASS', vaultKey: 'dockerhub_pass']
]]]) {
    sh """
        docker build -t kastanov7/frontend:${BUILD_NUMBER} -t kastanov7/frontend:latest .
        echo ${DH_PASS} | docker login -u ${DH_USER} --password-stdin
        docker push kastanov7/frontend:${BUILD_NUMBER}
        docker push kastanov7/frontend:latest
    """
}
```

---

## Starting Phase 1

```bash
cd /home/kastanov/infra-sim
docker network create infra   # only needed once (or run setup.sh)
cd phase1
docker compose up -d
```

Wait ~2 minutes for SonarQube to fully initialize before running pipelines.

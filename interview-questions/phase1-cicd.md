# Phase 1 — CI/CD & Code Quality: Interview Questions

---

## Jenkins

**Q1: What is Jenkins and what role does it play in this project?**

Jenkins is an open-source CI/CD automation server. In this project it orchestrates the full pipeline for both services: checkout code from GitHub → build → test → SonarQube scan → build & push Docker image to Docker Hub → deploy via Ansible.

---

**Q2: What is a Jenkinsfile and why is it stored in the repo?**

A Jenkinsfile is a Groovy-based pipeline definition checked into source control alongside the code. Storing it in the repo means the pipeline is versioned, reviewed, and changes to it go through the same git workflow as code changes. If Jenkins data is wiped, pipelines are not lost.

---

**Q3: What is the difference between Declarative and Scripted pipelines?**

| | Declarative | Scripted |
|--|-------------|---------|
| Syntax | Structured (`pipeline {}` block) | Full Groovy (`node {}` block) |
| Readability | Easier, enforced structure | Flexible but harder to maintain |
| Error handling | Built-in `post {}` blocks | Manual try/catch |

This project uses Declarative pipelines.

---

**Q4: How does Jenkins authenticate with GitHub in this project?**

Via a Personal Access Token (PAT) stored as a `Username with password` credential with ID `github-creds`. The Jenkinsfile uses `checkout scm` which references the SCM config on the job, which in turn uses that credential.

---

**Q5: How does Jenkins get secrets like Docker Hub credentials without hardcoding them?**

Two approaches used here:
1. **Jenkins credentials store** — credentials stored in Jenkins and injected via `withCredentials()` block
2. **HashiCorp Vault** — secrets fetched at runtime via `withVault()` using the HashiCorp Vault Plugin, pulling from `secret/jenkins` path

---

**Q6: What triggers a Jenkins build in this project?**

**Poll SCM** — Jenkins checks the GitHub repo on a schedule and triggers a build only if new commits are detected. A webhook-based trigger (`GitHub hook trigger for GITScm polling`) is the event-driven alternative but requires Jenkins to be publicly reachable.

---

**Q7: What does `checkout scm` do in the pipeline?**

It checks out source code from the SCM configuration defined on the Jenkins job. It automatically uses the configured branch and credentials, so the Jenkinsfile does not need to hardcode the repo URL.

---

**Q8: What are the pipeline stages in the order-service pipeline?**

1. **Checkout** — pull code from GitHub
2. **Build** — `mvn clean package`, archive the JAR
3. **Test** — `mvn test`, publish JUnit results
4. **SonarQube Scan** — static analysis, token fetched from Vault
5. **Build & Push Docker Image** — build image, push to Docker Hub with build number and latest tags
6. **Deploy** — run Ansible playbook to pull and restart the container

---

## SonarQube

**Q9: What is SonarQube and what does it scan for?**

SonarQube is a static code analysis tool. It scans for bugs, vulnerabilities, code smells, test coverage gaps, and security hotspots (OWASP-aligned). In this project it scans the Java order-service via `mvn sonar:sonar` and the Node.js frontend via `npx sonar-scanner`.

---

**Q10: What database does SonarQube use and why not the embedded H2?**

PostgreSQL (`sonar_db`). SonarQube needs an external relational database to persist analysis history, rules, and quality profiles across restarts. The embedded H2 database is not supported in production and is for evaluation only.

---

**Q11: What does `SONAR_ES_BOOTSTRAP_CHECKS_DISABLE: "true"` do?**

SonarQube bundles an Elasticsearch instance that requires `vm.max_map_count=524288` on the host. This env var disables the bootstrap check so SonarQube can start in environments where that kernel setting is not available. In this project `setup.sh` sets it via `sysctl`, but the flag provides a fallback.

---

## Docker & Networking

**Q12: What is the `infra` Docker network and why is it shared across all phases?**

`infra` is an external Docker bridge network created by `setup.sh`. All phase compose files declare it as `external: true`. This allows containers in different compose projects to communicate by container name — e.g., the Jenkins container reaches SonarQube at `sonarqube:9000` even though they are in separate compose files.

---

**Q13: What does `docker compose up -d --no-deps order_service` do?**

- `-d` — detached mode
- `--no-deps` — restarts only `order_service`, not its dependencies (kafka, app_db)

Used in the deploy stage for a targeted restart of only the updated service without touching the rest of the stack.

---

**Q14: Why tag Docker images with both `BUILD_NUMBER` and `latest`?**

- `BUILD_NUMBER` — immutable tag, allows rollback to any specific build
- `latest` — always points to the newest build, used by docker-compose for automatic pulls during deploy

---

**Q15: What does `docker-daemon.json` configure in this project?**

It adds `localhost:8082` as an insecure registry, allowing Docker to push/pull from Artifactory over plain HTTP without TLS. Required because Artifactory runs locally without an SSL certificate.

---

**Q16: What is the `post` block in a Jenkinsfile and what conditions can it have?**

The `post` block runs steps after all pipeline stages complete, regardless of outcome. Conditions:
- `always` — runs no matter what
- `success` — runs only if pipeline succeeded
- `failure` — runs only if pipeline failed
- `unstable` — runs if build is marked unstable (e.g., test failures)
- `cleanup` — always runs last, even after other post conditions

In this project `post` is used to print a success or failure message.

---

**Q17: What is a Jenkins agent and what does `agent any` mean?**

A Jenkins agent is the machine that executes pipeline steps. `agent any` tells Jenkins to run the pipeline on any available agent (including the Jenkins master itself). In production you would define specific agents by label (e.g., `agent { label 'docker-node' }`) to control where builds run.

---

**Q18: What is the Jenkins workspace and why does it matter?**

The workspace is a directory on the agent where Jenkins checks out source code and runs build commands. Each job gets its own workspace (e.g., `/var/jenkins_home/workspace/order-service`). Files written during the build (JARs, test reports) persist there between stages within the same build.

---

**Q19: What is `archiveArtifacts` in the pipeline and where are artifacts stored?**

```groovy
archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
```

It copies matching files from the workspace to Jenkins' internal artifact storage (`/var/jenkins_home/jobs/<job>/builds/<n>/archive/`). Artifacts are then downloadable from the Jenkins UI build page. `fingerprint: true` creates an MD5 hash for artifact tracking across jobs.

---

**Q20: What is `junit` in the pipeline and what does it produce?**

```groovy
junit testResults: 'target/surefire-reports/*.xml', allowEmptyResults: true
```

It parses JUnit-format XML test reports and publishes a test trend graph on the Jenkins job page. `allowEmptyResults: true` prevents the build from failing if no test report files are found (e.g., if tests were skipped).

---

**Q21: What is a multibranch pipeline and when would you use it?**

A multibranch pipeline automatically scans a GitHub repo and creates a separate Jenkins job for each branch. Each branch runs its own `Jenkinsfile`. It also supports pull request builds automatically.

Use it when:
- You have multiple feature branches and want CI on each
- You want PR builds before merging to main
- You want branch-specific deploy targets (dev branch → dev env, main → prod)

---

**Q22: How do you pass parameters to a Jenkins pipeline?**

Define parameters in the `parameters` block:
```groovy
pipeline {
    parameters {
        string(name: 'IMAGE_TAG', defaultValue: 'latest', description: 'Docker image tag')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false)
    }
    stages {
        stage('Build') {
            when { expression { !params.SKIP_TESTS } }
        }
    }
}
```
Parameters appear in the Jenkins UI as "Build with Parameters".

---

**Q23: What is a SonarQube Quality Gate and how does it affect the pipeline?**

A Quality Gate is a set of conditions that code must pass to be considered acceptable (e.g., coverage > 80%, no new critical bugs). If the gate fails, the pipeline can be configured to fail the build using the `waitForQualityGate()` step:

```groovy
stage('Quality Gate') {
    steps {
        waitForQualityGate abortPipeline: true
    }
}
```

This prevents deploying code that does not meet quality standards.

---

**Q24: What is Docker layer caching and how does it speed up Jenkins builds?**

Docker builds images in layers. Each `RUN`, `COPY`, `ADD` instruction creates a layer. If a layer's inputs haven't changed, Docker reuses the cached layer instead of rebuilding it. In the order-service multi-stage Dockerfile, copying `pom.xml` and running `mvn dependency:go-offline` before copying source code means the Maven dependency layer is cached and only rebuilt when `pom.xml` changes — not on every code change.

---

**Q25: What is a multi-stage Docker build and why is it used for the order-service?**

A multi-stage build uses multiple `FROM` instructions in a single Dockerfile. The first stage (builder) uses a full JDK + Maven image to compile and package the JAR. The second stage uses a minimal Alpine JRE image and only copies the compiled JAR. Result: a small production image without build tools, Maven cache, or source code — typically 10x smaller than a single-stage build.

---

**Q26: How would you implement a rollback strategy in this Jenkins pipeline?**

Two approaches:
1. **Image tag rollback** — since images are tagged with `BUILD_NUMBER`, redeploy a previous tag:
   ```groovy
   ansible-playbook -i inventory.ini playbook.yml -e image_tag=42
   ```
2. **Pipeline parameter** — add a `ROLLBACK_BUILD` parameter, and in the deploy stage use it instead of `BUILD_NUMBER` when set.

The immutable `BUILD_NUMBER` tag on Docker images is specifically what enables this.

---

**Q27: What is the difference between `docker build` and `docker compose build`?**

| | `docker build` | `docker compose build` |
|--|----------------|----------------------|
| Scope | Single image | All services with `build:` in compose file |
| Context | Explicit path | `build.context` from compose file |
| Tagging | Manual `-t` flag | Uses `image:` field from compose |
| Use case | CI pipelines | Local dev rebuild |

The Jenkinsfile uses `docker build` directly for explicit control over tagging with `BUILD_NUMBER`.

---

**Q28: What happens if a Jenkins pipeline stage fails — do subsequent stages run?**

By default no — Jenkins stops execution at the failing stage and marks the build as failed. To continue despite a failure use `catchError` or mark a stage as non-blocking:
```groovy
stage('Optional Scan') {
    steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
            sh 'run-optional-scan.sh'
        }
    }
}
```

The `post { always {} }` block always runs regardless.

---

**Q29: What is Poll SCM schedule syntax and what does `H/5 * * * *` mean?**

Jenkins uses cron syntax: `minute hour day month weekday`.
- `H/5 * * * *` — every 5 minutes (the `H` is a hash that distributes load across Jenkins jobs so they don't all poll simultaneously)
- `H H * * *` — once a day at a random hour
- `H 2 * * 1-5` — weekdays at 2am

`H` is Jenkins-specific and preferred over `0` to avoid thundering herd on large Jenkins instances.

---

**Q30: What is a shared library in Jenkins and when would you use it?**

A shared library is reusable Groovy code stored in a separate Git repo that multiple Jenkinsfiles can import. Used when:
- Multiple pipelines share the same deploy logic
- You want to standardize notifications, error handling, or Docker steps across teams
- You need to DRY up 10 similar Jenkinsfiles

Example usage in a Jenkinsfile:
```groovy
@Library('my-shared-lib') _
deployWithAnsible(service: 'order-service', tag: BUILD_NUMBER)
```

---

## Scenario-Based Questions

**S1: A developer pushes code and the Jenkins build passes but the deployed container immediately crashes. How do you diagnose it?**

1. Check container logs: `docker logs order_service --tail 50`
2. Look for startup errors — missing env vars, DB connection refused, port conflicts
3. Check if the image was actually updated: `docker inspect order_service | grep Image`
4. Verify env vars are correct in phase3/docker-compose.yml
5. Try running the container manually with `docker run` to isolate from compose
6. Check if the previous build's image works: redeploy with the previous `BUILD_NUMBER` tag

---

**S2: The SonarQube stage fails with "Unable to connect to SonarQube server". What are the possible causes and fixes?**

Possible causes:
1. SonarQube container is not running — check `docker ps | grep sonarqube`
2. SonarQube is still starting up (takes ~2 min) — wait and retry
3. Token is wrong or expired — regenerate in SonarQube UI → My Account → Security
4. Wrong URL — the pipeline uses `http://sonarqube:9000`, requires both containers on the `infra` network
5. Jenkins container is not on the `infra` network — verify with `docker inspect jenkins`

---

**S3: You need to add a staging environment. The same pipeline should deploy to staging on the `develop` branch and to production on `main`. How would you do it?**

Use the `when` directive and branch-specific inventory files:

```groovy
stage('Deploy to Staging') {
    when { branch 'develop' }
    steps {
        sh "ansible-playbook -i inventory-staging.ini playbook.yml -e image_tag=${BUILD_NUMBER}"
    }
}
stage('Deploy to Production') {
    when { branch 'main' }
    steps {
        sh "ansible-playbook -i inventory-prod.ini playbook.yml -e image_tag=${BUILD_NUMBER}"
    }
}
```

Each inventory file points to the appropriate server group.

---

**S4: Docker Hub rate limits are blocking your Jenkins builds. What are your options?**

1. **Authenticate docker pull** — add a `docker login` step before pulling base images using `dockerhub-creds`
2. **Use a pull-through cache** — configure Artifactory or Nexus as a Docker proxy that caches Docker Hub images locally
3. **Pre-pull base images** — build a custom base image (e.g., `kastanov7/java-base`) from the official image and push it to your own registry, removing the Docker Hub dependency from CI builds
4. **Upgrade Docker Hub plan** — paid plans have higher rate limits

---

**S5: Jenkins is running out of disk space. The workspace and old build artifacts are filling up `/var/jenkins_home`. How do you fix it?**

1. **Discard old builds** — on each job configure "Discard old builds": keep last 10 builds, max 7 days
2. **Clean workspace** — add `cleanWs()` in `post { always {} }` to delete workspace after each build
3. **Prune Docker** — add `docker system prune -f` in the pipeline to remove dangling images
4. **Expand the volume** — resize the `jenkins_data` Docker volume if the above is not enough
5. **Move artifacts to Artifactory/S3** — stop archiving JARs in Jenkins and push them to a dedicated artifact store

---

**S6: Two developers push to `main` at the same time and both builds run simultaneously. The second deploy overwrites the first mid-deploy. How do you prevent this?**

1. In Jenkins job configuration → enable **"Do not allow concurrent builds"**
2. Or use the `lock` step from the Lockable Resources plugin:
   ```groovy
   stage('Deploy') {
       steps {
           lock('order-service-deploy') {
               sh 'ansible-playbook ...'
           }
       }
   }
   ```
3. The second build queues behind the first and only deploys after the first completes
4. Long-term: implement a deployment queue or use a dedicated deploy job triggered by the build job

---

**S7: A Jenkins pipeline was working yesterday but today fails at the `docker build` stage with "Cannot connect to Docker daemon". What do you check?**

1. Verify the Docker socket is mounted in Jenkins container: `docker inspect jenkins | grep docker.sock`
2. Check if the Docker daemon is running on the host: `sudo systemctl status docker`
3. Check socket permissions: `ls -la /var/run/docker.sock` — Jenkins user must have access
4. Try manually: `docker exec jenkins docker ps` — if this fails, the socket mount is broken
5. Restart the Jenkins container: `docker restart jenkins` — may re-establish the socket connection
6. On WSL2: restart Docker Desktop if the daemon stopped

---

**S8: The SonarQube quality gate keeps failing due to code coverage below 80%. Developers want to bypass it temporarily. How do you handle this?**

Short-term bypass (with governance):
1. Add a boolean pipeline parameter `SKIP_QUALITY_GATE` defaulting to `false`
2. Wrap the gate step: `if (!params.SKIP_QUALITY_GATE) { waitForQualityGate abortPipeline: true }`
3. Require manager approval before running with `SKIP_QUALITY_GATE=true`

Long-term fix:
1. Add unit tests to raise coverage — identify untested classes in SonarQube UI
2. Lower the gate threshold temporarily to a realistic target (e.g., 60%) and raise it incrementally
3. Never remove the quality gate entirely — it defeats the purpose of having SonarQube

---

**S9: You need to add a manual approval step before production deployment. How do you implement it in Jenkins?**

Use the `input` step:
```groovy
stage('Approve Production Deploy') {
    steps {
        input message: 'Deploy order-service to production?',
              ok: 'Deploy',
              submitter: 'admin,team-lead'
    }
}
stage('Deploy') {
    steps {
        sh 'ansible-playbook -i inventory-prod.ini playbook.yml ...'
    }
}
```
The pipeline pauses and waits for a named approver to click "Deploy" in the Jenkins UI. If no one approves within a timeout, the build can auto-abort.

---

**S10: A developer accidentally pushed credentials to GitHub. Jenkins picked it up and the build log shows the secret in plain text. What do you do?**

Immediate actions:
1. **Rotate the exposed credential immediately** — new Docker Hub token, new SonarQube token
2. **Update the credential in Jenkins** and Vault
3. **Revoke the old credential** at the source (Docker Hub settings, SonarQube)
4. **Remove from git history**: `git filter-branch` or BFG Repo Cleaner to rewrite history, then force push
5. **Enable secret scanning** in GitHub (Settings → Code security → Secret scanning) to detect future leaks automatically
6. Audit whether the credential was used maliciously during the exposure window

---

**S11: Jenkins takes 20 minutes to build the order-service but only 2 minutes of that is actual compilation. How do you speed it up?**

1. **Cache Maven dependencies** — mount a volume for `~/.m2`:
   ```yaml
   volumes:
     - maven_cache:/root/.m2
   ```
2. **Use Docker layer caching** — copy `pom.xml` and run `mvn dependency:go-offline` before copying source code in Dockerfile
3. **Run tests in parallel** — configure Surefire plugin with `<parallel>methods</parallel>`
4. **Skip tests on feature branches** — add `when { branch 'main' }` to the Test stage
5. **Use a faster agent** — allocate more CPU to the Jenkins container

---

**S12: A new team member cannot trigger builds in Jenkins. They see the job but the "Build Now" button is missing. What is wrong?**

Jenkins uses role-based access control. The new member likely has only `Read` permission, not `Build`.

Fix:
1. Install the **Role-Based Authorization Strategy** plugin if not installed
2. Go to Manage Jenkins → Manage and Assign Roles
3. Add the user to a role that includes `Job/Build` permission
4. Or if using Matrix Authorization: Manage Jenkins → Configure Global Security → add user row → check `Job/Build`

---

**S13: The Jenkins build succeeds but the Ansible playbook fails with "Host key verification failed". How do you fix it?**

This happens because the Jenkins container's `known_hosts` file does not have an entry for the target server.

Fix options:
1. **Add the host key**: `ssh-keyscan 172.18.0.1 >> /var/jenkins_home/.ssh/known_hosts`
2. **Disable host key checking** (less secure, acceptable for internal networks):
   ```ini
   # inventory.ini
   [app_servers:vars]
   ansible_ssh_common_args='-o StrictHostKeyChecking=no'
   ```
3. **Add to ansible.cfg**:
   ```ini
   [defaults]
   host_key_checking = False
   ```

---

**S14: You need to notify the team on Slack when a Jenkins build fails. How do you implement it?**

1. Install the **Slack Notification** plugin in Jenkins
2. Configure the Slack workspace and token in Manage Jenkins → System → Slack
3. Add to the pipeline `post` block:
   ```groovy
   post {
       failure {
           slackSend channel: '#deployments',
                     color: 'danger',
                     message: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER} - ${env.BUILD_URL}"
       }
       success {
           slackSend channel: '#deployments',
                     color: 'good',
                     message: "DEPLOYED: order-service:${env.BUILD_NUMBER}"
       }
   }
   ```

---

**S15: A critical hotfix needs to be deployed immediately but the full pipeline takes 20 minutes due to SonarQube and tests. How do you handle it?**

Short-term (hotfix path):
1. Add a pipeline parameter `HOTFIX_MODE` (boolean)
2. Wrap slow stages with `when { expression { !params.HOTFIX_MODE } }`:
   ```groovy
   stage('Test') {
       when { expression { !params.HOTFIX_MODE } }
       steps { sh 'mvn test' }
   }
   stage('SonarQube Scan') {
       when { expression { !params.HOTFIX_MODE } }
       ...
   }
   ```
3. Trigger with `HOTFIX_MODE=true` — only Checkout → Build → Push → Deploy run
4. Follow up with a full pipeline run after the hotfix is live to ensure quality gates pass

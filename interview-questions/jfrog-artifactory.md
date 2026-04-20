# JFrog Artifactory — Interview Questions

---

## Core Concepts

**Q1: What is JFrog Artifactory and what problem does it solve?**

Artifactory is a universal artifact repository manager. It stores and manages build artifacts (JARs, Docker images, npm packages, Helm charts, etc.) in a central location. Without it, artifacts are scattered across build machines, making versioning, sharing, and auditing difficult.

It solves:
- **Reproducibility** — pin exact artifact versions used in any build
- **Proxying** — cache external registries (Maven Central, Docker Hub) to avoid rate limits and improve speed
- **Security** — scan artifacts for vulnerabilities, control who can push/pull
- **Single source of truth** — one place for all artifact types across all teams

---

**Q2: What is the difference between Artifactory OSS, JCR, and Artifactory Pro?**

| Edition | Key Features |
|---------|-------------|
| **OSS** | Open source, limited to Maven/Gradle/Docker, no HA, no replication |
| **JCR (JFrog Container Registry)** | Free, Docker and Helm only, no Maven/npm |
| **Pro** | All package types, HA, replication, advanced security, LDAP |
| **Enterprise** | Multi-site replication, federated repositories, advanced RBAC |

In this project **JCR** (`artifactory-jcr`) was used as a free Docker registry replacement after the OSS `latest` image had startup issues.

---

**Q3: What is a repository in Artifactory and what are the three types?**

A repository is a storage unit for a specific package type. Three types:

| Type | Description | Example |
|------|-------------|---------|
| **Local** | Stores artifacts you push directly | `libs-release-local`, `docker-local` |
| **Remote** | Proxy for an external registry; caches downloaded artifacts | Proxy for Maven Central, Docker Hub |
| **Virtual** | Aggregates local + remote repos behind a single URL | Developers point at one URL, Artifactory resolves from both |

---

**Q4: What is a local repository and why was `docker-local` used in this project?**

A local repository is where you push your own artifacts. `docker-local` was created as a local Docker repository in Artifactory to store Docker images built by Jenkins. The Jenkinsfile pushed images to `localhost:8082/docker-local/order-service:latest`. The `docker-local` name is the repository key — it forms part of the image path.

---

**Q5: What is a remote repository in Artifactory and what advantage does it provide?**

A remote repository proxies an external registry (e.g., Docker Hub, Maven Central) and caches downloaded artifacts locally. Advantages:

- **Speed** — subsequent pulls come from the local cache, not the internet
- **Reliability** — builds succeed even if the upstream registry is down
- **Rate limit bypass** — Docker Hub limits anonymous pulls; authenticated Artifactory proxy uses a single authenticated connection
- **Audit** — all external downloads are logged

---

**Q6: What is a virtual repository?**

A virtual repository is a logical aggregation of local and remote repositories. Developers configure a single URL (the virtual repo URL) and Artifactory resolves artifacts from the configured local and remote repos behind the scenes.

Example: a `libs-virtual` repo could aggregate `libs-release-local` (your builds) + a remote proxy for Maven Central. Developers use one URL and get artifacts from either source transparently.

---

**Q7: What is the Derby embedded database in Artifactory OSS and why is it not production-ready?**

Derby is a Java-based embedded database that runs inside the Artifactory process. In this project it was configured via `JF_SHARED_DATABASE_TYPE: derby`. It requires no external database setup but:
- No concurrent write support at scale
- No external backup tooling
- Stored inside the container volume — harder to manage
- Not supported for production by JFrog

For production, Artifactory requires an external PostgreSQL, MySQL, or MSSQL database.

---

**Q8: How does Docker push/pull work with Artifactory as a registry?**

Artifactory acts as a Docker v2 registry. Steps:

1. **Login**: `docker login localhost:8082 -u admin -p password`
2. **Tag**: `docker tag myapp localhost:8082/docker-local/myapp:1.0`
3. **Push**: `docker push localhost:8082/docker-local/myapp:1.0`
4. **Pull**: `docker pull localhost:8082/docker-local/myapp:1.0`

The URL format is `<artifactory-host>:<port>/<repo-key>/<image-name>:<tag>`.

---

**Q9: What is `insecure-registries` in `docker-daemon.json` and why was it needed for Artifactory?**

By default Docker requires HTTPS for all registries except `localhost`. Artifactory in this project runs on `localhost:8082` over plain HTTP. Adding it to `insecure-registries` in `docker-daemon.json` tells the Docker daemon to allow HTTP pushes/pulls to that address:

```json
{
  "insecure-registries": ["localhost:8082"]
}
```

Without this, `docker push` fails with "server gave HTTP response to HTTPS client".

---

**Q10: What is artifact fingerprinting in Artifactory?**

Fingerprinting assigns a checksum (MD5, SHA1, SHA256) to every stored artifact. It enables:
- **Integrity verification** — detect corrupted or tampered artifacts
- **Cross-repo tracking** — trace where an artifact was used across multiple builds
- **Deduplication** — Artifactory stores only one copy of an artifact regardless of how many repos reference it

In the Jenkinsfile, `archiveArtifacts fingerprint: true` stores the checksum in Jenkins, which can then be cross-referenced with Artifactory.

---

## Advanced Topics

**Q11: What is Artifactory's role in a CI/CD pipeline compared to Docker Hub?**

| | Artifactory | Docker Hub |
|--|-------------|-----------|
| Artifact types | Universal (Maven, npm, Docker, Helm, etc.) | Docker images only |
| Hosting | Self-hosted, air-gapped possible | Cloud-hosted |
| Access control | Fine-grained per repo/path | Basic public/private |
| Proxying | Can proxy Docker Hub and others | Cannot proxy |
| Rate limiting | No limits (self-hosted) | Yes (free tier) |
| Vulnerability scanning | JFrog Xray integration | Basic |
| Cost | License required for Pro | Free for public |

For enterprise CI/CD, Artifactory is preferred. For open-source/personal projects, Docker Hub is simpler.

---

**Q12: What is JFrog Xray and how does it integrate with Artifactory?**

JFrog Xray is a security scanning and compliance tool that integrates with Artifactory. It:
- Scans Docker images, JARs, and npm packages for known CVEs
- Checks license compliance (e.g., GPL vs commercial use)
- Blocks downloads of artifacts that fail security policies
- Generates SBOMs (Software Bill of Materials)

In a Jenkins pipeline, a Xray scan stage can be added after the push stage — if critical vulnerabilities are found the pipeline fails before deployment.

---

**Q13: What is Artifactory replication and when would you use it?**

Replication copies artifacts from one Artifactory instance to another. Use cases:
- **Geo-distribution** — replicate to regional instances so teams in Europe and Asia pull locally
- **Disaster recovery** — maintain a warm standby replica
- **Promotion** — push release artifacts from a dev instance to a production instance

Push replication: source pushes artifacts to target.
Pull replication: target pulls artifacts from source on schedule.

---

**Q14: What is artifact promotion in Artifactory?**

Promotion moves an artifact from one repository to another as it progresses through the delivery pipeline:

```
libs-snapshot-local → libs-staging-local → libs-release-local
```

For Docker images:
```
docker-dev → docker-staging → docker-prod
```

The artifact is promoted (copied or moved) only after passing tests at each stage. This provides a clear audit trail of which artifacts reached production and when.

---

**Q15: How does Artifactory handle Maven dependency resolution?**

1. Maven is configured to use Artifactory's virtual repo URL instead of Maven Central directly (in `settings.xml` or `pom.xml`)
2. On `mvn build`, Maven requests the dependency from Artifactory
3. Artifactory checks its local cache — if present, returns it immediately
4. If not cached, Artifactory fetches from the configured remote proxy (Maven Central), caches it, and returns it
5. On subsequent builds, the cached version is returned without hitting the internet

---

**Q16: What is a snapshot vs release repository in Artifactory?**

| | Snapshot | Release |
|--|----------|---------|
| Version pattern | `1.0.0-SNAPSHOT` | `1.0.0` |
| Overwritable | Yes — same version can be re-pushed | No — immutable once pushed |
| Purpose | Development builds, work in progress | Stable, versioned artifacts for production |
| Retention | Short-lived, cleaned regularly | Long-lived, permanent |

In this project `libs-release-local` stores the final JAR with the Jenkins `BUILD_NUMBER` as version — immutable and traceable.

---

**Q17: What is the Artifactory REST API and how is it used in the Jenkinsfile?**

Artifactory exposes a REST API for artifact management. In the original Jenkinsfile, the JAR was pushed using `curl`:

```bash
curl -s -u ${AF_USER}:${AF_PASS} \
     -T target/order-service-1.0.0.jar \
     "http://artifactory:8082/artifactory/libs-release-local/com/infrasim/order-service/42/order-service-42.jar"
```

The URL structure is: `<artifactory-url>/artifactory/<repo-key>/<group-path>/<version>/<filename>`.

Other REST API operations: search, delete, copy, move, get properties, trigger Xray scan.

---

**Q18: What is the Access Service in Artifactory and why did it cause startup failures?**

The Access Service is an internal microservice within Artifactory (running on port 8046) responsible for authentication, authorization, and token management. Starting from Artifactory 7.x, it became a mandatory component.

In this project the `latest` image pulled a version where the Access Service failed to initialize, causing Artifactory to retry indefinitely. The fix was to pin to version `7.55.14` where this bug is not present.

---

**Q19: How would you configure Jenkins to use Artifactory as a Maven proxy?**

1. In Artifactory, create a remote repository proxying Maven Central
2. Create a virtual repository aggregating `libs-release-local` + the remote proxy
3. In Jenkins, configure the Maven settings via JFrog Jenkins plugin:
   ```groovy
   def server = Artifactory.server('artifactory-server')
   def rtMaven = Artifactory.newMavenBuild()
   rtMaven.resolver server: server, releaseRepo: 'libs-virtual', snapshotRepo: 'libs-snapshot-local'
   rtMaven.deployer server: server, releaseRepo: 'libs-release-local'
   rtMaven.run pom: 'pom.xml', goals: 'clean package'
   ```
4. All Maven downloads go through Artifactory; resolved artifacts and build info are recorded

---

**Q20: What is build info in Artifactory and why is it valuable?**

Build info is metadata Artifactory records about a CI build:
- Which artifacts were produced
- Which dependencies were resolved
- Environment variables at build time
- Test results
- Git commit SHA and branch

It links every artifact back to the exact build that produced it. In Artifactory UI you can click any artifact → Build Info → see exactly which Jenkins build, which git commit, and which dependencies were used. Critical for compliance and incident forensics.

---

**Q21: What is Artifactory's cleanup policy and why is it needed?**

Artifacts accumulate over time — every Jenkins build pushes new Docker images and JARs. Without cleanup, storage is exhausted.

Artifactory supports:
- **Artifact cleanup** — delete artifacts older than N days or beyond N versions
- **Docker tag cleanup** — keep only the last N tags per repository
- **Unused artifact cleanup** — remove artifacts not downloaded in N days

Configured via Artifactory Admin → Repositories → Cleanup Policies or via REST API / JFrog CLI.

---

**Q22: What is the JFrog CLI and what can it do?**

JFrog CLI (`jf`) is a command-line tool for interacting with Artifactory (and other JFrog products). It can:

```bash
# Upload a file
jf rt upload target/*.jar libs-release-local/com/infrasim/

# Download an artifact
jf rt download libs-release-local/com/infrasim/order-service/42/

# Search artifacts
jf rt search "libs-release-local/com/infrasim/*.jar"

# Promote a build
jf rt build-promote order-service 42 docker-prod

# Trigger Xray scan
jf rt build-scan order-service 42
```

The JFrog CLI is preferred over raw `curl` in pipelines as it handles authentication, checksums, and build info automatically.

---

**Q23: What is a Helm chart repository in Artifactory?**

Artifactory can host Helm chart repositories. Teams push packaged Helm charts (`.tgz` files with `Chart.yaml`) to Artifactory, and Kubernetes deployments pull them via `helm install`:

```bash
helm repo add myrepo http://artifactory:8082/artifactory/helm-local
helm install order-service myrepo/order-service --version 1.2.0
```

This makes Helm chart versioning and distribution consistent with other artifact types in the same tool.

---

**Q24: How do you secure Artifactory in production?**

1. **Enable HTTPS** — configure a reverse proxy (nginx/Apache) with TLS in front of Artifactory
2. **Remove default admin password** — change `admin/password` immediately
3. **Create least-privilege users** — separate read-only users for CI pull, write users for CI push
4. **Enable anonymous access restriction** — disable anonymous reads for private repos
5. **Integrate with LDAP/SSO** — authenticate via corporate directory instead of local accounts
6. **Enable Xray scanning** — block downloads of vulnerable artifacts via policy
7. **Network isolation** — Artifactory should not be publicly accessible; only reachable from CI/CD and internal networks

---

**Q25: What is the difference between copy and move operations in Artifactory?**

| Operation | Source artifact | Use case |
|-----------|----------------|----------|
| **Copy** | Stays in place | Promotion while keeping original (audit trail) |
| **Move** | Removed from source | Reorganization, final release promotion |

In artifact promotion workflows, `copy` is preferred — the artifact remains in the dev/staging repo as a record, and a copy exists in the release repo. `move` is used when you want strict control that only the promoted version exists in the target.

---

## Scenario-Based Questions

**S1: A Jenkins build fails with "401 Unauthorized" when pushing to Artifactory. How do you diagnose it?**

1. Verify the `artifactory-creds` credential in Jenkins — is the username/password correct?
2. Test manually: `curl -u admin:password http://localhost:8082/artifactory/api/system/ping`
3. Check if the Artifactory admin password was changed after setup — the credential in Jenkins may be stale
4. Verify the user has write permission on the target repository in Artifactory Admin → Permissions
5. Check if anonymous access is disabled and the credential is being passed correctly in the `curl` or `docker login` command
6. Check Artifactory access logs: Admin → Security → Access Log

---

**S2: Docker images in Artifactory are consuming 200GB of storage. How do you reduce it?**

1. **Identify large images**: Artifactory UI → docker-local → sort by size
2. **Delete old tags**: keep only the last 5 tags per image using a cleanup policy
3. **Enable Docker layer deduplication**: Artifactory deduplicates identical layers across images automatically — ensure it is enabled
4. **Set retention policy**: Admin → Repositories → docker-local → Cleanup Policy: delete tags older than 30 days
5. **Run GC**: Artifactory garbage collection removes unreferenced layers — Admin → Advanced → Maintenance → Garbage Collection
6. **Archive to cold storage**: move rarely-used release artifacts to cheaper storage

---

**S3: A developer reports they can pull an old Docker image version from Artifactory but it runs different code than expected. What could cause this and how do you investigate?**

Possible causes:
1. The image was overwritten — check if the `docker-local` repo allows re-deployment of existing tags (should be disabled for releases)
2. Wrong tag pulled — `latest` points to the most recent push, not necessarily a specific version
3. Docker layer cache — the developer's machine cached an old layer; run `docker pull --no-cache`

Investigation:
1. In Artifactory, click the image tag → Properties → check `build.number` and `build.name` properties
2. Cross-reference the build number with Jenkins build history to find the exact git commit
3. Enable repository "Forbid Overwrite" for `docker-local` to prevent this in the future

---

**S4: Your team is setting up a new microservice. How do you set up its artifact pipeline in Artifactory from scratch?**

1. **Create a local Docker repository** in Artifactory: `docker-notification-local`
2. **Create a local Maven repository**: `libs-notification-local`
3. **Set permissions**: create a permission target granting CI user write access to both repos
4. **Update the Jenkinsfile**: set `DOCKERHUB_REPO` or Artifactory repo key for the new service
5. **Add cleanup policy**: configure max tags retention on the new Docker repo
6. **Enable Xray indexing** on the new repos if Xray is available
7. **Add to virtual repo** so the virtual aggregation URL automatically includes the new repo

---

**S5: Artifactory is returning 503 errors intermittently during peak CI hours when 10 pipelines run simultaneously. How do you fix it?**

1. **Check resource usage**: `docker stats artifactory` — is CPU/memory maxed?
2. **Increase JVM heap**: add `JF_JVM_MAX_HEAP_SIZE=4g` to the compose environment
3. **Check database connections**: if using Derby (embedded), it doesn't handle concurrent writes well — migrate to PostgreSQL
4. **Enable connection pooling**: configure database connection pool size in Artifactory system config
5. **Add a load balancer**: for high concurrency, run multiple Artifactory nodes behind a load balancer (Pro/Enterprise)
6. **Reduce simultaneous pipeline runs**: in Jenkins configure max concurrent builds or use a build queue

---

**S6: A developer pushed a Docker image with a critical vulnerability to `docker-local`. You need to prevent it from being pulled immediately. What do you do?**

1. **Block downloads via Xray policy** (if Xray is available): create a security policy that blocks artifacts with critical CVEs from being downloaded
2. **Delete the specific tag** via Artifactory UI: Artifacts → docker-local → find the image → Delete tag
3. **Or via REST API**:
   ```bash
   curl -u admin:password -X DELETE \
     "http://localhost:8082/artifactory/docker-local/order-service/vulnerable-tag/"
   ```
4. **Notify the team** — alert whoever pulled the image to redeploy with a clean version
5. **Scan all images** in the repo for the same vulnerability: Xray → Watches → trigger manual scan
6. **Add a pipeline scan gate** — add a Xray scan stage before the deploy stage to prevent future vulnerable images from reaching production

---

**S7: A build was promoted to `docker-prod` by mistake. How do you reverse it in Artifactory?**

1. **Delete the specific tag** from `docker-prod`:
   ```bash
   curl -u admin:password -X DELETE \
     "http://localhost:8082/artifactory/docker-prod/order-service/mistaken-tag/"
   ```
2. **Or move it back** using the Artifactory Move API:
   ```bash
   curl -u admin:password -X POST \
     "http://localhost:8082/artifactory/api/move/docker-prod/order-service/mistaken-tag?to=/docker-staging/order-service/mistaken-tag"
   ```
3. Check audit log (Admin → Security → Audit) to confirm the promotion and who did it
4. **Prevention**: implement promotion approvals — require a second person to confirm before promoting to `docker-prod` using Artifactory's permission system or a Jenkins approval step

---

**S8: After migrating Artifactory from Derby to PostgreSQL, artifact downloads are failing with "checksum mismatch". What is wrong?**

Checksum mismatch after a database migration usually means the filestore (binary artifacts) is intact but the database metadata (checksums stored in DB) was corrupted or incompletely migrated.

Steps:
1. Run Artifactory's built-in consistency check: Admin → Advanced → Maintenance → Consistency Check
2. This compares filestore checksums against database records and reports mismatches
3. For each mismatch: Artifactory can re-index the file to repair the metadata
4. If many files are affected, restore the PostgreSQL database from a backup taken during migration
5. Re-run the migration following JFrog's official database migration guide exactly

---

**S9: You need to give a new CI user read-only access to `docker-local` but write access to `libs-snapshot-local`. How do you configure this in Artifactory?**

1. Admin → Security → Users → Create user: `ci-user`
2. Admin → Security → Permission Targets → Add Permission Target:
   - Name: `ci-docker-read`
   - Repository: `docker-local`
   - User `ci-user`: check `Read` only
3. Add another Permission Target:
   - Name: `ci-maven-write`
   - Repository: `libs-snapshot-local`
   - User `ci-user`: check `Read`, `Deploy/Cache`, `Annotate`
4. Test: log in as `ci-user` and verify `docker pull` works but `docker push` to `docker-local` returns 403

---

**S10: Artifactory's `docker-local` repository is growing by 10GB per day. You need to implement an automated cleanup. How do you do it?**

1. **Identify the growth source**: Artifactory UI → docker-local → sort by date — which images are being pushed most?
2. **Create a cleanup policy**: Admin → Repositories → docker-local → Cleanup Policy:
   - Keep last N versions: 10
   - Delete artifacts not downloaded in: 30 days
3. **Schedule the cleanup**: Admin → Advanced → Maintenance → Scheduled Jobs → add Artifact Cleanup
4. **Via REST API** for more control:
   ```bash
   # Delete all tags except the last 5 for order-service
   curl -u admin:password \
     "http://localhost:8082/artifactory/api/search/aql" \
     -d 'items.find({"repo":"docker-local","name":{"$match":"*"},"created":{"$before":"30d"}})'
   ```
5. **Run Docker GC** after deletion to reclaim storage from orphaned layers

---

**S11: A Jenkins pipeline is pushing the same image tag (`latest`) on every build, causing Artifactory to overwrite it. Previous versions are lost. How do you fix it?**

The root issue is using a mutable tag. Fixes:

1. **Tag with BUILD_NUMBER** — already done in this project: `kastanov7/order-service:${BUILD_NUMBER}` — this is immutable
2. **Disable re-deployment** for release repos: Admin → Repositories → docker-local → Repository Configuration → uncheck "Allow Content Browsing" and enable "Forbid Overwrite for Release Artifacts"
3. **Use semantic versioning** instead of build numbers: `1.2.3-${BUILD_NUMBER}`
4. **Keep `latest` but also push the versioned tag** — `latest` is always the most recent, numbered tags allow rollback:
   ```bash
   docker push kastanov7/order-service:${BUILD_NUMBER}
   docker push kastanov7/order-service:latest
   ```

---

**S12: Artifactory's Access Service (port 8046) keeps crashing on startup in a cloud VM. What do you check?**

This was the same issue encountered in this project with the `latest` OSS image. Steps:
1. Check logs: `docker logs artifactory | grep -i "access\|8046\|error"`
2. **Pin to a stable version**: change image to `artifactory-oss:7.55.14` or `artifactory-jcr:7.55.14`
3. **Check available memory**: Access Service requires at minimum 2GB RAM. `free -h` on the host — if under 2GB, the JVM crashes during startup
4. **Check port conflicts**: `ss -tlnp | grep 8046` — another process may be using the port
5. **Check kernel limits**: Access Service requires `vm.max_map_count=524288` — run `sysctl vm.max_map_count` to verify
6. **Review JFrog release notes** for the specific version — some minor versions have known Access Service bugs

---

**S13: You need to audit which team member deployed the production Docker image 2 weeks ago. How do you find this in Artifactory?**

1. **Artifactory Audit Log**: Admin → Security → Audit → filter by repository `docker-prod` and action `deploy`
2. **Build Info**: Navigate to the artifact in docker-prod → Properties → check `build.name` and `build.number` properties
3. **Cross-reference with Jenkins**: use the build number to find the Jenkins build → check "Started by user" in the build log
4. **Artifactory REST API search**:
   ```bash
   curl -u admin:password \
     "http://localhost:8082/artifactory/api/storage/docker-prod/order-service/42/?list"
   ```
   Check `createdBy` field in the response
5. Enable **Xray audit trail** for detailed access logs including downloads and promotions

---

**S14: A remote proxy repository for Docker Hub is caching images but the cache is returning outdated versions. How do you force a refresh?**

1. **Increase cache expiry** — by default Artifactory caches remote artifacts for 15 minutes. For Docker Hub, tags like `latest` can change. Set the cache period to 0 for the `latest` tag or configure `Retrieve Always from Remote`:
   - Admin → Repositories → docker-hub-remote → Advanced → Retrieve Always from Remote: enable
2. **Delete the cached artifact**: navigate to the cached image in the remote repo → Delete
3. **Force re-fetch via REST**:
   ```bash
   curl -u admin:password -X DELETE \
     "http://localhost:8082/artifactory/docker-hub-remote/library/node/latest/"
   ```
4. **Use immutable tags** in Dockerfiles (`FROM node:18.20.4` not `FROM node:latest`) — prevents this problem entirely since the tag never changes

---

**S15: Your organization is moving from Docker Hub to Artifactory as the central Docker registry for all teams. What is the migration plan?**

Phase 1 — Setup:
1. Create `docker-local` repository in Artifactory for internal images
2. Create a remote proxy `docker-hub-remote` for Docker Hub
3. Create a virtual repository `docker-virtual` aggregating both — teams use one URL

Phase 2 — Migrate existing images:
1. For each team image: `docker pull kastanov7/service:tag && docker tag ... artifactory:8082/docker-local/service:tag && docker push`
2. Script this for all repos using the Docker Hub API to list all tags

Phase 3 — Update pipelines:
1. Change `DOCKERHUB_REPO` in all Jenkinsfiles to the Artifactory URL
2. Update `docker login` to authenticate against Artifactory
3. Update `docker-daemon.json` if Artifactory is on HTTP

Phase 4 — Update Dockerfiles:
1. Change `FROM node:18` to `FROM artifactory:8082/docker-virtual/node:18` so base image pulls go through Artifactory cache

Phase 5 — Cutover:
1. Set Docker Hub repositories to read-only / archive
2. Monitor Artifactory for 2 weeks to confirm all teams are pulling from it
3. Decommission Docker Hub paid plan if applicable

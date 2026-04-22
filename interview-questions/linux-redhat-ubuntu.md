# Linux — Red Hat / Ubuntu: Interview Questions

---

## Core Concepts

**Q1: What is the difference between Red Hat Enterprise Linux (RHEL) and Ubuntu?**

| | RHEL | Ubuntu |
|--|------|--------|
| Vendor | Red Hat (IBM) | Canonical |
| Package manager | `dnf` / `yum` (RPM packages) | `apt` (DEB packages) |
| Release model | Major versions (RHEL 8, 9) with long support | LTS every 2 years (22.04, 24.04) + interim |
| Target | Enterprise, stability-focused | Developer-friendly, cloud, desktop |
| Cost | Subscription required | Free |
| Free clone | AlmaLinux, Rocky Linux | — |
| Init system | systemd | systemd |
| Default firewall | firewalld | ufw |

---

**Q2: What is systemd and what replaced it?**

systemd is the init system and service manager used by both RHEL and Ubuntu. It replaced older init systems:
- **SysVinit** — sequential startup with shell scripts in `/etc/init.d/`
- **Upstart** — event-driven, used in Ubuntu before 15.04

systemd starts services in parallel, tracks dependencies, manages logs via journald, and handles socket/device/timer activation.

Key commands:
```bash
systemctl start nginx
systemctl enable nginx      # start on boot
systemctl status nginx
systemctl restart nginx
journalctl -u nginx -f      # follow logs
```

---

**Q3: What is the difference between `apt` and `apt-get`?**

Both manage Debian/Ubuntu packages but differ in interface:
- `apt-get` — older, scriptable, stable output format (use in scripts)
- `apt` — newer, friendlier CLI with progress bars and color (use interactively)

`apt` is essentially a user-friendly wrapper that combines `apt-get` and `apt-cache`.

```bash
apt update              # refresh package list
apt upgrade             # upgrade all packages
apt install nginx       # install package
apt remove nginx        # remove package
apt autoremove          # remove unused dependencies
```

---

**Q4: What is the difference between `dnf` and `yum`?**

Both are package managers for RPM-based systems (RHEL, CentOS, Fedora):
- `yum` — older, Python 2-based, slower
- `dnf` — replacement for yum (RHEL 8+), Python 3, faster dependency resolution, better API

`yum` is still available on RHEL 8/9 but is an alias for `dnf`.

```bash
dnf install nginx
dnf update
dnf remove nginx
dnf search nginx
dnf list installed
```

---

**Q5: What is the Linux file permission model and how do you read `rwxr-xr--`?**

Linux permissions are three groups of three bits: **owner | group | others**

```
rwxr-xr--
│││││││││
│││││││└└─ others: r-- = read only (4)
│││││└└─── group:  r-x = read + execute (5)
│││└└───── owner:  rwx = read + write + execute (7)
```

Octal: `754`

Commands:
```bash
chmod 754 file.sh
chmod u+x file.sh        # add execute for owner
chown kastanov:devs file  # change owner and group
ls -la                   # view permissions
```

---

**Q6: What is the difference between a hard link and a soft (symbolic) link?**

| | Hard Link | Soft Link (Symlink) |
|--|-----------|---------------------|
| Points to | Inode (actual data) | File path |
| Cross-filesystem | No | Yes |
| If original deleted | File data remains | Link breaks (dangling) |
| Directory links | Not allowed | Allowed |
| Created with | `ln file link` | `ln -s file link` |

```bash
ln -s /home/kastanov/infra-sim/phase3 /tmp/phase3-link
ls -la /tmp/phase3-link   # shows → /home/kastanov/infra-sim/phase3
```

---

**Q7: What are Linux runlevels and systemd targets?**

Runlevels (SysVinit) are replaced by systemd targets:

| Runlevel | systemd Target | Description |
|----------|---------------|-------------|
| 0 | `poweroff.target` | Shutdown |
| 1 | `rescue.target` | Single user / recovery |
| 3 | `multi-user.target` | Multi-user, no GUI |
| 5 | `graphical.target` | Multi-user with GUI |
| 6 | `reboot.target` | Reboot |

```bash
systemctl get-default              # current default target
systemctl set-default multi-user   # set default (no GUI on boot)
systemctl isolate rescue.target    # switch to rescue mode now
```

---

**Q8: What is the `/etc/fstab` file and what does each column mean?**

`/etc/fstab` defines filesystems to mount at boot:

```
/dev/sda1   /          ext4   defaults        0  1
/dev/sda2   /home      ext4   defaults        0  2
tmpfs       /tmp       tmpfs  nodev,nosuid    0  0
```

Columns: `device | mount_point | filesystem_type | options | dump | fsck_order`

- `dump` — 0=no backup, 1=backup
- `fsck_order` — 0=skip, 1=check first (root), 2=check after root

---

**Q9: What is the difference between `/etc/passwd` and `/etc/shadow`?**

- `/etc/passwd` — readable by all users. Contains: `username:x:UID:GID:comment:home:shell`. The `x` means password is in shadow.
- `/etc/shadow` — readable only by root. Contains hashed passwords, expiry dates, and lockout info.

```bash
cat /etc/passwd | grep kastanov
# kastanov:x:1000:1000::/home/kastanov:/bin/bash

sudo cat /etc/shadow | grep kastanov
# kastanov:$6$hash...:19000:0:99999:7:::
```

Separating them prevents unprivileged users from accessing password hashes for offline cracking.

---

**Q10: What is SELinux?**

It is a **Mandatory Access Control (MAC)** systems that enforce security policies beyond standard Unix permissions.

It's a security layer on top of Linux that controls what processes can access — even if a process is hacked, SELinux limits what damage it can do.

Real example:
Web server can't read SSH keys
Without SELinux: if Apache is compromised, attacker could read /etc/ssh/ keys.
With SELinux: Apache is only allowed to access web content directories — accessing SSH keys is blocked even as root.


**Step 1 — Check if SELinux is blocking it**


**Look for denials in the log**

ausearch -m avc -ts recent




**Step 2 — See the current context on the directory**


**ls -Z /data/website**

Output: unconfined_u:object_r:default_t:s0  (wrong type for Apache)




**Step 3 — Fix the context**


**Apply correct SELinux type to your directory**

semanage fcontext -a -t httpd_sys_content_t "/data/website(/.*)?"


**Restore the context**

restorecon -Rv /data/website


**Verify**

ls -Z /data/website

Now shows: httpd_sys_content_t


**Step 4 — Test Apache**


systemctl restart httpd




**-a
Short for add. You're adding a new rule. Other options are:**


-m = modify existing rule

-d = delete rule

-l = list all rules

-t = type. 


**httpd_sys_content_t means:**


httpd = Apache/Nginx web server

sys_content = static content the server is allowed to read

_t = suffix meaning it's a type



---

**Q11: What is `sudo` and how is it configured?**

`sudo` allows a regular user to run commands as root (or another user) without switching accounts. Configuration is in `/etc/sudoers` (edit with `visudo`):

```bash
# Allow kastanov to run all commands as root
kastanov ALL=(ALL:ALL) ALL

# Allow kastanov to run docker without password
kastanov ALL=(ALL) NOPASSWD: /usr/bin/docker

# Allow group devops to run systemctl
%devops ALL=(ALL) NOPASSWD: /bin/systemctl
```

`visudo` validates syntax before saving — a syntax error in sudoers can lock out all sudo access.

---

**Q12: What is the difference between `kill`, `kill -9`, and `pkill`?**

| Command | Signal | Behavior |
|---------|--------|----------|
| `kill PID` | SIGTERM (15) | Politely ask process to terminate; process can handle/ignore |
| `kill -9 PID` | SIGKILL (9) | Force kill — cannot be caught or ignored by the process |
| `kill -HUP PID` | SIGHUP (1) | Reload config without restarting (many daemons support this) |
| `pkill nginx` | SIGTERM | Kill by process name instead of PID |
| `killall nginx` | SIGTERM | Kill all processes named nginx |

Always try SIGTERM first — SIGKILL prevents the process from cleaning up (closing files, releasing locks).

---

**Q13: What is a Linux process and what information does `ps aux` show?**

```bash
ps aux
USER    PID  %CPU %MEM    VSZ   RSS TTY  STAT  START  TIME COMMAND
root      1   0.0  0.1  16952  1024 ?    Ss   Apr19  0:01 /sbin/init
kastanov 1234  1.2  2.5 512000 25600 pts/0 S+  10:00  0:03 java -jar app.jar
```

- `VSZ` — virtual memory size (includes swapped out memory)
- `RSS` — resident set size (actual RAM used)
- `STAT` — process state: S=sleeping, R=running, Z=zombie, D=uninterruptible sleep
- `+` — foreground process

---

**Q14: What is the difference between `top` and `htop`?**

Both show real-time process and resource usage:
- `top` — built-in, available everywhere, keyboard-driven, minimal UI
- `htop` — enhanced version, color UI, mouse support, easier process management, not always pre-installed

Key `top` shortcuts: `k`=kill, `r`=renice, `q`=quit, `M`=sort by memory, `P`=sort by CPU, `1`=show per-CPU stats

---

**Q15: What is `cron` and how do you write a cron expression?**

`cron` is the Linux task scheduler. Each line in `crontab` has the format:
```
minute hour day month weekday command
  *      *    *    *     *
```

Examples:
```bash
0 2 * * *        /backup.sh          # daily at 2am
*/5 * * * *      /check-health.sh    # every 5 minutes
0 9 * * 1-5      /send-report.sh     # weekdays at 9am
0 0 1 * *        /monthly-cleanup.sh # 1st of every month
```

```bash
crontab -e    # edit current user's crontab
crontab -l    # list crontab
crontab -r    # remove crontab
```

---

## Networking

**Q16: What is the difference between `netstat` and `ss`?**

Both show network connections but `ss` is the modern replacement for `netstat`:
- `netstat` — older, reads from `/proc`, slower on large systems
- `ss` — faster, reads kernel data directly, same syntax

```bash
ss -tlnp          # TCP listening ports with process names
ss -tulnp         # TCP + UDP
netstat -tlnp     # equivalent (deprecated)

# Find what is using port 8080
ss -tlnp | grep 8080
```

---

**Q17: What is `iptables` and how does it differ from `firewalld` and `ufw`?**

All three manage the Linux kernel's netfilter packet filtering:

| | iptables | firewalld (RHEL) | ufw (Ubuntu) |
|--|----------|-----------------|--------------|
| Level | Low-level, direct kernel rules | Frontend for iptables/nftables | Frontend for iptables |
| Persistence | Manual (`iptables-save`) | Built-in | Built-in |
| Concepts | Tables/chains/rules | Zones and services | Allow/deny rules |
| Complexity | High | Medium | Low |

```bash
# ufw (Ubuntu)
ufw allow 8080/tcp
ufw enable
ufw status

# firewalld (RHEL)
firewall-cmd --add-port=8080/tcp --permanent
firewall-cmd --reload
firewall-cmd --list-ports
```

---

**Q18: What is `nmcli` and what can you do with it?**

`nmcli` (NetworkManager CLI) manages network connections on RHEL/Ubuntu systems with NetworkManager:

```bash
nmcli device status              # show all network interfaces
nmcli connection show            # list connections
nmcli connection up eth0         # bring up interface
nmcli connection modify eth0 ipv4.addresses 192.168.1.100/24
nmcli connection modify eth0 ipv4.gateway 192.168.1.1
nmcli connection modify eth0 ipv4.dns "8.8.8.8 8.8.4.4"
nmcli connection modify eth0 ipv4.method manual
nmcli connection up eth0
```

---

**Q19: What is `/etc/hosts` and when does it take priority over DNS?**

`/etc/hosts` is a local hostname-to-IP mapping file. The resolution order is controlled by `/etc/nsswitch.conf`:

```
hosts: files dns
```

`files` (i.e., `/etc/hosts`) is checked first. If a match is found, DNS is never queried.

Used in this project's Docker environment — container names like `kafka`, `sonarqube`, `app_db` resolve via Docker's internal DNS, not `/etc/hosts`. But on the host machine, `/etc/hosts` could be used to create friendly aliases.

---

**Q20: What is the difference between TCP and UDP and when would you use each?**

| | TCP | UDP |
|--|-----|-----|
| Connection | Established (3-way handshake) | Connectionless |
| Reliability | Guaranteed delivery, ordered | No guarantee, no ordering |
| Speed | Slower (overhead) | Faster (no handshake) |
| Use cases | HTTP, SSH, databases, Kafka | DNS, video streaming, monitoring metrics |

In this project: Kafka uses TCP, Prometheus metrics scraping uses TCP (HTTP), DNS resolution uses UDP.

---

## File System & Storage

**Q21: What is LVM and what advantages does it provide?**

LVM (Logical Volume Manager) is an abstraction layer over physical storage:

```
Physical Volumes (PV) → Volume Group (VG) → Logical Volumes (LV) → Filesystems
/dev/sda1 + /dev/sdb1 → vg_data           → lv_home, lv_var
```

Advantages:
- **Resize on the fly** — extend LV without unmounting: `lvextend -L +10G /dev/vg_data/lv_home`
- **Snapshots** — instant read-only snapshot for backups
- **Spanning** — one LV can span multiple physical disks
- **Easy migration** — move data between disks without downtime

---

**Q22: What is `df` vs `du` and when do you use each?**

```bash
df -h           # disk space per filesystem (total/used/available)
du -sh /var/*   # disk usage per directory (what is consuming space)
```

- `df` — filesystem-level: how full is the partition?
- `du` — directory-level: what is taking up the space?

Common workflow: `df -h` shows `/var` is 95% full → `du -sh /var/*` shows `/var/log` is 40GB → `du -sh /var/log/*` narrows down the specific log file.

---

**Q23: What is the difference between `ext4`, `xfs`, and `tmpfs`?**

| Filesystem | Used on | Characteristics |
|------------|---------|-----------------|
| `ext4` | Ubuntu default | Journaled, widely supported, good general purpose |
| `xfs` | RHEL default | High performance, large files, no shrinking |
| `tmpfs` | `/tmp`, `/run` | RAM-based, lost on reboot, extremely fast |
| `overlay` | Docker | Union filesystem, layers images on top of each other |

Docker uses `overlay2` on both RHEL and Ubuntu — each image layer is a directory; containers add a writable layer on top.

---

**Q24: What does `inode` mean and what happens when inodes are exhausted?**

An inode stores file metadata (permissions, owner, timestamps, block locations) — not the filename or content. Every file/directory uses one inode.

When inodes are exhausted:
- `df -i` shows 100% inode usage
- New files cannot be created even if there is disk space
- Common cause: millions of small files (log files, temp files, Docker image layers)

Fix:
```bash
df -i                           # check inode usage
find /tmp -type f | wc -l       # count files
find /tmp -mtime +7 -delete     # delete files older than 7 days
```

---

**Q25: What is `rsync` and how is it different from `cp`?**

`rsync` synchronizes files between two locations (local or remote):
```bash
rsync -avz /home/kastanov/ user@server:/backup/kastanov/
# -a: archive (preserve permissions, timestamps, symlinks)
# -v: verbose
# -z: compress during transfer
# --delete: remove files from destination that don't exist in source
```

Differences from `cp`:
- Only transfers changed parts of files (delta transfer)
- Works over SSH for remote transfers
- Preserves all file metadata
- Can resume interrupted transfers

Used in this project context: backup `jenkins_data` volume to a remote server without copying unchanged files every time.

---

## Process & Performance

**Q26: What is `strace` and when would you use it?**

`strace` traces system calls made by a process — every interaction with the Linux kernel is logged:

```bash
strace -p 1234              # attach to running process
strace -e trace=network curl https://example.com  # trace only network calls
strace -f -o /tmp/trace.log java -jar app.jar     # trace including forks
```

Use when:
- A program fails with a cryptic error — strace shows the exact failing syscall
- Debugging permission issues — see exactly which file is being denied
- Understanding what files a program reads at startup

---

**Q27: What is the `load average` shown in `top` and `uptime`?**

```bash
uptime
# 14:23:01 up 3 days, load average: 0.52, 1.20, 0.88
#                                    1min  5min  15min
```

Load average is the average number of processes waiting for CPU or I/O over 1, 5, and 15 minutes. On a 4-core system:
- Load < 4.0 — healthy
- Load = 4.0 — fully utilized
- Load > 4.0 — overloaded, processes queuing

High load from CPU-bound work: `top` shows high `%us` or `%sy`
High load from I/O wait: `top` shows high `%wa` — disk or network is the bottleneck

---

**Q28: What is `nice` and `renice` and why would you use them?**

`nice` sets the scheduling priority of a process (-20 = highest priority, 19 = lowest):

```bash
nice -n 19 mvn clean package    # run Maven build at lowest priority
nice -n -5 /critical-service    # run at higher than normal priority (requires root)
renice -n 10 -p 1234            # lower priority of running process
```

Use case in this project: run Jenkins Maven builds with `nice -n 10` so they don't starve the order-service running on the same host.

---

**Q29: What is swap and when is it used?**

Swap is disk space used as an overflow when RAM is full. The kernel moves inactive memory pages to swap to free up RAM.

```bash
free -h             # show RAM and swap usage
swapon --show       # list swap devices
vmstat 1            # monitor swap activity (si=swap in, so=swap out)
```

High swap usage (`so` in vmstat) means the system is paging heavily — severe performance degradation. In containers, swap should usually be disabled (`--memory-swap`) to make OOM (Out of Memory) behavior predictable.

---

**Q30: What is `journalctl` and how do you use it to debug service failures?**

`journalctl` reads logs from systemd's journal:

```bash
journalctl -u jenkins           # all logs for jenkins service
journalctl -u jenkins -f        # follow (like tail -f)
journalctl -u jenkins --since "1 hour ago"
journalctl -u jenkins -p err    # only errors
journalctl --disk-usage         # how much space logs use
journalctl --vacuum-time=7d     # delete logs older than 7 days
```

For Docker containers (not systemd services), use `docker logs` instead since container output goes to the Docker logging driver, not journald (unless configured otherwise).

---

## Users & Security

**Q31: What is the difference between `su` and `sudo su`?**

- `su -` — switch to root user, requires root's password. Full login shell.
- `su username` — switch to another user, requires that user's password
- `sudo su -` — become root using your own password (if sudo is configured). Preferred in modern systems because it is audited.
- `sudo -i` — same as `sudo su -`, opens root login shell

In RHEL by default, root SSH login is disabled — `sudo` is the standard escalation path.

---

**Q32: What is PAM (Pluggable Authentication Modules) in Linux?**

PAM is a framework that separates authentication logic from applications. Instead of each program implementing its own authentication, they delegate to PAM which chains configured modules:

```
# /etc/pam.d/sshd
auth    required  pam_unix.so      # check /etc/shadow password
auth    required  pam_tally2.so    # lockout after failed attempts
account required  pam_nologin.so   # check if logins are allowed
session required  pam_limits.so    # apply resource limits
```

Keycloak, SSH, and `sudo` all use PAM. Adding MFA, LDAP authentication, or IP-based access restrictions is done by adding PAM modules — no application changes needed.

---

**Q33: What are Linux namespaces and how do they enable Docker containers?**

Namespaces isolate kernel resources so each container sees its own view of the system:

| Namespace | Isolates |
|-----------|---------|
| `pid` | Process IDs — container has its own PID 1 |
| `net` | Network interfaces, routing tables, ports |
| `mnt` | Filesystem mounts |
| `uts` | Hostname and domain name |
| `ipc` | Inter-process communication |
| `user` | User and group IDs |

Docker creates a new set of namespaces for each container. This is why a container thinks it is the only process on the system while sharing the host kernel.

---

**Q34: What are cgroups and how do they relate to Docker resource limits?**

cgroups (Control Groups) limit and account for resource usage of process groups:

```bash
# Docker uses cgroups to enforce limits:
docker run --memory=512m --cpus=1 order-service
```

Under the hood Docker creates a cgroup at `/sys/fs/cgroup/memory/docker/<container-id>/` and sets `memory.limit_in_bytes`. The kernel enforces the limit — if the container exceeds it, the OOM killer terminates a process inside the container.

```bash
cat /sys/fs/cgroup/memory/docker/<id>/memory.limit_in_bytes
```

---

**Q35: What is `ssh-keygen` and how do you set up passwordless SSH?**

```bash
# On the source machine (Jenkins container):
ssh-keygen -t ed25519 -f /var/jenkins_home/.ssh/id_rsa -N ""
# -N "": no passphrase (needed for automated scripts)

# Copy public key to target machine:
ssh-copy-id -i /var/jenkins_home/.ssh/id_rsa.pub kastanov@172.18.0.1

# Or manually append:
cat id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

This is exactly what is needed in this project — the Jenkins container needs its public key in `~/.ssh/authorized_keys` on the WSL2 host so Ansible can SSH without a password.

---

## Package Management & System Administration

**Q36: What is the difference between `rpm` and `dpkg`?**

Both are low-level package tools — they install package files directly without resolving dependencies:

| | rpm (RHEL) | dpkg (Ubuntu) |
|--|------------|---------------|
| Install | `rpm -ivh package.rpm` | `dpkg -i package.deb` |
| Remove | `rpm -e package` | `dpkg -r package` |
| List installed | `rpm -qa` | `dpkg -l` |
| Query file | `rpm -qf /etc/nginx/nginx.conf` | `dpkg -S /etc/nginx/nginx.conf` |

`dnf`/`apt` are built on top of these and add dependency resolution and repo management.

---

**Q37: What is `systemctl enable` vs `systemctl start`?**

- `systemctl start nginx` — starts nginx **now** but does not persist across reboots
- `systemctl enable nginx` — creates a symlink so nginx **starts on boot** but does not start it now
- `systemctl enable --now nginx` — does both at once

```bash
# Check if service is enabled (will start on boot):
systemctl is-enabled nginx

# Check if service is currently running:
systemctl is-active nginx
```

---

**Q38: What is a Linux daemon and how is it different from a regular process?**

A daemon is a background process that:
- Has no controlling terminal (detached from TTY)
- Typically started at boot by systemd
- Named with a `d` suffix: `sshd`, `dockerd`, `nginx`, `httpd`
- Runs continuously waiting for events or requests

Regular processes are started by users in a terminal, tied to that terminal session. A daemon survives terminal close and system boot.

```bash
systemctl list-units --type=service --state=running  # list running daemons
```

---

**Q39: What is `logrotate` and why is it important?**

`logrotate` automatically rotates, compresses, and deletes log files to prevent disk exhaustion:

```bash
# /etc/logrotate.d/nginx
/var/log/nginx/*.log {
    daily
    rotate 14          # keep 14 days
    compress           # gzip old logs
    delaycompress      # compress previous, not current rotation
    missingok          # don't error if log is missing
    notifempty         # don't rotate empty files
    postrotate
        nginx -s reopen  # tell nginx to reopen log files
    endscript
}
```

Without logrotate, `/var/log` fills up and services start failing when they cannot write logs.

---

**Q40: What is the difference between `grep`, `awk`, and `sed`?**

| Tool | Purpose | Example |
|------|---------|---------|
| `grep` | Search/filter lines matching a pattern | `grep "ERROR" app.log` |
| `awk` | Field-based text processing | `awk '{print $1, $3}' access.log` (print cols 1 and 3) |
| `sed` | Stream editor — find/replace/delete | `sed 's/localhost/app_db/g' config.yml` |

Real example from this project:
```bash
# Find all ERROR lines in order-service logs
docker logs order_service | grep ERROR

# Extract just the timestamp and message
docker logs order_service | awk '{print $1, $2, $NF}'

# Replace old registry in Jenkinsfile
sed -i 's/localhost:8082/kastanov7/g' Jenkinsfile
```

---

## Scenario-Based Questions

**S1: A Linux server is completely unresponsive but you can still SSH in. CPU is at 100%. How do you diagnose and recover it?**

1. `top` or `htop` — identify the process consuming CPU (`P` to sort by CPU)
2. `ps aux --sort=-%cpu | head -10` — top CPU consumers
3. Check if it is a runaway process or legitimate load:
   - Runaway: `kill -15 <PID>` → wait 5s → `kill -9 <PID>` if still running
   - Legitimate: investigate why (e.g., a Java GC loop, a stuck Maven build)
4. Check for zombie processes: `ps aux | grep Z`
5. Check `dmesg | tail -20` — kernel OOM killer messages
6. If the process is a Jenkins build: `docker exec jenkins kill -9 <PID>` or cancel the build in UI

---

**S2: `/var/log` is 100% full and all services are writing errors about being unable to log. What do you do immediately?**

Immediate relief (without data loss):
1. `df -h` to confirm which partition is full
2. `du -sh /var/log/*` — identify the largest log file
3. **Truncate** the largest log (do NOT delete while service is using it):
   ```bash
   > /var/log/syslog              # truncate to 0 bytes
   truncate -s 0 /var/log/app.log
   ```
4. `systemctl restart rsyslog` — restart logging service after truncation
5. Compress old logs: `gzip /var/log/*.log.1`

Long-term:
1. Configure `logrotate` for the offending service
2. Add disk usage monitoring in Prometheus with an alert at 80%

---

**S3: A developer says "I can't SSH to the server, it times out". You can SSH to it fine from your machine. What do you check?**

1. **Is it a network issue?** `ping <server>` from their machine — if timeout, routing or firewall issue
2. **Is it a firewall rule?** Check if their IP is allowed: `sudo iptables -L -n | grep 22` or `firewall-cmd --list-all`
3. **Is SSH itself working?** Try `ssh -v` for verbose output — shows exactly where it hangs
4. **Too many connections?** `ss -tnp | grep :22 | wc -l` — check `MaxSessions` in `/etc/ssh/sshd_config`
5. **Hosts.deny?** `cat /etc/hosts.deny` — their IP may be blocked
6. **Failed logins lockout?** `faillock --user <username>` (RHEL) or `pam_tally2 --user` — too many failed attempts triggers lockout
7. Ask them to try: `ssh -o ConnectTimeout=5 user@server` — does it refuse or timeout?

---

**S4: A critical service needs to be restarted but it keeps failing to start. `systemctl status` shows "failed". How do you debug it?**

```bash
systemctl status order-service       # check status and recent log lines
journalctl -u order-service -n 50    # last 50 log lines
journalctl -u order-service --since "5 min ago"  # recent logs

# Check exit code
systemctl show order-service -p ExecMainStatus

# Try starting manually to see output directly
/usr/bin/java -jar /opt/order-service/app.jar

# Check for port conflicts
ss -tlnp | grep 8888

# Check for permission issues
ls -la /opt/order-service/
ls -la /var/log/order-service/
```

Most common causes: wrong working directory, missing environment variable, port already in use, permission denied on log directory.

---

**S5: You need to find which process is listening on port 9000 (SonarQube) and it is not responding. How do you investigate?**

```bash
ss -tlnp | grep 9000          # find PID listening on 9000
lsof -i :9000                 # alternative: list open files on port 9000

# Get the PID from above, then:
ps aux | grep <PID>           # what process is it?
cat /proc/<PID>/status        # process state
strace -p <PID>               # what is it doing?
ls -la /proc/<PID>/fd/        # what files/sockets it has open

# Check if SonarQube's Elasticsearch is stuck:
journalctl -u sonarqube --since "10 min ago"
docker logs sonarqube --tail 50
```

---

**S6: A server has been running for 200 days. You notice memory usage is at 95% but the top processes look normal. What is consuming the memory?**

Memory fragmentation or kernel buffers — Linux uses free RAM for page cache. `free -h` breakdown:

```bash
free -h
#              total   used   free  shared  buff/cache  available
# Mem:          15Gi   12Gi  512Mi   256Mi        3Gi       2.5Gi
```

`available` is what matters — includes reclaimable cache. If `available` is low:
1. `smem -r -k | head -20` — processes sorted by actual RAM used (accounts for shared libs)
2. Check for memory leaks: `cat /proc/<PID>/status | grep VmRSS` — compare over time
3. Check kernel slab cache: `slabtop` — kernel object caches consuming RAM
4. If Docker is running: `docker system df` — images and containers consuming RAM
5. Force page cache drop (safe): `echo 3 > /proc/sys/vm/drop_caches`

---

**S7: You need to schedule a one-time task (not recurring) to run at 3am tonight. How do you do it without cron?**

Use `at`:
```bash
echo "/home/kastanov/infra-sim/setup.sh" | at 03:00
at 03:00 -f /home/kastanov/backup.sh

atq          # list scheduled at jobs
atrm 2       # remove job #2
```

`at` runs the command once at the specified time. Unlike cron it is not recurring.

Alternative: `systemd-run` for a transient systemd timer:
```bash
systemd-run --on-calendar="03:00" /path/to/script.sh
```

---

**S8: After a kernel update, a server won't boot. You have access to the GRUB menu. How do you recover?**

1. At GRUB menu, press `e` to edit the boot entry
2. Select the **previous kernel version** entry (GRUB keeps the last 3 by default)
3. Boot into the previous kernel to restore service immediately
4. Once booted, investigate why the new kernel failed:
   ```bash
   dmesg | grep -i "error\|fail"
   journalctl -b -1          # logs from the previous (failed) boot
   ```
5. If a driver/module is incompatible: `modprobe -r <module>` and add to `/etc/modprobe.d/blacklist.conf`
6. Set the working kernel as default: `grub2-set-default "saved_entry"` (RHEL)

---

**S9: A user reports their home directory is full but `df -h` shows the filesystem has plenty of space. How do you explain and fix this?**

The user has hit their **disk quota** — a per-user limit separate from total filesystem space.

```bash
quota -u kastanov             # check user quota
repquota -a                   # report all users' quota usage
```

Fix options:
1. Delete unnecessary files in the home directory: `du -sh ~/* | sort -h`
2. Increase the user's quota (as root): `edquota kastanov`
3. Move large files (e.g., Maven cache, Docker images) to a non-quota filesystem

Common culprits: Maven `~/.m2` cache, npm `~/.npm`, Docker images in `~/.docker`.

---

**S10: You need to copy 500GB of data between two servers without interrupting other services and resume if the connection drops. What tool do you use?**

`rsync` over SSH with `--partial` and `--progress`:
```bash
rsync -avz --partial --progress \
  /data/backups/ \
  kastanov@server2:/data/backups/

# --partial: keep partially transferred files (enables resume)
# --progress: show transfer progress
# --bwlimit=10000: limit bandwidth to 10MB/s to avoid saturating the link
rsync -avz --partial --bwlimit=10000 /data/ kastanov@server2:/data/
```

For very large transfers, run inside `tmux` or `screen` so the rsync continues if your SSH session drops:
```bash
tmux new -s rsync-session
rsync -avz --partial /data/ kastanov@server2:/data/
# Ctrl+B, D to detach — rsync keeps running
```

---

**S11: An application is writing logs so fast that it fills the disk in minutes. You cannot restart the application. How do you handle it?**

1. **Identify the log file**: `lsof -p <PID> | grep log` — find which file is growing
2. **Truncate without restarting**:
   ```bash
   truncate -s 0 /var/log/app/fast.log
   ```
3. **Redirect to /dev/null temporarily** (advanced): use `gdb` to replace the file descriptor
4. **Set up a log rotation loop** using `watch`:
   ```bash
   watch -n 60 'truncate -s 0 /var/log/app/fast.log'
   ```
5. **Root cause**: reduce log verbosity — if app supports signal-based log level change: `kill -USR1 <PID>` (many Java apps support this to switch to WARN level)
6. Add monitoring alert: `df -h` + alert when `/var/log` > 80%

---

**S12: You need to give a developer temporary sudo access for 2 hours to debug a production issue. How do you implement this safely?**

Option 1 — Time-limited sudoers entry:
```bash
# Add to /etc/sudoers.d/developer-temp
developer ALL=(ALL) NOPASSWD: ALL
# Set a cron job to remove it after 2 hours:
echo "rm /etc/sudoers.d/developer-temp" | at now + 2 hours
```

Option 2 — `sudo` with expiry using PAM:
```bash
# Use Wallix or a similar PAM tool for proper time-limited access
```

Option 3 — Pair programming approach (safest):
1. Give them a screen/tmux session you can observe
2. You run commands they request — you retain control
3. `script /tmp/session.log` — record everything

After the session:
```bash
last developer          # audit login history
journalctl | grep developer  # command audit trail
```

---

**S13: A server's clock is drifting by 5 minutes. Why does this matter and how do you fix it?**

Clock drift breaks:
- **TLS certificates** — validation fails if clock is off by more than allowed skew
- **JWT tokens** — `exp` and `nbf` checks fail (Keycloak tokens rejected by order-service)
- **Distributed logs** — events in Loki/Grafana appear out of sequence
- **Kerberos** — authentication fails if clock is off by more than 5 minutes
- **Kafka** — message timestamps are wrong

Fix — enable and configure NTP (Network Time Protocol):
```bash
# RHEL
timedatectl set-ntp true
systemctl enable --now chronyd
chronyc tracking         # verify sync status

# Ubuntu
timedatectl set-ntp true
systemctl enable --now systemd-timesyncd
timedatectl show-timesync
```

---

**S14: You are asked to harden a freshly deployed Ubuntu server before putting it into production. What are the first 10 steps?**

1. **Update packages**: `apt update && apt upgrade -y`
2. **Disable root SSH login**: `/etc/ssh/sshd_config` → `PermitRootLogin no`
3. **Disable password SSH auth**: `PasswordAuthentication no` → use keys only
4. **Create a non-root user with sudo**: `adduser kastanov && usermod -aG sudo kastanov`
5. **Enable UFW firewall**: `ufw allow ssh && ufw allow 80 && ufw allow 443 && ufw enable`
6. **Install fail2ban**: `apt install fail2ban` — auto-ban IPs with too many failed SSH attempts
7. **Disable unused services**: `systemctl disable cups avahi-daemon`
8. **Configure automatic security updates**: `dpkg-reconfigure unattended-upgrades`
9. **Set strong SSH config**: `AllowUsers kastanov`, `MaxAuthTries 3`, `ClientAliveInterval 300`
10. **Enable AppArmor**: `aa-status` — ensure it is enforcing profiles

---

**S15: Your Ansible playbook fails on a RHEL server but works on Ubuntu. The error is "sudo: a password is required". How do you fix it?**

RHEL servers often require a sudo password by default, unlike Ubuntu where NOPASSWD is sometimes configured.

Fix options:

1. **Configure NOPASSWD for the deploy user** on the RHEL server:
   ```bash
   echo "deploy ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/deploy
   ```

2. **Pass the sudo password via Ansible vault**:
   ```bash
   # inventory.ini
   ansible_become_pass={{ sudo_password }}
   
   # Store in vault:
   ansible-vault encrypt_string 'mypassword' --name 'sudo_password'
   
   # Run with:
   ansible-playbook playbook.yml --ask-vault-pass
   ```

3. **Use `become: false`** if the playbook tasks don't actually require root — check if `become: true` is set unnecessarily in the playbook

4. **Check sudoers on the RHEL server**: `visudo` — ensure `requiretty` is disabled: `Defaults !requiretty` (tty requirement blocks Ansible SSH)

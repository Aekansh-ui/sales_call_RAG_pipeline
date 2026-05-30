# T-00 — Prerequisites & Environment Setup
# Command & Concept Reference

> This file logs every concept taught and every shell command used during T-00.
> Purpose: a detailed reference you can return to at any point — not a summary.
> Structure: concepts first (the "why" and "how it works"), commands second (the "what to run").

---

## Table of Contents

### Concepts
- [C1. What is containerization?](#c1-what-is-containerization)
- [C2. Containers vs. Virtual Machines](#c2-containers-vs-virtual-machines)
- [C3. Docker architecture — daemon, CLI, registry](#c3-docker-architecture--daemon-cli-registry)
- [C4. Images vs. containers vs. volumes](#c4-images-vs-containers-vs-volumes)
- [C5. Why we containerize this project](#c5-why-we-containerize-this-project)
- [C6. Docker Compose and the service graph](#c6-docker-compose-and-the-service-graph)

### Commands
- [1. Environment audit commands](#1-environment-audit-commands)
- [2. Starting the Docker daemon](#2-starting-the-docker-daemon)
- [3. Verifying Docker works](#3-verifying-docker-works)

---

# PART A — Concepts

> Deep explanations of every technology, idea, and design decision introduced in T-00.

---

## C1. What is containerization?

**What it is:**
Containerization is a way to package an application together with everything it needs
to run — its code, runtime, libraries, config, and dependencies — into a single
self-contained unit called a **container**. The container runs identically on any
machine that has a container runtime (Docker), regardless of what else is installed on
that machine.

**How it actually works (internals):**
Containers are not magic — they use two Linux kernel features that have existed since the
early 2000s:

1. **Namespaces** — isolate what a process can *see*. A container has its own namespace
   for the filesystem, network interfaces, process IDs, hostname, and user IDs. From
   inside the container, it looks like a complete independent machine, even though it's
   just a process (or set of processes) on the host.

2. **cgroups (control groups)** — limit what a process can *use*. cgroups enforce CPU,
   memory, and I/O quotas so one container can't starve the others.

Docker wraps these two kernel features with a user-friendly CLI and a standard image
format, making containers easy to build, share, and run.

**Why we use it in this project:**
Our stack has 5 services (Postgres, Ollama, the app, Nginx, cloudflared), each with
different runtime requirements. Without containers:
- Postgres 16, Ollama, and Python 3.11 would all need to be installed on the host,
  potentially conflicting with other projects.
- The setup would be different on every developer's machine.
- "Works on my machine" becomes a real problem.

With containers, `docker compose up` gives everyone an identical environment in one command.

**Tradeoffs:**
- Adds a layer of abstraction — debugging inside containers is slightly harder than
  debugging directly on the host.
- Container startup is fast but not instant (a few seconds per service).
- Docker must be installed and the daemon must be running.

---

## C2. Containers vs. Virtual Machines

**The common confusion:**
Both containers and VMs isolate an application from the host. But they do it very
differently, with significant consequences for speed, size, and overhead.

**Virtual Machines:**
A VM runs a complete, separate operating system (guest OS) on top of a hypervisor
(software that emulates hardware). Each VM includes:
- A full Linux/Windows kernel
- All OS processes (init, udev, sshd, etc.)
- The application

A typical VM image is 1–20 GB. Boot time is 30–60 seconds. RAM overhead is 512 MB–2 GB
per VM just for the OS.

**Containers:**
A container shares the host's Linux kernel. It doesn't run a guest OS — it just runs the
application (and its dependencies) inside an isolated namespace. A container image is
typically 50–500 MB. Start time is under 1 second. RAM overhead is negligible.

```
VM stack:                       Container stack:
┌─────────────────┐             ┌──────────┐ ┌──────────┐ ┌──────────┐
│   Application   │             │  App A   │ │  App B   │ │  App C   │
├─────────────────┤             ├──────────┴─┴──────────┴─┴──────────┤
│    Guest OS     │             │          Docker Engine              │
├─────────────────┤             ├────────────────────────────────────┤
│   Hypervisor    │             │           Host OS + Kernel         │
├─────────────────┤             ├────────────────────────────────────┤
│   Host OS       │             │              Hardware               │
└─────────────────┘             └────────────────────────────────────┘
```

**When to use VMs:**
- You need to run a different OS entirely (e.g., Windows on a Linux host).
- You need stronger security isolation (containers share the kernel — a kernel exploit
  can escape a container; it cannot escape a VM).
- Your workload requires persistent full-OS configuration.

**When to use containers (us):**
- All services run Linux — no OS boundary needed.
- You want fast startup, low overhead, and reproducible builds.
- You want to ship the exact same environment to any machine.

---

## C3. Docker architecture — daemon, CLI, registry

**Three separate pieces work together:**

```
┌─────────────────────────────────────────────────────────┐
│  Your terminal                                           │
│  ┌──────────────────┐                                   │
│  │  Docker CLI      │  ← you type commands here        │
│  │  (docker, ...)   │                                   │
│  └────────┬─────────┘                                   │
│           │ REST API (over unix socket or TCP)           │
│  ┌────────▼─────────┐                                   │
│  │  Docker Daemon   │  ← background process (dockerd)  │
│  │  (dockerd)       │    manages containers/images      │
│  └────────┬─────────┘                                   │
│           │ pull/push                                    │
│  ┌────────▼─────────┐                                   │
│  │  Docker Registry │  ← Docker Hub or private registry │
│  │  (hub.docker.com)│    stores images                  │
│  └──────────────────┘                                   │
└─────────────────────────────────────────────────────────┘
```

**Docker CLI (`docker`):**
The command-line client. When you type `docker run ...`, the CLI doesn't run anything
itself — it sends a REST API request to the daemon over a Unix socket at
`/var/run/docker.sock`. This is why the daemon must be running for any `docker` command
to work.

**Docker Daemon (`dockerd`):**
The background process that does the actual work: pulling images, creating containers,
managing networks and volumes. It runs as root (or via a setuid socket) because
creating namespaces and cgroups requires kernel-level privileges.

**Docker Registry:**
A server that stores and distributes Docker images. Docker Hub (`hub.docker.com`) is
the default public registry. When you run `docker pull postgres:16`, the daemon
fetches the image from Docker Hub. You can also run private registries.

**Why this matters for us:**
When the Docker daemon is not running, `docker ps` fails with "Cannot connect to the
Docker daemon at unix:///var/run/docker.sock." This is the most common beginner error.
The fix is always: start the daemon first.

---

## C4. Images vs. containers vs. volumes

These three terms are constantly confused. Here's the precise distinction:

**Docker Image:**
A read-only, layered snapshot of a filesystem. Think of it as a blueprint or template.
An image contains the OS base, runtime, libraries, and your application code, frozen
at build time. Images are immutable — you never modify one directly.

```
Image layers (read-only, stacked):
┌──────────────────────────────┐  ← Your app code (COPY . .)
├──────────────────────────────┤  ← pip install requirements
├──────────────────────────────┤  ← Python 3.11 runtime
└──────────────────────────────┘  ← Debian slim base OS
```

**Docker Container:**
A running (or stopped) instance of an image. When you `docker run postgres:16`,
Docker takes the postgres image and adds a thin writable layer on top — that's
your container. You can have 10 containers all based on the same image. Containers
are ephemeral by default: when deleted, their writable layer is gone.

```
Container = Image (read-only) + Writable layer (runtime state)
```

**Docker Volume:**
Named, persistent storage that exists independently of any container. Data written
to a volume survives container restarts and deletions. In our project:
- The Postgres data volume (`pgdata`) persists the database between `docker compose
  down` and `docker compose up`.
- The Ollama volume persists downloaded model weights so you don't re-download
  2 GB every time you restart.

**The analogy:**
- Image = a class definition in code
- Container = an instance of that class (running in memory)
- Volume = the instance's persistent fields saved to disk

---

## C5. Why we containerize this project

Our stack has unusual dependencies that would be painful to install directly:

| Service | Why a container is better |
|---|---|
| **Postgres 16 + pgvector** | pgvector is a compiled extension. Installing the right version of both Postgres and pgvector on Ubuntu without conflicts is fiddly. The `pgvector/pgvector:pg16` image has it pre-built. |
| **Ollama** | Ollama manages its own model storage, GPU detection, and API server. Running it in a container keeps it isolated and makes the GPU config explicit. |
| **App (Python 3.11)** | Ubuntu 22.04 ships Python 3.10. We want 3.11 for the app without affecting the host. The container has exactly the Python version we specify. |
| **Nginx** | We need a specific config file. Containerizing it means the config is version-controlled alongside the code. |
| **cloudflared** | The Cloudflare tunnel binary and its config live entirely in a container — no host installation needed. |

**The key benefit:** `git clone` + `docker compose up` → fully running stack, every time,
on any machine. No "it works on my machine" problems.

---

## C6. Docker Compose and the service graph

**What Docker Compose is:**
A tool for defining and running multi-container applications. Instead of running
`docker run ...` for each service with all its flags typed manually, you describe
all services in a single `docker-compose.yml` file and start everything with one
command: `docker compose up`.

**What a "service" is in Compose:**
Each entry under `services:` in the YAML file is a service. Compose creates one
container per service (by default). Services are named and can refer to each other
by name — Compose creates an internal DNS so `app` can connect to `postgres` just
by using the hostname `postgres`.

**The internal network:**
Compose automatically creates a private Docker network for your project. All services
join it. Containers on this network can talk to each other by service name. Nothing
on this network is reachable from outside unless you explicitly publish a port with
`ports:`. This is how we keep Postgres and Ollama internal — no external traffic
can reach them.

**Example of what we'll write in T-01:**
```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    # only reachable inside the Docker network — no ports: published

  ollama:
    image: ollama/ollama:latest
    # only reachable inside the Docker network

  app:
    build: .              # uses our Dockerfile
    depends_on:
      - postgres
      - ollama
    ports:
      - "8000:8000"       # FastAPI — published to host
      - "8501:8501"       # Streamlit — published to host
```

The `depends_on` key tells Compose to start `postgres` and `ollama` before `app`.
(It doesn't wait for them to be *ready*, only *started* — we'll handle readiness in T-01.)

---

# PART B — Commands

> Every shell command run during T-00, with flag-by-flag breakdowns, expected output,
> and troubleshooting guidance.

---

## 1. Environment audit commands

These commands check what is already installed on the host machine before writing
any project code. The goal is to know exactly what we have, what version, and
whether anything is missing.

---

### 1.1 Check Docker version

```bash
docker --version
```

**What it does:**
Prints the installed Docker Engine version. Docker is the containerization runtime —
it creates and runs isolated environments called containers. Every service in this
project (Postgres, Ollama, the app) runs inside its own Docker container.

**Why we run it here:**
We need Docker >= 20 for modern Compose v2 syntax and BuildKit support. We have
Docker 29.5.2, which is well above that.

**Expected output:**
```
Docker version 29.5.2, build 79eb04c
```

**If it fails (`command not found`):**
Docker is not installed. On Ubuntu 22.04:
```bash
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

---

### 1.2 Check Docker Compose version

```bash
docker compose version
```

**What it does:**
Prints the version of Docker Compose v2. Compose is the tool that lets you define
and run a multi-container application from a single `docker-compose.yml` file.
Instead of running `docker run ...` for each service separately, Compose starts them
all with one command and wires them onto a shared internal network.

**Why we run it here:**
There are two generations of Compose:
- Compose v1 (old): standalone binary called `docker-compose` (with a hyphen)
- Compose v2 (current): plugin built into Docker CLI, called `docker compose` (space)

This project uses v2 syntax. We have v2.24.6 — correct.

**Expected output:**
```
Docker Compose version v2.24.6-desktop.1
```

**If it fails (`unknown command`):**
Install the Compose plugin:
```bash
sudo apt install -y docker-compose-plugin
```

---

### 1.3 Check Python version

```bash
python3 --version
```

**What it does:**
Prints the Python 3 version installed on the host system.

**Why we run it here:**
The host Python is only needed for any scripts we might run locally outside Docker.
The actual application Python (3.11) lives inside the app container — the host
version doesn't affect the project. We just want to confirm Python is available
in case we need to run a one-off local script.

We have Python 3.10.12. This is fine.

**Expected output:**
```
Python 3.10.12
```

**Note — why we are not installing Python 3.11 on the host:**
Everything in this project runs inside Docker containers. The `Dockerfile` for the
app container will use `FROM python:3.11-slim`, which pulls a 3.11 image regardless
of what is on the host. The host Python version is irrelevant to the app.

---

### 1.4 Check Make version

```bash
make --version
```

**What it does:**
Prints the version of GNU Make. Make is a build automation tool originally designed
for compiling C programs, but it is widely used as a general-purpose task runner.
We use it to define short commands like `make up`, `make logs`, `make migrate`
instead of typing long `docker compose` commands each time.

**Why we run it here:**
The project's `Makefile` (created in T-01.7) will define all developer workflow
commands. Make needs to be present on the host.

**Expected output:**
```
GNU Make 4.3
...
```

**If it fails (`command not found`):**
```bash
sudo apt install -y build-essential
```

---

### 1.5 Check Git version

```bash
git --version
```

**What it does:**
Prints the installed Git version. Git is the version control system — it tracks
every change to every file in the project and lets you see history, roll back
mistakes, and collaborate.

**Why we run it here:**
The repo is already initialised (`git init` was already done). We just confirm Git
is available for future commits.

**Expected output:**
```
git version 2.54.0
```

---

### 1.6 Check curl

```bash
curl --version
```

**What it does:**
Prints the curl version. curl is a command-line HTTP client — it sends HTTP requests
from the terminal. We will use it throughout this project to test APIs directly:
- Test the Ollama API: `curl http://localhost:11434/api/embeddings`
- Test FastAPI endpoints before the UI is ready
- Download files (model configs, etc.)

**Expected output:**
```
curl 7.81.0 ...
```

---

### 1.7 Check disk space

```bash
df -h .
```

**What it does:**
`df` = disk free. Reports how much disk space is used and available on the filesystem
where `.` (current directory) lives.

Flags:
- `-h` = human-readable sizes (GB/MB instead of raw byte counts)
- `.` = report only the filesystem containing the current directory, not all filesystems

**Why we run it here:**
The models and Docker images we download are large:
- `llama3.2:3b` model weights: ~2.0 GB
- `nomic-embed-text` model weights: ~270 MB
- Docker images for all 5 services: ~2–3 GB total
- Postgres data volume grows as we ingest calls (~1 MB per call with embeddings)

We have 158 GB free — more than enough.

**Expected output:**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme1n1p2  228G   59G  158G  28% /
```

**Rule of thumb:** you need at least 10 GB free before starting this project.

---

### 1.8 Check OS version

```bash
lsb_release -d
```

**What it does:**
Prints the Ubuntu release description. Useful for knowing which package manager
commands and repository sources apply to your system.

`lsb_release` = Linux Standard Base release information tool.
`-d` = print only the Description field (short form of the full release info).

**Expected output:**
```
Description:    Ubuntu 22.04.5 LTS
```

Ubuntu 22.04 LTS (Jammy Jellyfish) is well-supported by all tools in this project.

---

## 2. Starting the Docker daemon

The Docker daemon (`dockerd`) is the background process that actually creates and
manages containers. The Docker CLI (`docker` command) is just a client that sends
requests to it over a Unix socket. If the daemon is not running, every `docker`
command will fail with "Cannot connect to the Docker daemon."

---

### 2.1 Start Docker via systemd

```bash
sudo systemctl start docker
```

**What it does:**
`systemctl` manages Linux system services (daemons). `start docker` tells systemd
to launch the Docker daemon service immediately.

Breaking it down:
- `sudo` — the Docker daemon requires root privileges to create kernel namespaces
  and cgroups. You need sudo to interact with system services.
- `systemctl` — the systemd service manager (the init system on Ubuntu 22.04).
  systemd is what starts all background services when your machine boots.
- `start` — start the service right now, this session only.
- `docker` — the service name registered with systemd for the Docker daemon.

**`start` vs `enable` vs `enable --now`:**
- `start` — starts the service now, but it will not auto-start on next reboot.
- `enable` — configures it to auto-start on every boot, but does not start it now.
- `enable --now` — both: starts it now AND configures auto-start. Use this if you
  want Docker to always be available without manual intervention after a reboot:
  ```bash
  sudo systemctl enable --now docker
  ```

**Expected output:**
No output means success. The daemon started silently in the background.

**If it fails:**
```
Failed to start docker.service: Unit not found.
```
This means Docker is not installed as a systemd service. Try opening Docker Desktop
from the application menu instead (it manages its own daemon).

---

### 2.2 Add yourself to the docker group (one-time setup)

```bash
sudo usermod -aG docker $USER
newgrp docker
```

**What it does:**
By default, the Docker daemon socket (`/var/run/docker.sock`) is owned by root and
the `docker` group. Without being a member of that group, every `docker` command
requires `sudo`. These two commands fix that permanently.

`sudo usermod -aG docker $USER`:
- `usermod` — modify a user account
- `-a` — append (add to the group without removing from other groups). Without `-a`,
  the `-G` flag would *replace* all your current groups with just `docker` — dangerous.
- `-G docker` — add the user to the `docker` group
- `$USER` — shell variable that expands to your current username (e.g., `aekansh`)

`newgrp docker`:
- Switches your active group to `docker` in the current shell session.
- Without this, the group change only takes effect after you log out and back in.
- This is a workaround for the current session only — a new terminal will pick up
  the group automatically.

**Why we do this:**
So you can run `docker ps`, `docker compose up`, etc. without typing `sudo` every time.
This is a one-time setup — once in the `docker` group, it persists across reboots.

**Note:** The full effect (in all new terminals) only applies after a full logout/login.
`newgrp` only applies to the current shell.

---

## 3. Verifying Docker works

After starting the daemon, two verification commands confirm everything is working.

---

### 3.1 List running containers

```bash
docker ps
```

**What it does:**
Lists all currently running containers. When the daemon is running and no containers
have been started yet, this returns an empty table with just column headers.

Useful flags (for later use):
- `docker ps -a` — shows ALL containers, including stopped ones
- `docker ps --filter "name=postgres"` — filter by container name
- `docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"` — custom columns

**Expected output (daemon running, no containers yet):**
```
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
```

**If it fails:**
```
Cannot connect to the Docker daemon at unix:///var/run/docker.sock.
Is the docker daemon running?
```
The daemon is not running. Go back to step 2.1.

---

### 3.2 Run the hello-world container

```bash
docker run --rm hello-world
```

**What it does:**
Downloads (if not already cached) and runs the official `hello-world` Docker image —
the simplest possible container. It prints a confirmation message and immediately exits.

Breaking it down:
- `docker run` — create a new container from an image and start it
- `--rm` — automatically delete the container after it exits. Without this flag,
  stopped containers accumulate silently and waste disk space. Always use `--rm`
  for one-shot test containers.
- `hello-world` — the image name. Docker looks for it locally first; if not found,
  pulls it from Docker Hub (the default public image registry at hub.docker.com).

**What happens internally:**
1. Docker CLI sends a `POST /containers/create` request to the daemon.
2. The daemon checks the local image cache — `hello-world` not found.
3. Daemon pulls the image from Docker Hub (a few KB — it's tiny).
4. Daemon creates a container from the image, starts it.
5. Container process runs, prints its message, exits with code 0.
6. Because of `--rm`, the daemon deletes the container immediately.

**Why we run it:**
This is the standard smoke test for Docker. It exercises:
1. The daemon is running and responding to CLI requests ✓
2. The daemon can reach the internet and pull from Docker Hub ✓
3. The daemon can create, start, and delete containers ✓

**Expected output:**
```
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
...
Hello from Docker!
This message shows that your installation appears to be working correctly.
...
```

**If it fails with a network error:**
Your machine cannot reach Docker Hub (hub.docker.com). Check your internet connection.
If you're behind a corporate proxy, Docker needs proxy configuration — ask your
network admin for the proxy address and set it in `/etc/systemd/system/docker.service.d/`.

---

## Summary — T-00 status

| Check | Result |
|---|---|
| Docker 29.5.2 installed | ✅ |
| Docker Compose v2.24.6 installed | ✅ |
| Python 3.10.12 on host | ✅ (host version — app uses 3.11 in container) |
| Make 4.3 installed | ✅ |
| Git 2.54.0 installed | ✅ |
| curl installed | ✅ |
| VS Code 1.122.1 installed | ✅ |
| 158 GB free disk space | ✅ |
| Docker daemon running | ⬜ Run: `sudo systemctl start docker` |
| `hello-world` test passes | ⬜ Run after daemon starts |
| HuggingFace account created | ⬜ Needed before T-03 — not urgent yet |

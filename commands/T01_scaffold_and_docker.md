# T-01 — Project Scaffold & Docker Environment
# Command & Concept Reference

> This file logs every concept taught and every shell command used during T-01.
> Purpose: a detailed reference you can return to at any point — not a summary.
> Structure: concepts first (the "why" and "how it works"), commands second (the "what to run").

---

## Table of Contents

### Concepts
- [C1. Separation of concerns — why we structure code into folders](#c1-separation-of-concerns--why-we-structure-code-into-folders)
- [C2. Python packages and `__init__.py`](#c2-python-packages-and-__init__py)
- [C3. Environment variables and the 12-factor app](#c3-environment-variables-and-the-12-factor-app)
- [C4. The Dockerfile — building a custom image](#c4-the-dockerfile--building-a-custom-image)
- [C5. Docker Compose — wiring services together](#c5-docker-compose--wiring-services-together)
- [C6. Docker internal networks and why services stay private](#c6-docker-internal-networks-and-why-services-stay-private)
- [C7. The Makefile as a developer task runner](#c7-the-makefile-as-a-developer-task-runner)

### Commands
- [1. Creating the directory skeleton](#1-creating-the-directory-skeleton)
- [2. .env and .env.example setup](#2-env-and-envexample-setup)
- [3. Building the app container](#3-building-the-app-container)
- [4. Docker Compose — bring services up and down](#4-docker-compose--bring-services-up-and-down)
- [5. Verification commands](#5-verification-commands)
- [6. Makefile targets](#6-makefile-targets)

---

# PART A — Concepts

---

## C1. Separation of concerns — why we structure code into folders

**What it is:**
Separation of concerns is a design principle where you divide a program into distinct
sections, each responsible for one specific thing. In a project like ours, "concerns"
are the different *types of work* the system does: ingestion, retrieval, API serving,
UI, database, infrastructure.

**How it applies to this project:**

```
sales_call_rag/
│
├── app/           ← shared utilities: DB connection pool, config loader
├── ingestion/     ← write pipeline: audio → transcript → chunks → DB
├── rag/           ← read pipeline: question → retrieve → LLM → answer
├── api/           ← HTTP layer: FastAPI routes, request/response models
├── ui/            ← frontend: Streamlit pages
├── sql/           ← database schema: SQL migration files, versioned
│   └── migrations/
├── docker/        ← infrastructure config: Nginx, Postgres init scripts
├── tests/         ← pytest test suite
│
├── Dockerfile          ← how to build the app container image
├── docker-compose.yml  ← wires all 5 services together
├── .env                ← all secrets and config — never committed to git
├── .env.example        ← template of .env keys — committed, no values
├── requirements.txt    ← Python dependencies for the app container
└── Makefile            ← developer task runner
```

**Why `ingestion/` and `rag/` are separate:**
They are entirely different pipelines with different purposes:
- Ingestion is a *write* pipeline — runs once per audio file, offline, can be slow.
- RAG is a *read* pipeline — runs on every user query, must be fast, user-facing.
They share the database but nothing else. Separating them means you can modify,
test, and debug one without touching the other.

**Why `sql/` is separate:**
SQL migration files are version control for the database schema. Numbered files
(`001_init.sql`, `002_pgvector.sql`) apply in order and build the schema step by step.
If you ever reset the database or set up a new machine, you run the migrations in
order and get an identical schema every time. Keeping them in their own folder makes
them easy to find and impossible to accidentally mix with application code.

**Why `docker/` is separate:**
Files like `nginx.conf` and the Postgres init script are infrastructure configuration,
not application logic. They don't contain Python and they're not imported by any module.
Separating them makes the boundary between "app code" and "infrastructure config" clear.

**Tradeoffs:**
More directories means more places to look when you're unfamiliar with the project.
The payoff is that once you know the structure, you always know *exactly* where to look
for any given type of code. This scales well as the project grows.

**Alternative:**
A flat structure (everything in one folder) works for toy scripts but becomes painful
at 20+ files. A monorepo with one package per service (each with its own
`pyproject.toml`) is the enterprise approach but is overkill for a learning project.
Our structure is the practical middle ground.

---

## C2. Python packages and `__init__.py`

**What it is:**
In Python, a **module** is a single `.py` file. A **package** is a directory containing
Python modules. For Python to treat a directory as a package (i.e., allow
`from ingestion.chunk import split_into_chunks`), the directory must contain a file
named `__init__.py`.

**How it actually works:**
When Python sees `from ingestion.chunk import split_into_chunks`, it:
1. Looks for a directory named `ingestion` in the Python path.
2. Checks for `ingestion/__init__.py` — if it doesn't exist, Python refuses to treat
   the directory as a package (in Python 3.3+ there are "namespace packages" that work
   without it, but explicit `__init__.py` is still the standard for application code).
3. Loads `ingestion/chunk.py` and finds `split_into_chunks`.

**What goes in `__init__.py`:**
It can be empty — and ours will be. An empty `__init__.py` simply signals "this
directory is a Python package." You can optionally put imports in it to create a
cleaner public API for the package, but we won't do that here to keep things explicit.

**Why we create them now:**
We create empty `__init__.py` files in `app/`, `ingestion/`, `rag/`, `api/`, and `ui/`
now so that the import system works correctly from the first line of code we write.
If we forget one, we'll get a confusing `ModuleNotFoundError` later.

**Tradeoffs:**
None in practice for a project this size. Some modern Python projects use implicit
namespace packages and skip `__init__.py`, but explicit is clearer for learning.

---

## C3. Environment variables and the 12-factor app

**What it is:**
An environment variable is a key-value pair stored in the operating system's environment,
accessible to any process that runs in it. Examples:
- `DATABASE_URL=postgresql://user:pass@localhost:5432/sales`
- `OLLAMA_BASE_URL=http://ollama:11434`

In Docker Compose, environment variables are the primary way to pass configuration
into containers.

**The problem they solve:**
Hard-coding config values (database passwords, model names, ports) inside source files
is dangerous and inflexible:
- If you commit a password to git, it's in the history forever — even after you delete it.
- If you want to change the database URL (e.g., moving from dev to prod), you have to
  edit source code instead of just changing a config value.
- Different developers may need different local settings.

**The 12-factor app principle:**
The [12-Factor App](https://12factor.net) is a methodology for building software-as-a-service
apps. Factor III (Config) states: **store config in the environment, not in the code**.
Config is anything that varies between deployments (dev / staging / prod): database URLs,
credentials, hostnames, feature flags.

**How we implement it in this project:**

```
.env                ← actual values (never committed to git)
.env.example        ← template showing which keys exist, with fake values (committed)
```

`.env` is loaded by Docker Compose automatically — all key=value pairs in it become
environment variables inside every container. Python reads them with `os.getenv()` or
the `python-dotenv` library.

`.env.example` is the documentation. A new developer clones the repo, copies
`.env.example` to `.env`, fills in real values, and is ready to run.

**Why `.env` must never be committed:**
Once a secret is in git history, it is effectively public — even if you delete the file,
the secret exists in every `git clone` ever made. The `.gitignore` file must list `.env`.

**Tradeoffs:**
Environment variables are strings only — no nested structure, no types. For complex config
you might use a config file (YAML/TOML) or a secrets manager (Vault, AWS Secrets Manager).
For a local learning project, `.env` is the right tradeoff: simple, widely understood,
zero infrastructure.

---

## C4. The Dockerfile — building a custom image

**What it is:**
A `Dockerfile` is a text file containing a sequence of instructions that Docker uses to
build a container image. Each instruction adds a layer to the image. The result is a
reproducible, self-contained image that can run on any machine with Docker.

**How it actually works — layers:**
Docker builds images in layers. Each instruction (`FROM`, `RUN`, `COPY`, etc.) creates
one layer. Layers are cached — if a layer hasn't changed since the last build, Docker
reuses the cached version and skips re-running that step. This is why instruction order
matters: put things that change frequently (your app code) at the bottom, and things
that change rarely (OS packages, pip install) near the top.

**Our Dockerfile (written in T-01.3):**
```dockerfile
FROM python:3.11-slim          # base image: Debian slim with Python 3.11

WORKDIR /app                   # all subsequent commands run from /app inside container

COPY requirements.txt .        # copy requirements first (changes rarely)
RUN pip install --no-cache-dir -r requirements.txt   # install dependencies (cached)

COPY . .                       # copy app code (changes often — near bottom)

EXPOSE 8000 8501               # document which ports the container listens on
```

**Why `python:3.11-slim` and not `python:3.11`:**
`python:3.11` is based on Debian full (~900 MB). `python:3.11-slim` strips build tools
and documentation (~130 MB). We don't need a compiler inside the running container —
we compile Python packages during `pip install`, then the `.so` files are enough.

**Why `COPY requirements.txt .` before `COPY . .`:**
Layer caching. `requirements.txt` changes only when you add/remove packages. Your app
code changes every time you edit a file. By copying `requirements.txt` and running
`pip install` before copying the app code, Docker caches the expensive pip install step
and only re-runs it when requirements actually change. If you did `COPY . .` first,
every code change would invalidate the cache and re-run all pip installs — very slow.

---

## C5. Docker Compose — wiring services together

**What it is:**
Docker Compose reads a `docker-compose.yml` file and manages the full lifecycle of a
multi-container application: pulling images, building custom images, creating networks,
starting containers in the right order, and linking them together.

**Key sections of our `docker-compose.yml`:**

```yaml
services:
  postgres:             # service name — also its hostname on the Docker network
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_DB: sales_rag
      POSTGRES_USER: raguser
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}  # reads from .env
    volumes:
      - pgdata:/var/lib/postgresql/data         # persist DB across restarts
    restart: unless-stopped

  ollama:
    image: ollama/ollama:latest
    volumes:
      - ollama_data:/root/.ollama               # persist downloaded models
    restart: unless-stopped

  app:
    build: .                                    # build from our Dockerfile
    depends_on:
      - postgres
      - ollama
    env_file: .env                             # inject all .env vars into container
    ports:
      - "8000:8000"                            # FastAPI — host:container
      - "8501:8501"                            # Streamlit
    restart: unless-stopped

volumes:
  pgdata:       # named volume — survives docker compose down
  ollama_data:
```

**`depends_on` — what it does and doesn't do:**
`depends_on: [postgres, ollama]` tells Compose to *start* postgres and ollama before
starting app. It does NOT wait for them to be *ready* (accepting connections). Postgres
takes a few seconds to initialise on first boot. We handle this in `db.py` with a retry
loop — try to connect, if it fails wait 1 second and retry, up to 10 times.

**`restart: unless-stopped`:**
If a container crashes, Docker automatically restarts it — unless you explicitly stopped
it with `docker compose stop`. This gives us basic resilience without Kubernetes.

**Named volumes vs bind mounts:**
- Named volume (`pgdata:/var/lib/postgresql/data`): Docker manages the storage location.
  Data persists across `docker compose down` and restarts. Best for databases.
- Bind mount (`./app:/app`): maps a host directory into the container. Changes on the
  host instantly appear in the container — useful for development hot-reload. We'll use
  this for the app service in dev mode so we don't have to rebuild the image on every
  code change.

---

## C6. Docker internal networks and why services stay private

**What it is:**
When Docker Compose starts, it automatically creates a private bridge network for your
project. Every service joins this network. Containers on this network can reach each
other by service name — Compose sets up internal DNS so `app` can connect to `postgres`
just by using the hostname `postgres` (not an IP address, which can change).

**What's exposed vs. what's private:**

```
Internet / your browser
        │
        │  only ports explicitly published with "ports:" are reachable
        ▼
  Host machine  ─────────────────────────────────────────────────────
        │          8000 (FastAPI)    8501 (Streamlit)
        │                │                  │
  ──────┼──────────────────────────────────────────────── Docker network
        │          ┌─────┴────┐    ┌─────────┴──────┐
        │          │   app    │    │   app (same)   │
        │          └─────┬────┘    └────────────────┘
        │                │ internal only
        │          ┌─────┴──────┐    ┌─────────────┐
        │          │  postgres  │    │   ollama    │
        │          └────────────┘    └─────────────┘
  ──────┼─────────────────────────────────────────────────────────────
```

Postgres and Ollama have no `ports:` entries — they are only reachable from inside the
Docker network. An attacker on the internet cannot reach your database directly. The app
container is the only thing that talks to them.

**Why this matters:**
Never publish Postgres to the host (`5432:5432`) in a production or internet-facing setup.
If you do, anyone who can reach your machine can attempt to connect to your database.
The Docker internal network is the firewall.

---

## C7. The Makefile as a developer task runner

**What it is:**
A `Makefile` defines named targets — short command aliases. Instead of typing
`docker compose -f docker-compose.yml up --build -d` every time, you type `make up`.

**How it works:**
```makefile
# Target name followed by a colon
up:
	docker compose up --build -d    # ← must be indented with a TAB, not spaces

down:
	docker compose down

logs:
	docker compose logs -f
```

Running `make up` executes the commands under the `up:` target.

**Critical syntax rule — tabs, not spaces:**
Makefile recipe lines MUST be indented with a real TAB character (`\t`), not spaces.
This is a decades-old requirement of Make syntax. If you use spaces, Make will error:
`Makefile:2: *** missing separator. Stop.`
Most editors show tabs and spaces identically — be careful.

**Why we use Make instead of shell scripts:**
- Self-documenting: `make help` can list all targets.
- Standard: every developer knows how to run `make <target>`.
- Dependency tracking: a target can depend on other targets (`migrate: up`).
- No interpreter needed: Make is available on every Linux/Mac system.

**Alternative:** some projects use `just` (a modern Make alternative with better syntax)
or `npm run` scripts. Make is the most universally available option.

---

# PART B — Commands

---

## 1. Creating the directory skeleton

### 1.1 Create all directories at once

```bash
mkdir -p ingestion rag api ui sql/migrations docker tests app
```

**What it does:**
Creates all project directories in one command.

- `mkdir` — make directory
- `-p` — "parents": create any missing parent directories in the path, and don't
  error if the directory already exists. Without `-p`, `mkdir sql/migrations` would
  fail if `sql/` doesn't exist yet. With `-p`, it creates `sql/` then `sql/migrations/`
  in one step.
- The remaining arguments are a space-separated list of directories to create.
  All are created relative to the current working directory (the repo root).

**Why we run it here:**
We create all directories upfront, even for tasks we haven't started yet (like `tests/`
for T-07), because:
1. The Dockerfile and docker-compose.yml will reference these paths.
2. Python imports assume the package directories exist.
3. It's easier to reason about the structure when the full skeleton is visible.

**Expected output:**
No output — silence means success in Unix.

**If it fails:**
```
mkdir: cannot create directory 'sql/migrations': Permission denied
```
You're not in the right directory, or the parent directory is owned by root.
Run `pwd` to confirm you're in the project root, then `ls -la` to check permissions.

---

### 1.2 Create Python package markers and empty config files

```bash
touch app/__init__.py ingestion/__init__.py rag/__init__.py api/__init__.py ui/__init__.py
touch Dockerfile docker-compose.yml requirements.txt Makefile .env.example
```

**What it does:**
`touch` creates an empty file if it doesn't exist, or updates its "last modified"
timestamp if it does exist. We use it here purely to create empty placeholder files.

- `app/__init__.py` etc. — marks each directory as a Python package (see Concept C2).
- `Dockerfile` — will contain the image build instructions (T-01.3).
- `docker-compose.yml` — will define all services (T-01.4).
- `requirements.txt` — will list all Python dependencies (T-01.3).
- `Makefile` — will define developer task shortcuts (T-01.7).
- `.env.example` — template of config keys (T-01.2). Note: `.env` itself is NOT
  created with touch — we'll write it with real content in T-01.2.

**Why we create these now as empty files:**
Editors and tools (like VS Code's file tree) work better when the files exist, even
empty. It also documents intent: seeing `Dockerfile` in the root immediately tells
anyone cloning the repo "this project is containerized."

**Expected output:**
No output — silence means success.

---

### 1.3 Verify the structure

```bash
find . -not -path '*/.git/*' | sort
```

**What it does:**
- `find .` — recursively lists every file and directory under `.` (current directory).
- `-not -path '*/.git/*'` — excludes the `.git/` directory (which contains hundreds
  of internal Git files that would clutter the output).
- `| sort` — pipes the output through `sort` to display entries alphabetically,
  making the structure easier to read.

**Why we run it here:**
To visually confirm that every directory and placeholder file was created exactly
as intended before we start writing content into them. A typo in a directory name
now would cause confusing import errors in T-03 or T-04.

**Expected output:**
```
.
./api
./api/__init__.py
./app
./app/__init__.py
./commands
./docker
./docker-compose.yml
./Dockerfile
./.env.example
./ingestion
./ingestion/__init__.py
./LEARNING_PLAN.md
./Makefile
./rag
./rag/__init__.py
./requirements.txt
./sql
./sql/migrations
./tests
./ui
./ui/__init__.py
```

---

## 2. .env and .env.example setup

### 2.1 Create .env from the example template

```bash
cp .env.example .env
```

**What it does:**
`cp` (copy) duplicates `.env.example` into a new file called `.env`.

- Source: `.env.example` — the committed template with placeholder values
- Destination: `.env` — your local config with real values, never committed

**Why we do it this way:**
Every developer on a project has their own `.env` with values appropriate for their
machine. By copying from `.env.example`, you get the correct set of variable names
automatically — you only need to fill in the real values. If a new variable is added
to the project later, the developer just looks at `.env.example` to see what's new.

**Expected output:** No output — silence means success.

---

### 2.2 Edit the password in .env

```bash
sed -i 's/changeme/ragpass123/' .env
```

**What it does:**
`sed` is a stream editor — it processes text line by line and applies transformations.

- `-i` — "in-place": edit the file directly (without `-i`, sed prints to stdout
  and the file is unchanged)
- `'s/changeme/ragpass123/'` — the substitution command: replace the first occurrence
  of `changeme` with `ragpass123` on each line
  - `s` = substitute
  - `/changeme/` = pattern to find
  - `/ragpass123/` = replacement text
  - (a trailing `g` flag like `s/.../...g` would replace ALL occurrences per line —
    we omit it because each variable appears once)

**Why we run it here:**
`.env.example` uses `changeme` as a placeholder password. The actual `.env` needs a
real (non-default) value — even for local dev it's good practice to not use the
literal word "changeme" as your password.

For a real production deployment you'd use a strong random password here:
```bash
openssl rand -base64 32   # generates a cryptographically random 32-byte password
```

**Expected output:** No output — silence means success.

---

### 2.3 Verify .env is protected by .gitignore

```bash
git check-ignore -v .env
```

**What it does:**
Asks git: "is this file ignored, and which `.gitignore` rule caused it?"

- `check-ignore` — the git subcommand that checks ignore rules
- `-v` — verbose: print which rule matched and which file contains that rule
- `.env` — the file to check

**Why we run it here:**
Before doing anything else, we verify that git will never accidentally stage `.env`.
This is a hard rule — a committed secret is a compromised secret, permanently, because
git history is forever. This command gives us proof that the ignore rule is working.

**Expected output:**
```
.gitignore:2:.env	.env
```
Reading this: `.gitignore` file, line 2, pattern `.env`, matches the file `.env`.
If you see this output, the file is safely ignored.

**If it returns nothing:**
`.env` is NOT ignored. Open `.gitignore` and add `.env` on its own line.

---

### 2.4 Verify the content of .env

```bash
cat .env
```

**What it does:**
`cat` (concatenate) prints the contents of a file to the terminal. Here we use it
simply to read and visually inspect `.env`.

**Why we run it here:**
Confirm that the `sed` substitution worked correctly — `POSTGRES_PASSWORD` and
`DATABASE_URL` should both show `ragpass123`, not `changeme`.

**Security note:** Only run `cat .env` in your own terminal on your own machine.
Never paste the output into a chat, a GitHub issue, or a shared document.

---

### 2.5 Understanding the DATABASE_URL format

The `DATABASE_URL` variable uses a standard URI format understood by psycopg2,
SQLAlchemy, LangChain, and most Python database libraries:

```
postgresql://raguser:ragpass123@postgres:5432/sales_rag
│            │        │          │        │    │
│            │        │          │        │    └── database name
│            │        │          │        └─────── port (Postgres default)
│            │        │          └──────────────── hostname = Docker service name
│            │        └─────────────────────────── password
│            └──────────────────────────────────── username
└───────────────────────────────────────────────── driver/protocol
```

**Why the host is `postgres` not `localhost`:**
Inside the Docker network, each service is reachable by its service name. From inside
the `app` container, `localhost` refers to the app container itself. To reach the
Postgres container, you use its service name: `postgres`. Docker's internal DNS
resolves `postgres` → the IP address of the Postgres container automatically.

---

## 3. Building the app container

### 3.1 Build the image

```bash
docker build -t sales-rag-app .
```

**What it does:**
`docker build` reads the `Dockerfile` in the current directory and produces an image.

- `-t sales-rag-app` — tag (name) the resulting image `sales-rag-app`.
  Without `-t` Docker assigns a random hex ID — hard to reference later.
- `.` — the **build context**: the directory Docker sends to the Docker daemon.
  Every `COPY` instruction in the Dockerfile copies from this context, not from
  your filesystem directly. Keeping the context small (via `.dockerignore`) speeds
  up builds because Docker has to transfer the context over a socket.

**Why we run it here:**
To verify the Dockerfile is syntactically correct and all packages install successfully
before writing docker-compose.yml.

**Expected output (first build, no cache):**
```
[1/5] FROM docker.io/library/python:3.11-slim
[2/5] RUN apt-get update && apt-get install -y ...
[3/5] COPY requirements.txt .
[4/5] RUN pip install --no-cache-dir -r requirements.txt
[5/5] COPY . .
Successfully built <image-id>
Successfully tagged sales-rag-app:latest
```
Takes ~2-4 minutes on first build (downloading base image + pip installs).
Subsequent builds with only code changes take ~5 seconds (layers 1-4 are cached).

**If it fails with "package not found":**
A package name in requirements.txt is wrong. `pip` error messages name the bad package.

**If it fails with "apt-get: command not found":**
The base image changed. Check `FROM python:3.11-slim` is typed exactly.

---

### 3.2 Verify the image was built

```bash
docker images sales-rag-app
```

**Expected output:**
```
REPOSITORY      TAG       IMAGE ID       CREATED         SIZE
sales-rag-app   latest    abc123def456   2 minutes ago   ~600MB
```

---

### 3.3 Test that imports work inside the container

```bash
docker run --rm sales-rag-app python -c "
import langchain; print('langchain OK')
import fastapi; print('fastapi OK')
import streamlit; print('streamlit OK')
import psycopg2; print('psycopg2 OK')
import pgvector; print('pgvector OK')
import vaderSentiment; print('vaderSentiment OK')
"
```

**What it does:**
- `docker run --rm` — start a container and delete it immediately when it exits.
  `--rm` keeps your system clean; without it the stopped container stays in
  `docker ps -a` until you manually remove it.
- `sales-rag-app` — the image to run (built in 3.1).
- `python -c "..."` — runs a Python one-liner instead of the default CMD.

**Why we run it here:**
Verifies that `pip install` inside the container installed every package correctly
and that Python can import them. A successful import means no missing C dependencies,
no version conflicts, and no typos in package names.

**Expected output:**
```
langchain OK
fastapi OK
streamlit OK
psycopg2 OK
pgvector OK
vaderSentiment OK
```

**If an import fails:**
```
ModuleNotFoundError: No module named 'langchain'
```
The package didn't install. Check the package name in `requirements.txt` and rebuild.

---

## 4. Docker Compose — bring services up and down

*(Commands added when T-01.4 is complete)*

---

## 5. Verification commands

*(Commands added when T-01 verification is complete)*

---

## 6. Makefile targets

*(Commands added when T-01.7 is complete)*

---

## Summary — T-01 status

| Sub-step | Description | Status |
|---|---|---|
| T-01.1 | Directory skeleton created | ✅ |
| T-01.2 | `.env` + `.env.example` | ✅ |
| T-01.3 | Dockerfile + requirements.txt | ✅ |
| T-01.4 | docker-compose.yml (3 services) | ⬜ |
| T-01.5 | Postgres pgvector init script | ⬜ |
| T-01.6 | Ollama model pull | ⬜ |
| T-01.7 | Makefile targets | ⬜ |

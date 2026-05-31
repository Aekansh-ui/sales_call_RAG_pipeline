# Sales Call RAG Pipeline — Learning Program & Plan

> A paced, task-by-task learning program for building the Sales Call RAG pipeline
> described in `Sales_Call_RAG_Pipeline_PRD_v3.docx`. The goal is **understanding
> each component**, not shipping fast. We build it together, in small steps.

---

## 📍 CHECKPOINT — read this first, every session

> **This block is the resume point. At the start of every session I read it.
> At the end of every session I update it.** Keep it short and current.

| Field | Value |
|---|---|
| **Current task** | T-01 — Project Scaffold & Docker |
| **Current sub-step** | T-01.4 — docker-compose.yml (not started) |
| **Status** | 🟡 In progress — 3 of 7 sub-steps done |
| **Last session** | 2026-05-31 — T-01.3 completed: requirements.txt and Dockerfile written, image built successfully, pip installs verified. |
| **Next action** | Begin T-01.4: write docker-compose.yml with 3 services (postgres+pgvector, ollama, app). Teach service graph, depends_on, named volumes, internal DNS. |
| **Blockers / open questions** | None. Docker is running. |

**Overall progress:** 🟢🟡⬜⬜⬜⬜⬜⬜⬜ T-00 done · T-01 in progress (2/7) · T-02 through T-08 not started

---

## How this learning program works

**Teaching style (your choice): "We pair, step by step."**
For each sub-step I will:
1. **Teach the concept first** — explain what we're about to build and *why*, with the deep fundamentals (theory, tradeoffs, alternatives).
2. **Write code in small increments** — one focused piece at a time, explaining each before moving on.
3. **Pause** — so you can ask questions, tweak, or push back before we continue.
4. **Verify** — run it, confirm the PRD's "Done When" criteria, then tick the box.

**Depth (your choice): "Deep fundamentals."**
We don't just wire things up — for each component I'll explain how it actually works
(e.g. how embeddings and ANN/IVFFlat search work, how diarization clusters speakers,
how RAG grounding/prompting works), the tradeoffs, and what the alternatives are.

**Pace:** ~8 tasks, PRD-estimated 17–25 days of part-time work. One task at a time;
finish (and verify) a task before starting the next.

### The checkpoint protocol (how I resume across sessions)
- **Source of truth:** this file, committed to git.
- **At session start:** I read the `📍 CHECKPOINT` block above to know exactly where we are.
- **At session end (or after each sub-step):** I (a) tick completed `[ ]` boxes, (b) update
  the CHECKPOINT table, (c) add any decisions to the **Decisions Log**, (d) flush any new
  commands to the task's command reference file in `commands/`.
- **Memory backup:** a `project`-type memory points future sessions here, so even a cold
  start routes me back to this plan.
- **Status legend:** 🟢 done · 🟡 in progress / ready · 🔴 blocked · ⬜ not started.

### Command & concept reference files (one per task)
Every concept taught and every shell command we run together is recorded in
`commands/T<nn>_<title>.md`. These are **detailed reference files, not summaries** —
everything you need to understand what was covered and why, without referring back
to the conversation.

**Structure of each file:**

**Part A — Concepts** (one section per concept introduced in the task):
1. **What it is** — plain-language definition
2. **How it actually works** — internals, mechanisms, analogies
3. **Why we use it in this project** — the specific problem it solves here
4. **Tradeoffs** — what this approach gives up
5. **Alternatives considered** — what else we could have used and why we didn't

**Part B — Commands** (one section per command or group of commands):
1. **The command** (code block, copy-paste ready)
2. **What it does** — flag-by-flag breakdown
3. **Why we run it here** — its purpose in this project at this step
4. **Expected output** — what you should see when it works
5. **If it fails** — common errors and what they mean

Files live in `commands/` at the repo root. One file per task, written as we go.
A `_TEMPLATE.md` exists for consistency.

---

## Project at a glance (from the PRD)

A fully-offline, containerized RAG pipeline to query transcribed sales calls in natural
language. Everything runs locally (no cloud AI APIs), optionally exposed to the internet
via Cloudflare Tunnel in the final task.

**Stack:** faster-whisper (STT) · pyannote.audio (diarization) · nomic-embed-text +
llama3.2 via Ollama · PostgreSQL 16 + pgvector · LangChain · FastAPI · Streamlit ·
Nginx · Cloudflare Tunnel/Access · VADER sentiment · pytest · Docker Compose.

**Ingestion flow:** audio → transcribe → diarise → chunk → sentiment → embed → topics → DB.
**Query flow:** question → embed → pgvector search → LLM with cited context → answer + sources.

---

## Task Roadmap

| Task | Title | Focus | Depends on | Status |
|---|---|---|---|---|
| T-00 | Prerequisites & Environment | Host setup | — | 🟡 |
| T-01 | Project Scaffold & Docker | DevOps / Containers | T-00 | ⬜ |
| T-02 | DB Schema & Migrations | Database / pgvector | T-01 | ⬜ |
| T-03 | Audio Transcription Pipeline | STT / NLP | T-02 | ⬜ |
| T-04 | Embedding Pipeline & Vector Search | Embeddings / pgvector | T-03 | ⬜ |
| T-05 | RAG Query Engine & Sentiment | LLM / RAG | T-04 | ⬜ |
| T-06 | FastAPI Backend & Streamlit UI | API / Frontend | T-05 | ⬜ |
| T-07 | Testing, Tuning & Docs | Quality / Learning | T-06 | ⬜ |
| T-08 | Internet Exposure via Cloudflare | Networking / Security | T-07 | ⬜ |

---

## T-00 — Prerequisites & Environment Setup  ·  Status: 🟡

**Goal:** verify every host tool is installed and working before a single line of project code is written.

**Audited 2026-05-30 — Ubuntu 22.04 LTS:**

| Tool | Required | Status | Notes |
|---|---|---|---|
| Docker 29.5.2 | ✅ | Installed | Daemon not running — see action below |
| Docker Compose v2 | ✅ | Installed | Correct version (`docker compose`, not `docker-compose`) |
| Python 3.10 (host) | Optional | ✅ | Host Python; app container uses 3.11 via Dockerfile |
| Python 3.11 (host) | Not needed | — | Lives inside the container only |
| pip3 (host) | Not needed | — | All packages install inside containers |
| Make | ✅ | Installed | Used for Makefile task runner |
| Git | ✅ | Installed | |
| curl | ✅ | Installed | |
| VS Code | ✅ | Installed | |
| Disk space | 3 GB min | ✅ 158 GB free | Models: llama3.2:3b ~2 GB, nomic-embed ~270 MB |
| HuggingFace account | Needed in T-03 | ⬜ | Create free account + accept pyannote model terms before T-03 |

**One remaining action — start the Docker daemon:**

Docker Desktop on Linux needs to be started manually if it isn't set to auto-launch. Run:
```bash
# Option A: start Docker Desktop app from your application menu
# Option B: start the system daemon directly
sudo systemctl start docker

# Verify it works:
docker ps
docker run --rm hello-world
```

- [ ] T-00.1 — Docker daemon running (`docker ps` returns without error).
- [ ] T-00.2 — `docker run --rm hello-world` completes successfully.
- [x] T-00.3 — All other tools confirmed present (Docker, Compose, Make, Git, curl, VS Code, disk space).

**Future prerequisite (do before T-03):**
- [ ] T-00.4 — Create a free [HuggingFace](https://huggingface.co) account and accept the pyannote.audio model usage terms (needed for speaker diarization). I'll remind you again at T-03.

---

## T-01 — Project Scaffold & Docker Environment  ⏱ 1–2 days  ·  Status: ⬜

**Goal:** project skeleton + Docker Compose, all services start cleanly.

**Concepts I'll teach (deep):** containers vs. VMs and why we containerize; Docker images
vs. containers vs. volumes; Docker Compose service graph & internal networks; why Postgres
+ Ollama run as separate services; env-based config & the 12-factor idea; Makefile as a
task runner.

**Sub-steps:**
- [x] T-01.1 — Directory structure: `/app`, `/ingestion`, `/rag`, `/ui`, `/sql`, `/docker`.
- [x] T-01.2 — `.env` for all config (DB URL, model names, ports, secrets).
- [x] T-01.3 — Python 3.11 app container + `requirements.txt` (langchain, psycopg2, fastapi, streamlit, …).
- [ ] T-01.4 — `docker-compose.yml`: 3 services — postgres (+pgvector), ollama, app; `restart: unless-stopped`.
- [ ] T-01.5 — Postgres init script enables pgvector on first boot.
- [ ] T-01.6 — Ollama with `llama3.2:3b` + `nomic-embed-text` pre-pulled.
- [ ] T-01.7 — `Makefile`: `up`, `down`, `pull-models`, `migrate`, `shell`, `logs`.

**Done when:** `docker compose ps` healthy · pgvector extension present · `ollama list`
shows both models · app container can import langchain/psycopg2 and call Ollama.

---

## T-02 — Database Schema & Migrations  ⏱ 1–2 days  ·  Status: ⬜

**Goal:** full Postgres schema for metadata + vector embeddings.

**Concepts I'll teach (deep):** relational schema design & normalization; UUID vs serial
PKs; foreign keys & referential integrity; what a vector column *is*; pgvector internals;
ANN vs exact search; IVFFlat (lists/probes, recall vs speed); migrations as version control
for the DB; connection pooling.

**Sub-steps:**
- [ ] T-02.1 — `calls` table (id UUID PK, file_name, call_date, salesperson, customer, duration_sec, raw_transcript, created_at).
- [ ] T-02.2 — `chunks` table (id, call_id FK, chunk_index, speaker_role, text, start_sec, end_sec, sentiment).
- [ ] T-02.3 — `chunk_embeddings` table (chunk_id FK, embedding vector(768)).
- [ ] T-02.4 — `call_topics` (id, call_id FK, topic, confidence) + `call_sentiment` (call_id FK, overall, score).
- [ ] T-02.5 — Migration files `/sql/migrations/001_init.sql`, `002_pgvector.sql`.
- [ ] T-02.6 — `db.py`: connection pool, `run_migration()`, `health_check()`.
- [ ] T-02.7 — IVFFlat index on `chunk_embeddings.embedding`.

**Done when:** `\dt` shows all 5 tables · `\d chunk_embeddings` shows `vector(768)` ·
INSERT+SELECT works on each table · `EXPLAIN` on a vector query shows IVFFlat index scan.

---

## T-03 — Audio Transcription Pipeline  ⏱ 3–4 days  ·  Status: ⬜

**Goal:** ingest an audio file → speaker-labelled transcript stored in Postgres.

**Concepts I'll teach (deep):** how ASR/Whisper works (mel spectrograms, encoder-decoder,
why faster-whisper is faster); speaker diarization (embeddings + clustering) vs simple
energy heuristics; tokenization & why we chunk; chunk size vs overlap tradeoffs for
retrieval; idempotency in pipelines.

**Sub-steps:**
- [ ] T-03.1 — faster-whisper in app container (CPU, large-v3).
- [ ] T-03.2 — Diarization: pyannote.audio OR energy-based 2-speaker heuristic.
- [ ] T-03.3 — Parser: Whisper JSON → `[{speaker, text, start, end}]`.
- [ ] T-03.4 — Chunker: ~400-token chunks, 80-token overlap, preserve speaker metadata.
- [ ] T-03.5 — `ingest.py` CLI (`--file --salesperson --customer`), writes calls + chunks.
- [ ] T-03.6 — Progress bar (rich) + error handling for corrupt/short audio.
- [ ] T-03.7 — Idempotency: skip if `file_name` already ingested.

**Done when:** 10-min call → 20–30 chunks · each chunk `speaker_role` sales/customer ·
chunks readable (no mid-sentence cuts) · re-run creates no duplicates.

---

## T-04 — Embedding Pipeline & Vector Search  ⏱ 2–3 days  ·  Status: ⬜

**Goal:** embed every chunk, store in pgvector, implement semantic search.

**Concepts I'll teach (deep):** what embeddings are (semantic vector space); cosine vs L2
distance and the `<=>` operator; why nomic-embed (768-dim); batching & throughput; retry
with exponential backoff; how metadata filters combine with ANN (pre/post-filtering).

**Sub-steps:**
- [ ] T-04.1 — `embed.py`: `batch_embed(texts)` → float[768] via Ollama `/api/embeddings`.
- [ ] T-04.2 — Pipeline step: after ingestion, embed all chunks → `chunk_embeddings`.
- [ ] T-04.3 — Retry logic (exponential backoff) for Ollama failures.
- [ ] T-04.4 — `search.py`: `semantic_search(query, top_k=8, filters={})`.
- [ ] T-04.5 — Filters: call_date range, salesperson, speaker_role.
- [ ] T-04.6 — pgvector `<=>` cosine query + WHERE filters.

**Done when:** one embedding row per chunk · search < 3s for 50-call corpus · top-3 results
visibly relevant · `speaker_role='customer'` filter excludes sales chunks.

---

## T-05 — RAG Query Engine & Sentiment Analysis  ⏱ 3–4 days  ·  Status: ⬜

**Goal:** full RAG: question → retrieve → LLM cited answer. Add sentiment + topics at ingestion.

**Concepts I'll teach (deep):** the RAG pattern (retrieve-then-generate) & why it beats
fine-tuning here; prompt engineering & context construction; grounding/citations to fight
hallucination; context-window budgeting; VADER lexicon-based sentiment vs ML models; LLM
topic extraction & prompt design.

**Sub-steps:**
- [ ] T-05.1 — `rag.py`: `query(question, filters)` → `{answer, sources}`.
- [ ] T-05.2 — Prompt template: system + retrieved context + question.
- [ ] T-05.3 — LLM generation via Ollama (llama3.2).
- [ ] T-05.4 — Source citations: call_id, date, speaker, excerpt per answer.
- [ ] T-05.5 — VADER sentiment per chunk at ingestion → `chunks.sentiment`.
- [ ] T-05.6 — Call-level sentiment (avg) → `call_sentiment`.
- [ ] T-05.7 — Topic extractor (1 LLM call/call) → `call_topics` (top 3).
- [ ] T-05.8 — Wire sentiment + topics into `ingest.py` (after chunk, before DB write).

**Done when:** answer grounded (no hallucinated calls) · ≥2 citations with date+excerpt ·
sentiment populated for all chunks · 2–4 topics/call · end-to-end < 30s on CPU.

---

## T-06 — FastAPI Backend & Streamlit UI  ⏱ 3–4 days  ·  Status: ⬜

**Goal:** expose RAG as REST API + build the Streamlit analytics app.

**Concepts I'll teach (deep):** REST design & HTTP verbs; FastAPI async, Pydantic models,
auto Swagger; sync vs async / background tasks for ingestion; Streamlit's run-on-rerun
model & session state; charts (Altair); separating API from UI.

**Sub-steps:**
- [ ] T-06.1 — FastAPI `api/main.py`: `POST /query`, `POST /ingest`, `GET /calls`, `GET /calls/{id}`.
- [ ] T-06.2 — `POST /query` returns answer + sources JSON.
- [ ] T-06.3 — `POST /ingest`: audio upload + metadata, runs pipeline async.
- [ ] T-06.4 — `GET /calls` paginated list with sentiment summary.
- [ ] T-06.5 — Streamlit `ui/app.py` w/ `st.navigation` — Page 1 Chat.
- [ ] T-06.6 — Page 2 Call Browser (table, sentiment badge, transcript view).
- [ ] T-06.7 — Page 3 Insights (topics bar chart, sentiment trend via `st.altair_chart`).
- [ ] T-06.8 — Both run in app container (ports 8000, 8501).

**Done when:** all 3 pages load · chat round-trip works · browser shows calls + sentiment ·
insights charts render from DB · file upload triggers ingestion, new call appears.

---

## T-07 — Testing, Tuning & Documentation  ⏱ 2–3 days  ·  Status: ⬜

**Goal:** tests for core modules, tune RAG quality, document the project.

**Concepts I'll teach (deep):** unit vs integration tests; pytest fixtures & mocking
Ollama/DB; RAG evaluation (retrieval@k, why eval matters); chunk-size & top-K experiments
and how they trade relevance vs context budget; writing docs for a future reader.

**Sub-steps:**
- [ ] T-07.1 — pytest suite: `test_ingest.py`, `test_embed.py`, `test_rag.py`, `test_api.py`.
- [ ] T-07.2 — Fixtures: small synthetic 3-chunk transcript.
- [ ] T-07.3 — RAG eval: 10 Q&A pairs, check correct call in top-3.
- [ ] T-07.4 — Chunk-size experiment (200/400/600) — compare relevance.
- [ ] T-07.5 — Top-K experiment (4/8/12) — quality vs context.
- [ ] T-07.6 — `README.md`: ASCII architecture, quick-start, env table.
- [ ] T-07.7 — `LEARNINGS.md`: ≥5 personal observations.
- [ ] T-07.8 — Makefile: `test`, `eval`, `logs`, `reset-db`.

**Done when:** pytest >80% pass · correct call in top-3 for ≥7/10 questions · README runnable
in <15 min · LEARNINGS has ≥5 notes.

---

## T-08 — Internet Exposure: Cloudflare Tunnel + Auth + Hardening  ⏱ 2–3 days  ·  Status: ⬜

**Goal:** securely expose the app over the internet from your home machine, free, no port-forwarding.

**Concepts I'll teach (deep):** reverse proxies & why Nginx; HTTP proxy headers; outbound
tunnels vs port-forwarding; TLS termination at Cloudflare edge; zero-trust auth (Cloudflare
Access); rate limiting; secrets hygiene; restart policies & health checks for resilience.

**Sub-steps:**
- [ ] T-08.1 — Cloudflare account + domain (or trycloudflare subdomain).
- [ ] T-08.2 — Nginx reverse-proxy service (5th): `/` → Streamlit :8501, `/api` → FastAPI :8000.
- [ ] T-08.3 — `cloudflared` tunnel service (4th) + `config.yml` ingress → nginx.
- [ ] T-08.4 — Cloudflare Access policy (Google/GitHub login).
- [ ] T-08.5 — Rate limiting rule (20 req/min/IP).
- [ ] T-08.6 — Secrets hardening: no credentials in compose/committed files.
- [ ] T-08.7 — `restart: always` + health checks; optional auto-start on boot.
- [ ] T-08.8 — Streamlit proxy-safe config (`headless=true`, `enableCORS=false`).

**Done when:** reachable at public HTTPS from another network · unauthenticated → Access
login · reboot → auto-recovers in <60s · remote query returns cited answer · tunnel green ·
no secrets in committed files.

---

## Decisions Log

> Record choices we make as we go (versions pinned, design forks taken, deviations from PRD),
> so context survives across sessions.

| Date | Task | Decision | Rationale |
|---|---|---|---|
| 2026-05-30 | — | Teaching style: "we pair, step by step"; depth: "deep fundamentals". | User preference for this learning program. |
| 2026-05-30 | — | Single source of truth for progress = this file's CHECKPOINT block, backed by a project memory pointer. | Reliable cross-session resume. |
| 2026-05-30 | T-00 | Host environment audited: Docker+Compose+Make+Git+curl+VSCode all present. Only blocker = Docker daemon not running. | Pre-start audit on Ubuntu 22.04. |
| 2026-05-30 | T-00 | Python 3.11 not installed on host — deliberate. App container uses 3.11 via Dockerfile; host Python 3.10 is fine for any local tooling. | Containerized approach means host Python version doesn't matter. |

---

## Glossary (built up as we go)

> Plain-language definitions of terms as we encounter them. Add entries during each task.

- _(empty — we'll fill this in as we learn.)_

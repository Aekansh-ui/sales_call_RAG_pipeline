# T-02 — Database Schema & Migrations
# Command & Concept Reference

> This file logs every concept taught and every shell command used during T-02.
> Purpose: a detailed reference you can return to at any point — not a summary.
> Structure: concepts first (the "why" and "how it works"), commands second (the "what to run").

---

## Table of Contents

### Concepts
- [C1. Relational schema design & normalization](#c1-relational-schema-design--normalization)
- [C2. Primary keys — UUID vs SERIAL](#c2-primary-keys--uuid-vs-serial)
- [C3. TIMESTAMPTZ vs TIMESTAMP](#c3-timestamptz-vs-timestamp)
- [C4. Foreign keys & ON DELETE CASCADE](#c4-foreign-keys--on-delete-cascade)
- [C5. What a `vector` column is](#c5-what-a-vector-column-is)
- [C6. pgvector distance operators — L2 vs cosine vs inner product](#c6-pgvector-distance-operators--l2-vs-cosine-vs-inner-product)
- [C7. IVFFlat — how fast approximate vector search works](#c7-ivfflat--how-fast-approximate-vector-search-works)
- [C8. Migrations as version control for the database](#c8-migrations-as-version-control-for-the-database)
- [C9. Connection pooling](#c9-connection-pooling)

### Commands
- [1. Running migrations](#1-running-migrations)
- [2. Inspecting the schema in psql](#2-inspecting-the-schema-in-psql)
- [3. Testing INSERT + SELECT + CASCADE](#3-testing-insert--select--cascade)
- [4. Verifying the IVFFlat index with EXPLAIN](#4-verifying-the-ivfflat-index-with-explain)
- [5. db.py utility commands](#5-dbpy-utility-commands)

---

# PART A — Concepts

---

## C1. Relational schema design & normalization

**What it is:**
A relational database stores data in tables (rows + columns) with strict types. The core
design principle is **normalization** — store each fact exactly once, and reference it
from other tables via foreign keys rather than duplicating it.

**How it actually works:**
In an un-normalized design you might store call metadata and transcript text together in
one giant table, duplicating the salesperson name on every chunk. In a normalized design:
- `calls` stores call-level facts (file name, date, salesperson) once per call.
- `chunks` stores chunk-level facts (text, timestamps, speaker) once per chunk, with a
  `call_id` column pointing back to the parent call.
- `chunk_embeddings` stores the 768-dim vector once per chunk.

This is called **1NF / 2NF / 3NF** (Normal Forms) — the key idea is that every non-key
column depends on the whole key and nothing but the key.

**Why we use it in this project:**
One call produces 20–30 chunks, each with its own embedding. If we stored the call
metadata on every chunk row, a salesperson name change would require updating 30 rows.
With normalization, you update one row in `calls` and every chunk automatically reflects it.

**The schema relationship graph:**
```
calls ──< chunks ──< chunk_embeddings
      ──< call_topics
      ──< call_sentiment
```
`──<` means "one-to-many": one call has many chunks; one chunk has one embedding (one-to-one).

**Tradeoffs:**
Joins add query complexity. A denormalized schema (everything in one table) is faster to
query but painful to maintain and update. For this project's query patterns (retrieve by
call, by speaker, by semantic similarity) the join cost is negligible.

**Alternatives considered:**
- NoSQL (MongoDB): flexible schema, no joins needed. Rejected because pgvector gives us
  both vector search and relational queries in one system — no need for two databases.
- Flat table: simpler, but duplicates call metadata on every chunk row (~30× redundancy).

---

## C2. Primary keys — UUID vs SERIAL

**What it is:**
Every row needs a unique identifier — the **primary key (PK)**. Two common choices:

| | `SERIAL` (integer) | `UUID` |
|---|---|---|
| What it is | Auto-incrementing integer: 1, 2, 3… | 128-bit random hex ID: `a3f2c1d0-4e5b-...` |
| Size | 4 bytes | 16 bytes |
| Generation | Database generates it on INSERT | Can be generated anywhere (Python, DB, CLI) |
| Human-readable | Yes — easy to type in a URL | No — but copy-paste works fine |

**How it actually works:**
- `SERIAL`: Postgres maintains a sequence object (a counter). On every INSERT, the sequence
  is incremented atomically. You cannot insert a specific ID without resetting the sequence.
- `UUID`: `gen_random_uuid()` (built into Postgres 13+, no extension needed) generates a
  cryptographically random 128-bit value. The probability of a collision across two
  independently generated UUIDs is astronomically small (~1 in 10^38).

**Why we use UUID in this project:**
1. **Pre-generation in Python**: we want to know the `call_id` before inserting the call
   row, so we can also create chunks referencing it in the same transaction.
2. **Safe across environments**: if you ever export data from dev and import into prod,
   SERIAL IDs (1, 2, 3…) will collide. UUIDs are globally unique.
3. **No information leakage**: SERIAL IDs reveal row count (`/calls/1042` → you have at
   least 1042 calls). UUIDs reveal nothing.

**Tradeoffs:**
UUID indexes are slightly larger (16 bytes vs 4) and slightly slower to insert into
(random values cause more B-tree page splits than sequential integers). For our corpus
size this is imperceptible.

**In SQL:**
```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid()
```
`DEFAULT gen_random_uuid()` means: if the INSERT doesn't provide an `id`, generate one
automatically. If you provide one (from Python), it uses yours.

---

## C3. TIMESTAMPTZ vs TIMESTAMP

**What it is:**
- `TIMESTAMP`: stores a date and time with no timezone information. It's a "naive" datetime.
- `TIMESTAMPTZ` (timestamp with time zone): stores UTC internally, converts to the session
  timezone on read.

**How it actually works:**
`TIMESTAMPTZ` always stores UTC. When you insert `2026-06-13 15:00:00+05:30` (IST), Postgres
converts it to `2026-06-13 09:30:00 UTC` for storage. When you read it back, Postgres
converts it to the current session's timezone. The stored value is always unambiguous.

`TIMESTAMP` stores exactly what you give it, with no conversion. If your application code
runs in UTC and a user uploads a file timestamped in IST, Postgres will store whatever it
receives — and you can't tell later which timezone it was in.

**Why we always use TIMESTAMPTZ for `created_at`:**
Silent timezone bugs are extremely hard to debug. A row created at 15:00 IST that reads
back as 15:00 (no timezone) looks correct in India but wrong everywhere else. Using
`TIMESTAMPTZ` makes the timezone explicit and conversion automatic.

**In SQL:**
```sql
created_at TIMESTAMPTZ NOT NULL DEFAULT now()
```
`now()` returns the current timestamp in the database server's timezone — always UTC in
our Docker setup.

---

## C4. Foreign keys & ON DELETE CASCADE

**What it is:**
A **foreign key** is a column in one table that references the primary key of another table.
It enforces **referential integrity** — Postgres will reject any INSERT or UPDATE that
would create a reference to a row that doesn't exist.

**Example:**
```sql
-- This will FAIL if call_id doesn't exist in calls.id:
INSERT INTO chunks (call_id, ...) VALUES ('non-existent-uuid', ...);
-- ERROR: insert or update on table "chunks" violates foreign key constraint
```

**ON DELETE CASCADE:**
Defines what happens when the referenced parent row is deleted:

| Behaviour | SQL | Effect |
|---|---|---|
| `CASCADE` | `ON DELETE CASCADE` | Delete all child rows automatically |
| `RESTRICT` (default) | `ON DELETE RESTRICT` | Reject the delete if children exist |
| `SET NULL` | `ON DELETE SET NULL` | Set the FK column to NULL in child rows |

**Why we use CASCADE:**
When a call is deleted (e.g., you remove a test call), all its chunks, embeddings, topics,
and sentiment rows should also disappear. Without CASCADE, you'd have to manually delete
them in the right order (child tables first, then parent). With CASCADE, one `DELETE FROM
calls WHERE id = ?` cleans up everything automatically.

**The cascade chain in our schema:**
```
DELETE FROM calls WHERE id = X
  → automatically deletes chunks WHERE call_id = X
      → automatically deletes chunk_embeddings WHERE chunk_id IN (deleted chunks)
      → automatically deletes call_topics WHERE call_id = X
      → automatically deletes call_sentiment WHERE call_id = X
```

**In SQL:**
```sql
call_id UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE
```

---

## C5. What a `vector` column is

**What it is:**
A regular Postgres column stores a scalar — a single number, string, or date. A `vector(768)`
column stores an **array of 768 floating-point numbers** — the output of an embedding model.

**How embeddings work (the concept):**
An embedding model (like `nomic-embed-text`) maps text to a point in high-dimensional space.
The key property: **texts with similar meaning land near each other**. "The customer was
frustrated" and "The client seemed annoyed" will produce vectors that point in nearly the
same direction. "Quarterly revenue targets" will be far away from both.

The `nomic-embed-text` model produces 768-dimensional vectors. Each of the 768 dimensions
captures some aspect of meaning — no single dimension is human-interpretable, but together
they encode rich semantic information.

**What's stored in the DB:**
Each row in `chunk_embeddings` stores:
- `chunk_id`: which chunk this embedding belongs to
- `embedding`: the 768 floats produced by nomic-embed-text for that chunk's text

At query time, the user's question is also embedded into a 768-dim vector, and Postgres
finds the `chunk_embeddings` rows whose vectors are closest to it — that's semantic search.

**In SQL:**
```sql
embedding vector(768) NOT NULL
```
The `vector` type comes from the `pgvector` extension. It must be enabled before this
column can be created (migration 002 does this with `CREATE EXTENSION IF NOT EXISTS vector`).

---

## C6. pgvector distance operators — L2 vs cosine vs inner product

**What it is:**
pgvector adds three distance operators for comparing vectors:

| Operator | Name | Formula | Use when... |
|---|---|---|---|
| `<->` | L2 (Euclidean) | √(Σ(aᵢ - bᵢ)²) | Vectors have meaningful magnitude |
| `<=>` | Cosine distance | 1 - (a·b / ‖a‖‖b‖) | Meaning is in direction, not magnitude |
| `<#>` | Negative inner product | -(a·b) | Vectors are unit-normalized (faster) |

**How L2 works:**
Measures the straight-line distance between two points in N-dimensional space. Sensitive
to the *magnitude* (length) of each vector. Two vectors pointing in the same direction but
one twice as long have a large L2 distance even though they encode the same meaning.

**How cosine works:**
Measures the *angle* between two vectors, ignoring their lengths. Two vectors with identical
direction have cosine distance = 0 (perfectly similar), regardless of their magnitudes.
Cosine similarity = 1 - cosine distance, so similarity 1.0 = identical direction.

**Why we use cosine (`<=>`) for text embeddings:**
Embedding models encode meaning in the *direction* of the vector, not its length. The
length can vary depending on the text's length, vocabulary, etc. Cosine distance
correctly identifies "The customer complained about pricing" and "The client expressed
unhappiness with cost" as similar, even if their raw vectors have different magnitudes.

**In SQL (used in T-04 and T-05):**
```sql
SELECT chunk_id
FROM chunk_embeddings
ORDER BY embedding <=> $1::vector(768)   -- $1 is the query embedding
LIMIT 8;
```

---

## C7. IVFFlat — how fast approximate vector search works

**What it is:**
A brute-force vector search compares your query vector against every row in the table.
At 1,000 chunks this is instant. At 1,000,000 chunks this is too slow. **IVFFlat**
(Inverted File with Flat quantization) is an index type that speeds this up using
approximate nearest-neighbour (ANN) search.

**How it actually works — two phases:**

**Phase 1 — Build (happens when you CREATE INDEX):**
1. k-means clustering runs on all vectors in the table.
2. Vectors are grouped into `lists` buckets (e.g., `lists = 50`).
3. Each bucket stores the chunk IDs closest to that bucket's centroid.
4. Result: a lookup table mapping centroid → list of nearby chunk IDs.

**Phase 2 — Query (happens on SELECT):**
1. Your query vector is compared against all `lists` centroids.
2. The `probes` closest centroids are selected (e.g., `probes = 5`).
3. Only the vectors in those `probes` buckets are compared to your query.
4. The top-k results from those buckets are returned.

**The tradeoff — recall vs speed:**
- More `probes` → check more buckets → higher chance of finding the true nearest neighbour
  (higher recall) → slower.
- Fewer `probes` → check fewer buckets → may miss some relevant results → faster.
- `probes = sqrt(lists)` is the rule of thumb for a good recall/speed balance.

**Tuning parameters:**

| Parameter | Set at | Effect |
|---|---|---|
| `lists` | CREATE INDEX time | Number of k-means clusters. Rule of thumb: `rows / 1000`, min 10. |
| `probes` | Query time (`SET ivfflat.probes = N`) | How many buckets to search per query. Default = 1. |

**Our settings:**
```sql
-- Index: lists = 50 (suitable for up to ~50,000 chunks)
CREATE INDEX ... USING ivfflat (embedding vector_cosine_ops) WITH (lists = 50);

-- At query time (in search.py, T-04):
SET ivfflat.probes = 5;
```

**Important — index requires data to be useful:**
IVFFlat needs rows to train its k-means clusters. If you create the index on an empty
table (as we do in migration 002), it creates a trivial index. The index becomes meaningful
once you have a significant number of rows — typically 1,000+. For our use case (dozens
to hundreds of calls), the index overhead is low and the benefit is mostly future-proofing.

**Alternatives considered:**
- **Brute force (no index)**: always returns exact results, fine for small datasets (<10k rows).
  pgvector falls back to this when `lists = 0`.
- **HNSW (Hierarchical Navigable Small World)**: better recall at higher speed, but uses
  more memory and takes longer to build. Available in pgvector 0.5+. Good choice if the
  corpus grows to millions of rows.
- We chose IVFFlat because it's simpler to tune and sufficient for the expected corpus size.

---

## C8. Migrations as version control for the database

**What it is:**
A **migration** is a SQL file (or script) that makes a specific, incremental change to the
database schema. Migrations are numbered and run in order, and together they define the
complete schema.

**Why not just `CREATE TABLE IF NOT EXISTS` in Python on startup?**
You could auto-create tables when the app starts. This works for a toy project but breaks
down in practice:
- You can't see what the schema looked like at any point in history.
- Schema changes (adding a column, adding an index) have no safe, repeatable way to run.
- In a team, two developers can't independently change the schema without conflicts.

Migrations solve this: each schema change is a numbered file, committed to git, run exactly
once on each environment. The history of migration files *is* the history of your schema.

**Our migration structure:**
```
sql/migrations/
├── 001_init.sql        ← creates all 5 tables (no vector type yet)
└── 002_pgvector.sql    ← enables extension, adds vector column + index
```

**Why split into two files?**
`CREATE EXTENSION vector` must run before any `vector(768)` column can be created.
By splitting the work, each migration has a single clear responsibility. If something
fails, it's obvious which step caused it.

**Idempotency — safe to re-run:**
All statements use `IF NOT EXISTS` or `DO $$ IF NOT EXISTS ... $$` blocks, so running
the migrations twice produces the same result as running them once. This matters because
`make migrate` might accidentally be run on an already-initialized database.

**In `db.py`:**
```python
def run_migrations() -> None:
    migration_dir = os.path.join(os.path.dirname(__file__), "..", "sql", "migrations")
    files = sorted(glob.glob(os.path.join(migration_dir, "*.sql")))
    for path in files:
        with open(path) as f:
            execute(f.read())
```
`sorted()` ensures files run in filename order (001 before 002). `glob` finds all `.sql`
files, so adding a future `003_add_index.sql` is automatically picked up.

**Alternatives considered:**
- **Alembic** (SQLAlchemy migration tool): autogenerates migration files from model
  changes, tracks applied migrations in a `alembic_version` table. More powerful but
  adds a dependency and more complexity. Overkill for this project.
- **Flyway / Liquibase**: enterprise Java-origin tools. Not Python-native.
- Plain SQL files run manually: we chose this — simple, transparent, no extra tooling.

---

## C9. Connection pooling

**What it is:**
Every database query requires a **connection** — a persistent TCP socket plus an
authenticated Postgres session. Opening a new connection takes 10–50ms. A connection pool
keeps a small set of connections open and reuses them across requests.

**How it actually works:**
`psycopg2.pool.ThreadedConnectionPool` maintains a pool of `minconn` to `maxconn` open
connections. When your code calls `pool.getconn()`, it receives an already-open connection.
When done, `pool.putconn(conn)` returns it to the pool (doesn't close it). If all
connections are in use and a new request arrives, the call blocks until one is returned.

**Our pool settings:**
```python
_pool = pool.ThreadedConnectionPool(minconn=1, maxconn=5, dsn=_dsn())
```
- `minconn=1`: always keep at least 1 connection open (avoids cold-start latency).
- `maxconn=5`: never open more than 5 simultaneous connections (Postgres default max is 100;
  we stay well within it).

**The `execute()` helper pattern:**
```python
def execute(sql, params=None, *, fetch=False):
    conn = get_conn()
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            result = cur.fetchall() if fetch else None
        conn.commit()
        return result
    except Exception:
        conn.rollback()   # ← rollback on error so the connection is reusable
        raise
    finally:
        put_conn(conn)    # ← always return the connection to the pool
```
The `finally` block is critical — it ensures the connection is returned even if an
exception is raised. Without it, a failed query would leak a connection, and eventually
the pool would be exhausted.

**`RealDictCursor`:**
By default psycopg2 returns rows as tuples: `(value1, value2, ...)`. `RealDictCursor`
returns rows as dicts: `{"column_name": value, ...}`. Much easier to work with in Python.

**Tradeoffs:**
A simple `psycopg2.connect()` on every query is fine for scripts but not for a server
handling concurrent requests. `ThreadedConnectionPool` is the right tradeoff for a
low-concurrency app (< 50 simultaneous requests). For high concurrency, `asyncpg` with
`asyncio` is faster.

---

# PART B — Commands

---

## 1. Running migrations

### 1.1 Run all migrations via Makefile

```bash
make migrate
```

**What it does:**
Runs `docker compose exec app python -m app.db migrate` inside the app container.
`python -m app.db` invokes `app/db.py` as a module (the `if __name__ == "__main__"` block),
with `migrate` as the subcommand, which calls `run_migrations()`.

**Expected output:**
```
  Running migration: 001_init.sql
  Running migration: 002_pgvector.sql
  2 migration(s) applied.
```

**If it fails with `KeyError: 'POSTGRES_HOST'`:**
The app container was started before `POSTGRES_HOST` was added to `.env`. Run:
```bash
docker compose up -d   # recreates containers with updated env (restart does NOT work)
make migrate
```

**If it fails with `connection refused`:**
The postgres container isn't ready yet. Wait ~5 seconds and retry.

---

### 1.2 Run migrations directly (without Makefile)

```bash
docker compose exec app python -m app.db migrate
```

Same effect as `make migrate` but typed out in full.

---

### 1.3 Run health check

```bash
docker compose exec app python -m app.db health
```

**Expected output:**
```
healthy
```

Returns exit code 0 if pgvector is enabled and the DB is reachable, exit code 1 otherwise.

---

## 2. Inspecting the schema in psql

### 2.1 Open a psql shell

```bash
docker compose exec postgres psql -U raguser -d sales_rag
```

**What it does:**
- `docker compose exec postgres` — runs a command inside the postgres container
- `psql` — the Postgres interactive terminal
- `-U raguser` — connect as user `raguser` (from `.env`)
- `-d sales_rag` — connect to database `sales_rag` (from `.env`)

Type `\q` to quit.

---

### 2.2 List all tables

```bash
docker compose exec postgres psql -U raguser -d sales_rag -c "\dt"
```

**Expected output:**
```
              List of relations
 Schema |       Name       | Type  |  Owner
--------+------------------+-------+---------
 public | call_sentiment   | table | raguser
 public | call_topics      | table | raguser
 public | calls            | table | raguser
 public | chunk_embeddings | table | raguser
 public | chunks           | table | raguser
(5 rows)
```

---

### 2.3 Describe a table (columns, types, constraints, indexes)

```bash
docker compose exec postgres psql -U raguser -d sales_rag -c "\d chunk_embeddings"
```

**Expected output:**
```
                    Table "public.chunk_embeddings"
   Column   |           Type           | Collation | Nullable | Default
------------+--------------------------+-----------+----------+---------
 chunk_id   | uuid                     |           | not null |
 created_at | timestamp with time zone |           | not null | now()
 embedding  | vector(768)              |           | not null |
Indexes:
    "chunk_embeddings_pkey" PRIMARY KEY, btree (chunk_id)
    "chunk_embeddings_embedding_idx" ivfflat (embedding vector_cosine_ops) WITH (lists='50')
Foreign-key constraints:
    "chunk_embeddings_chunk_id_fkey" FOREIGN KEY (chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
```

Key things to verify:
- `embedding` column is `vector(768)` ✓
- `chunk_embeddings_embedding_idx` is `ivfflat ... vector_cosine_ops` ✓
- Foreign key references `chunks(id) ON DELETE CASCADE` ✓

---

### 2.4 List installed extensions

```bash
docker compose exec postgres psql -U raguser -d sales_rag -c "\dx"
```

**Expected output (relevant lines):**
```
 vector | ... | public | vector data type and ivfflat and hnsw access methods
```

---

## 3. Testing INSERT + SELECT + CASCADE

### 3.1 Full round-trip test

```sql
-- Insert a test call
INSERT INTO calls (file_name, call_date, salesperson, customer, duration_sec, raw_transcript)
VALUES ('test.wav', '2026-01-01', 'Alice', 'Acme Corp', 300, 'Hello world.')
RETURNING id;

-- Insert a chunk using the call's id
WITH c AS (SELECT id FROM calls WHERE file_name = 'test.wav')
INSERT INTO chunks (call_id, chunk_index, speaker_role, text, start_sec, end_sec)
SELECT id, 0, 'salesperson', 'Hello world.', 0, 10 FROM c
RETURNING id;

-- Insert a fake embedding (all zeros) for the chunk
WITH ch AS (SELECT id FROM chunks WHERE text = 'Hello world.')
INSERT INTO chunk_embeddings (chunk_id, embedding)
SELECT id, array_fill(0, ARRAY[768])::vector(768) FROM ch;

-- Verify the join
SELECT c.file_name, ch.text, 'embedding present' AS embedding
FROM calls c
JOIN chunks ch ON ch.call_id = c.id
JOIN chunk_embeddings ce ON ce.chunk_id = ch.id;

-- Test cascade: deleting the call should remove chunks + embeddings
DELETE FROM calls WHERE file_name = 'test.wav';

-- Verify chunks are gone (should return 0 rows)
SELECT COUNT(*) FROM chunks WHERE text = 'Hello world.';
```

**`array_fill(0, ARRAY[768])::vector(768)` explained:**
- `array_fill(0, ARRAY[768])` — creates a Postgres array of 768 zeros: `{0,0,0,...}`
- `::vector(768)` — casts it to the pgvector `vector(768)` type
- We use this as a fake embedding for testing without needing Ollama

---

## 4. Verifying the IVFFlat index with EXPLAIN

### 4.1 Confirm the index is used in a vector query

```sql
EXPLAIN
SELECT chunk_id
FROM chunk_embeddings
ORDER BY embedding <=> array_fill(0, ARRAY[768])::vector(768)
LIMIT 5;
```

**Expected output (key line):**
```
Index Scan using chunk_embeddings_embedding_idx on chunk_embeddings
```

If you see `Seq Scan` instead of `Index Scan`, the planner decided a full table scan
was cheaper (common on very small tables — it becomes `Index Scan` once the table grows).

**`EXPLAIN` vs `EXPLAIN ANALYZE`:**
- `EXPLAIN` shows the *query plan* (what Postgres intends to do) — no data is read.
- `EXPLAIN ANALYZE` *executes* the query and shows actual timing. Useful for performance
  tuning but not needed for schema verification.

---

## 5. db.py utility commands

### 5.1 Run migrations

```bash
docker compose exec app python -m app.db migrate
```

### 5.2 Health check

```bash
docker compose exec app python -m app.db health
```

### 5.3 Quick Python test of the connection pool

```bash
docker compose exec app python -c "
from app.db import execute, health_check
print('healthy:', health_check())
rows = execute('SELECT COUNT(*) AS n FROM calls', fetch=True)
print('calls in DB:', rows[0]['n'])
"
```

---

## Summary — T-02 status

| Sub-step | Description | Status |
|---|---|---|
| T-02.1 | `calls` table | ✅ |
| T-02.2 | `chunks` table | ✅ |
| T-02.3 | `chunk_embeddings` table with `vector(768)` | ✅ |
| T-02.4 | `call_topics` + `call_sentiment` tables | ✅ |
| T-02.5 | Migration files `001_init.sql` + `002_pgvector.sql` | ✅ |
| T-02.6 | `db.py`: connection pool + `run_migrations()` + `health_check()` | ✅ |
| T-02.7 | IVFFlat index on `chunk_embeddings.embedding` (cosine, lists=50) | ✅ |

**Done-when verification:**
- `\dt` shows all 5 tables ✅
- `\d chunk_embeddings` shows `vector(768)` + IVFFlat index ✅
- INSERT + SELECT round-trip across all tables ✅
- `EXPLAIN` shows IVFFlat index scan ✅
- `ON DELETE CASCADE` removes child rows when parent deleted ✅

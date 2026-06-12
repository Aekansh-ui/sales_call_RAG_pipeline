-- Migration 001 — core schema
-- Creates all five tables: calls, chunks, chunk_embeddings, call_topics, call_sentiment.
-- Run once on a fresh database. Safe to re-run: all statements use IF NOT EXISTS.

-- calls — one row per ingested audio file
CREATE TABLE IF NOT EXISTS calls (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name      TEXT        NOT NULL UNIQUE,
    call_date      DATE        NOT NULL,
    salesperson    TEXT        NOT NULL,
    customer       TEXT        NOT NULL,
    duration_sec   INTEGER     NOT NULL CHECK (duration_sec > 0),
    raw_transcript TEXT        NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- chunks — transcript split into ~400-token segments with speaker labels
CREATE TABLE IF NOT EXISTS chunks (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id      UUID        NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    chunk_index  INTEGER     NOT NULL CHECK (chunk_index >= 0),
    speaker_role TEXT        NOT NULL CHECK (speaker_role IN ('salesperson', 'customer', 'unknown')),
    text         TEXT        NOT NULL,
    start_sec    REAL        NOT NULL,
    end_sec      REAL        NOT NULL,
    sentiment    TEXT        CHECK (sentiment IN ('positive', 'negative', 'neutral')),
    UNIQUE (call_id, chunk_index)
);

-- chunk_embeddings — one 768-dim vector per chunk (nomic-embed-text output)
-- The vector column is added in migration 002 after pgvector is enabled.
CREATE TABLE IF NOT EXISTS chunk_embeddings (
    chunk_id   UUID PRIMARY KEY REFERENCES chunks(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- call_topics — LLM-extracted topics for each call (one row per topic)
CREATE TABLE IF NOT EXISTS call_topics (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id    UUID        NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    topic      TEXT        NOT NULL,
    confidence REAL        NOT NULL CHECK (confidence BETWEEN 0 AND 1)
);

-- call_sentiment — aggregate sentiment scores for the whole call
CREATE TABLE IF NOT EXISTS call_sentiment (
    call_id  UUID  PRIMARY KEY REFERENCES calls(id) ON DELETE CASCADE,
    overall  TEXT  NOT NULL CHECK (overall IN ('positive', 'negative', 'neutral')),
    score    REAL  NOT NULL CHECK (score BETWEEN -1 AND 1)
);

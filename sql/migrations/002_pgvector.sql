-- Migration 002 — enable pgvector and add embedding column + IVFFlat index
-- Depends on: 001_init.sql (chunk_embeddings table must exist)

-- Enable the pgvector extension (safe to re-run: CREATE EXTENSION IF NOT EXISTS)
CREATE EXTENSION IF NOT EXISTS vector;

-- Add the 768-dim embedding column to chunk_embeddings.
-- nomic-embed-text produces 768-dimensional vectors.
-- DO block makes this idempotent: skips if the column already exists.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'chunk_embeddings' AND column_name = 'embedding'
    ) THEN
        ALTER TABLE chunk_embeddings ADD COLUMN embedding vector(768) NOT NULL;
    END IF;
END
$$;

-- IVFFlat index for approximate nearest-neighbour cosine search.
-- lists=50: k-means buckets (tune upward as corpus grows beyond ~50k chunks).
-- At query time, SET ivfflat.probes = 5 (default) to 10 for higher recall.
CREATE INDEX IF NOT EXISTS chunk_embeddings_embedding_idx
    ON chunk_embeddings
    USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 50);

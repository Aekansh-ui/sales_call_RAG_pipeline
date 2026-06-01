-- Enable the pgvector extension in the target database.
-- This runs once on first boot (empty volume) via /docker-entrypoint-initdb.d/.
-- pgvector adds the vector column type and distance operators (<=> <#> <+>)
-- used by the chunk_embeddings table and its IVFFlat index.
CREATE EXTENSION IF NOT EXISTS vector;

# =============================================================================
# Sales Call RAG Pipeline — App Container
# =============================================================================
# Base: python:3.11-slim (Debian bookworm, stripped)
#   ~130 MB vs ~900 MB for python:3.11 full.
#   Slim removes build tools and docs we don't need at runtime.
#   Any C-extension compilation happens during pip install below; the resulting
#   .so files are all that's needed to run.
#
# Layer order matters for build cache:
#   1. OS-level packages  — changes almost never
#   2. requirements.txt   — changes only when packages are added/removed
#   3. pip install        — cached unless step 2 changed (the expensive step)
#   4. app source code    — changes on every code edit
# Putting fast-changing layers last means Docker reuses the expensive pip
# cache on every code-only change.
# =============================================================================

FROM python:3.11-slim

# Keeps Python from buffering stdout/stderr — log lines appear immediately
# rather than being held until the buffer fills. Critical for seeing progress
# bars and errors in `docker compose logs`.
ENV PYTHONUNBUFFERED=1

# Prevents Python from writing .pyc bytecode cache files into the image.
# Saves a small amount of space and avoids stale cache confusion.
ENV PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# Install OS-level dependencies that some Python packages need at compile time.
# libgomp1    — OpenMP runtime; required by CTranslate2 (faster-whisper)
# ffmpeg      — audio decoding; required by whisper and pyannote
# We install them now (before pip install) so they're available when pip
# builds any C extensions. --no-install-recommends keeps the layer small.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# --- Layer: Python dependencies (cached aggressively) ---
# Copy requirements.txt BEFORE the rest of the source code.
# If requirements.txt hasn't changed, Docker reuses this cache layer and
# skips the pip install entirely — saving 1-3 minutes on every code-only rebuild.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# --- Layer: Application source code ---
# This layer changes on every code edit. Because it's last, all the expensive
# layers above it stay cached.
COPY . .

# Document which ports the container listens on.
# EXPOSE is metadata only — it doesn't actually publish the port to the host.
# Publishing happens in docker-compose.yml via the "ports:" key.
EXPOSE 8000 8501

# No CMD here — docker-compose.yml specifies the command per service target.
# FastAPI:   uvicorn api.main:app --host 0.0.0.0 --port 8000
# Streamlit: streamlit run ui/app.py --server.port 8501 --server.address 0.0.0.0

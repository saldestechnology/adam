# Compiled AI — Autonomous Rust Spec Miner
# Dockerfile with: Rust toolchain, opencode, ctx, Python, embedding model, harvest binary
# Multi-stage: builders first, runtime last.

# Stage 1a: Build the harvest AST hasher
FROM rust:latest AS harvest-builder
WORKDIR /build
COPY harvest/Cargo.toml harvest/Cargo.lock ./
COPY harvest/src ./src
RUN cargo build --release

# Stage 1b: Build ctx (code intelligence) with limited parallelism to avoid OOM
FROM rust:latest AS ctx-builder
RUN apt-get update && apt-get install -y cmake pkg-config && rm -rf /var/lib/apt/lists/*
RUN cd /tmp && \
    git clone --depth 1 https://github.com/saldestechnology/ctx.git && \
    cd ctx && \
    MAKEFLAGS="-j1" NUM_JOBS=1 CARGO_BUILD_JOBS=1 cmake --build . --parallel 1 2>/dev/null || true && \
    MAKEFLAGS="-j1" NUM_JOBS=1 CARGO_BUILD_JOBS=1 cargo build --release && \
    cp target/release/ctx /tmp/ctx-built && \
    chmod +x /tmp/ctx-built

# Stage 2: Final runtime image
FROM rust:latest

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    python3 \
    python3-pip \
    curl \
    tar \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install opencode CLI
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path

# Install Python packages for embedding + Qdrant
RUN pip3 install --no-cache-dir \
    "sentence-transformers" \
    "qdrant-client" \
    "numpy" \
    --break-system-packages \
    2>/dev/null || \
    pip3 install --no-cache-dir \
        "sentence-transformers" \
        "qdrant-client" \
        "numpy"

# Pre-download the embedding model so it is baked into the image
RUN python3 -c \
    "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

# Set working directory
WORKDIR /app

# Initialize a minimal Git repository (required for worktrees)
RUN git init && git config user.email "adam@docker.local" && git config user.name "Adam"

# Copy builder artifacts into the final image
COPY --from=harvest-builder /build/target/release/harvest /usr/local/bin/harvest
RUN chmod +x /usr/local/bin/harvest

COPY --from=ctx-builder /tmp/ctx-built /usr/local/bin/ctx
RUN chmod +x /usr/local/bin/ctx

# Copy application scripts
COPY adam.sh /app/adam.sh
RUN chmod +x /app/adam.sh

COPY scripts/embed_and_push.py /app/scripts/embed_and_push.py
RUN chmod +x /app/scripts/embed_and_push.py

# Copy system prompt (renamed for opencode consumption)
COPY SYSTEM.md /app/AGENTS.md

# Copy opencode project config
COPY .opencode /app/.opencode

# Create output directory
RUN mkdir -p /output

# Redirect tool homes to /output so only /output is written externally
ENV HOME=/output
ENV CARGO_HOME=/output/.cargo
ENV XDG_CONFIG_HOME=/output/.config
ENV XDG_CACHE_HOME=/output/.cache
ENV OUTPUT_DIR=/output
ENV PATH="/root/.opencode/bin:${PATH}"

# Embedding configuration
ENV EMBED_MODEL="all-MiniLM-L6-v2"
ENV EMBED_VECTOR_SIZE="384"

# Continuous loop daemon entrypoint
ENTRYPOINT ["/app/adam.sh"]

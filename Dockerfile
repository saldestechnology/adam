FROM rust:latest

# Install dependencies: git, python3, curl, tar
RUN apt-get update && apt-get install -y \
    git \
    python3 \
    python3-pip \
    curl \
    tar \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install opencode using the official install script
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path

# Set working directory
WORKDIR /app

# Initialize a minimal Git repository (required for worktrees)
RUN git init && git config user.email "adam@docker.local" && git config user.name "Adam"

# Copy the script
COPY adam.sh /app/adam.sh
RUN chmod +x /app/adam.sh

# Copy the opencode TTY wrapper
COPY opencode_wrapper.py /app/opencode_wrapper.py

# Copy the system prompt (renamed from SYSTEM.md to AGENTS.md inside the container)
COPY SYSTEM.md /app/AGENTS.md

# Copy opencode project config
COPY .opencode /app/.opencode

# Create output directory
RUN mkdir -p /output

# Redirect all tool homes to /output so only /output is written
ENV HOME=/output
ENV CARGO_HOME=/output/.cargo
ENV XDG_CONFIG_HOME=/output/.config
ENV XDG_CACHE_HOME=/output/.cache
ENV OUTPUT_DIR=/output
ENV PATH="/root/.opencode/bin:${PATH}"

# One-shot entrypoint
ENTRYPOINT ["/app/adam.sh"]

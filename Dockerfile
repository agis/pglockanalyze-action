# -------- pglockanalyze GitHub Action container --------
FROM ubuntu:22.04

LABEL org.opencontainers.image.source="https://github.com/YOURORG/pglockanalyze-action"
ARG DEBIAN_FRONTEND=noninteractive

# ---------- build‑time arg (postgres version) ----------
ARG PGVERSION=16

# ---------- basic OS packages ----------
RUN apt-get update -y && \
    apt-get install -y curl gnupg lsb-release ca-certificates sudo jq git build-essential && \
    rm -rf /var/lib/apt/lists/*

# ---------- PostgreSQL APT repo ----------
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
      "postgresql-$PGVERSION" "postgresql-contrib-$PGVERSION" \
      nodejs npm && \
    rm -rf /var/lib/apt/lists/*

# ---------- GitHub CLI ----------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-gpg.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-gpg.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-gpg.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update -y && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# ---------- Rust toolchain & pglockanalyze ----------
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y && \
    echo 'source $HOME/.cargo/env' >> /root/.bashrc
ENV PATH="/root/.cargo/bin:${PATH}"
RUN /root/.cargo/bin/cargo install pglockanalyze

# ---------- copy runtime scripts ----------
COPY entrypoint.sh /entrypoint.sh
COPY scripts/comment-pr.sh /comment-pr.sh
RUN chmod +x /entrypoint.sh /comment-pr.sh

# ---------- default ----------
ENTRYPOINT ["/entrypoint.sh"]

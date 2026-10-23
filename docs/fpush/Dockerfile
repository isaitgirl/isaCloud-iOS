# fpush (https://github.com/monal-im/fpush): XEP-0357 push appserver for isaCloud,
# running as an XMPP component (XEP-0114) of the Prosody container.

# --- build ---
FROM rust:1.89-bookworm AS builder

# pinned fpush commit (update deliberately, after reading the upstream changes)
ARG FPUSH_REPO=https://github.com/monal-im/fpush.git
ARG FPUSH_COMMIT=42359ca2b6a57a3fe172e5f580ba05fd37f20a04

RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone "$FPUSH_REPO" fpush \
    && cd fpush \
    && git checkout --detach "$FPUSH_COMMIT"

WORKDIR /src/fpush
RUN cargo build --release --locked -p fpush

# --- runtime ---
FROM debian:bookworm-slim

# the APNs client (a2) uses OpenSSL
RUN apt-get update \
    && apt-get install -y --no-install-recommends libssl3 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --home-dir /nonexistent --shell /usr/sbin/nologin fpush

COPY --from=builder /src/fpush/target/release/fpush /usr/local/bin/fpush

USER fpush
ENV RUST_LOG=info
ENTRYPOINT ["/usr/local/bin/fpush", "/etc/fpush/settings.json"]

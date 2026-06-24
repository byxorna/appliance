FROM docker.io/library/rust:1.87-slim-bookworm AS builder

ARG RSRETICULUM_VERSION=v1.0.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libudev-dev libdbus-1-dev git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone --branch ${RSRETICULUM_VERSION} --depth 1 \
    https://github.com/ratspeak/rsReticulum.git .

RUN cargo build --release --bin rnsd-rs --bin rnstatus-rs --bin rnpath-rs

FROM docker.io/library/debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libudev1 libdbus-1-3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/rnsd-rs /usr/local/bin/
COPY --from=builder /build/target/release/rnstatus-rs /usr/local/bin/
COPY --from=builder /build/target/release/rnpath-rs /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/rnsd-rs"]
CMD ["--config", "/etc/rsReticulum"]

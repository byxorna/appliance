ARG RUST_VERSION=1.96
FROM docker.io/library/rust:${RUST_VERSION}-slim-bookworm AS builder

ARG RSLXMF_VERSION=v1.0.0
ARG RSRETICULUM_VERSION=v1.0.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config libudev-dev libdbus-1-dev git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --branch ${RSRETICULUM_VERSION} --depth 1 \
    https://github.com/ratspeak/rsReticulum.git /rsReticulum

WORKDIR /build
RUN git clone --branch ${RSLXMF_VERSION} --depth 1 \
    https://github.com/ratspeak/rsLXMF.git .

RUN cargo build --release --bin lxmd-rs

FROM docker.io/library/debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libudev1 libdbus-1-3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/release/lxmd-rs /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/lxmd-rs"]
CMD ["--config", "/etc/rsLXMF", "--rnsconfig", "/etc/rsReticulum", "--propagation-node"]

FROM docker.io/library/ubuntu:24.04

ARG RATSPEAK_VERSION=1.0.20

# TODO: validate .deb checksum against published SHA256SUMS
ADD https://github.com/ratspeak/Ratspeak/releases/download/v${RATSPEAK_VERSION}/Ratspeak-v${RATSPEAK_VERSION}-linux-arm64.deb /tmp/ratspeak.deb
RUN apt-get update && apt-get install -y --no-install-recommends \
    /tmp/ratspeak.deb \
    libasound2t64 \
    libpcsclite1 \
    && rm -rf /var/lib/apt/lists/* /tmp/ratspeak.deb

USER 810:810
ENTRYPOINT ["/usr/bin/ratspeak"]

FROM docker.io/library/ubuntu:22.04

ARG BUILDER_UID=1000
ARG BUILDER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Yocto scarthgap host dependencies
# https://docs.yoctoproject.org/ref-manual/system-requirements.html#required-packages-for-the-build-host
RUN apt-get update && apt-get install -y --no-install-recommends \
    gawk wget git diffstat unzip texinfo gcc build-essential \
    chrpath socat cpio python3 python3-pip python3-pexpect \
    xz-utils debianutils iputils-ping python3-git python3-jinja2 \
    python3-subunit zstd liblz4-tool file locales libacl1 \
    lz4 vim tmux bash-completion ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# UTF-8 locale (Yocto fetch tools require it)
RUN locale-gen en_US.UTF-8

# kas (Yocto build orchestrator)
RUN pip3 install --no-cache-dir kas

# Non-root builder user with configurable UID/GID
# Use -o to allow reusing an existing GID (e.g. macOS GID 20 = dialout in Ubuntu)
RUN groupadd -o -g ${BUILDER_GID} builder \
    && useradd -m -o -u ${BUILDER_UID} -g ${BUILDER_GID} -s /bin/bash builder

USER builder
WORKDIR /workspace

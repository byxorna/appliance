SUMMARY = "Reticulum transport and LXMF relay services (containerized)"
DESCRIPTION = "Headless services for rnsd-rs (Reticulum transport daemon) \
and lxmd-rs (LXMF propagation node). Both run as OCI containers managed by \
podman via Quadlet .kube units. Ships default configs and data directory layout."
HOMEPAGE = "https://github.com/ratspeak/rsReticulum"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMMUNITY_NODES_URL = "https://codeberg.org/latticeworks/wiki/raw/branch/main/resources/reticulum/community_nodes_list"

SRC_URI = " \
    file://rnsd.kube \
    file://lxmd.kube \
    file://rnsd-pod.yaml \
    file://lxmd-pod.yaml \
    file://reticulum-config.template \
    file://lxmf-config \
    file://appliance-reticulum-data.conf \
"

S = "${WORKDIR}"

do_compile() {
    cp ${WORKDIR}/reticulum-config.template ${WORKDIR}/reticulum-config

    if command -v wget >/dev/null 2>&1; then
        wget -q -O ${WORKDIR}/community_nodes "${COMMUNITY_NODES_URL}" || true
    fi

    if [ -s ${WORKDIR}/community_nodes ]; then
        grep -v '^#' ${WORKDIR}/community_nodes | grep -v '^$' | \
            grep -v '^## ' >> ${WORKDIR}/reticulum-config
    fi
}

do_install() {
    install -d ${D}${sysconfdir}/containers/systemd
    install -m 0644 ${WORKDIR}/rnsd.kube \
        ${D}${sysconfdir}/containers/systemd/rnsd.kube
    install -m 0644 ${WORKDIR}/lxmd.kube \
        ${D}${sysconfdir}/containers/systemd/lxmd.kube

    install -d ${D}${datadir}/appliance-reticulum
    install -m 0644 ${WORKDIR}/rnsd-pod.yaml \
        ${D}${datadir}/appliance-reticulum/rnsd-pod.yaml
    install -m 0644 ${WORKDIR}/lxmd-pod.yaml \
        ${D}${datadir}/appliance-reticulum/lxmd-pod.yaml
    install -m 0644 ${WORKDIR}/reticulum-config \
        ${D}${datadir}/appliance-reticulum/reticulum-config.default
    install -m 0644 ${WORKDIR}/lxmf-config \
        ${D}${datadir}/appliance-reticulum/lxmf-config.default

    install -d ${D}${nonarch_libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/appliance-reticulum-data.conf \
        ${D}${nonarch_libdir}/tmpfiles.d/appliance-reticulum-data.conf
}

RDEPENDS:${PN} = "podman"

FILES:${PN} += " \
    ${sysconfdir}/containers/systemd \
    ${datadir}/appliance-reticulum \
    ${nonarch_libdir}/tmpfiles.d/appliance-reticulum-data.conf \
"

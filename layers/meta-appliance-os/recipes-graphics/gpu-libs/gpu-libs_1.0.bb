SUMMARY = "GPU library directory for container bind-mounting"
DESCRIPTION = "Creates /usr/lib/gpu/ containing copies of Mesa, libdrm, \
and DRI driver .so files. Containers mount this directory read-only so \
they can use the host GPU stack without exposing all of /usr/lib (which \
would poison container binaries with incompatible host glibc)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "mesa libdrm vulkan-loader"
RDEPENDS:${PN} = "mesa-megadriver libdrm vulkan-loader"

GPU_LIBDIR = "${libdir}/gpu"

do_install() {
    install -d ${D}${GPU_LIBDIR}
    install -d ${D}${GPU_LIBDIR}/dri

    # Mesa DRI drivers (vc4, v3d, kmsro, etc.)
    for f in ${STAGING_LIBDIR}/dri/*_dri.so; do
        [ -e "$f" ] || continue
        install -m 0755 "$f" ${D}${GPU_LIBDIR}/dri/
    done

    # Mesa + libdrm shared libraries
    for pattern in \
        libEGL.so.* \
        libGLESv2.so.* \
        libgbm.so.* \
        libglapi.so.* \
        libdrm.so.* libdrm_*.so.* \
        libvulkan.so.* \
    ; do
        for f in ${STAGING_LIBDIR}/${pattern}; do
            [ -e "$f" ] || continue
            [ -L "$f" ] && continue
            install -m 0755 "$f" ${D}${GPU_LIBDIR}/
            base=$(basename "$f")
            # Create soname symlink (e.g. libEGL.so.1 -> libEGL.so.1.0.0)
            soname=$(${READELF} -d "$f" 2>/dev/null | sed -n 's/.*SONAME.*\[\(.*\)\]/\1/p')
            if [ -n "$soname" ] && [ "$soname" != "$base" ]; then
                ln -sf ${base} ${D}${GPU_LIBDIR}/${soname}
            fi
        done
    done
}

PRIVATE_LIBS = "\
    libEGL.so.1 \
    libGLESv2.so.2 \
    libgbm.so.1 \
    libglapi.so.0 \
    libvulkan.so.1 \
    libdrm.so.2 \
    libdrm_nouveau.so.2 \
    libdrm_radeon.so.1 \
    libdrm_amdgpu.so.1 \
    libdrm_intel.so.1 \
    libdrm_freedreno.so.1 \
    libdrm_omap.so.1 \
    libdrm_etnaviv.so.1 \
"
INSANE_SKIP:${PN} = "already-stripped dev-so"
FILES:${PN} = "${GPU_LIBDIR}"

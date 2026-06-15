SUMMARY = "GPU library directory for container bind-mounting"
DESCRIPTION = "Creates /usr/lib/gpu/ containing copies of Mesa, libdrm, \
and DRI driver .so files. Containers mount this directory read-only so \
they can use the host GPU stack without exposing all of /usr/lib (which \
would poison container binaries with incompatible host glibc)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "mesa libdrm vulkan-loader wayland"
RDEPENDS:${PN} = "mesa-megadriver libdrm vulkan-loader"

GPU_LIBDIR = "${libdir}/gpu"

do_install() {
    install -d ${D}${GPU_LIBDIR}
    install -d ${D}${GPU_LIBDIR}/dri
    install -d ${D}${GPU_LIBDIR}/gbm

    # Mesa DRI drivers (vc4, v3d, kmsro, etc.)
    for f in ${STAGING_LIBDIR}/dri/*_dri.so; do
        [ -e "$f" ] || continue
        install -m 0755 "$f" ${D}${GPU_LIBDIR}/dri/
    done

    # GBM backend (dri_gbm.so) -- Mesa 25.x loads this from <libdir>/gbm/
    for f in ${STAGING_LIBDIR}/gbm/*_gbm.so; do
        [ -e "$f" ] || continue
        install -m 0755 "$f" ${D}${GPU_LIBDIR}/gbm/
    done

    # Mesa + libdrm shared libraries
    for pattern in \
        libEGL.so.* \
        libGLESv2.so.* \
        libgbm.so.* \
        libglapi.so.* \
        libdrm.so.* libdrm_*.so.* \
        libvulkan.so.* \
        libgallium*.so* \
        libwayland-server.so.* \
        libwayland-client.so.* \
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

# These are copies of real shared libraries placed in a non-standard path
# (/usr/lib/gpu/) for container bind-mounting. OE's packaging QA is not
# designed for this pattern.

# Don't register as a provider of libdrm.so.2, libgbm.so.1, etc.
EXCLUDE_FROM_SHLIBS = "1"
# Don't auto-generate RDEPENDS from DT_NEEDED entries
INHIBIT_SHLIBDEPS = "1"
# Don't strip binaries (they're already stripped by the source package)
INHIBIT_PACKAGE_STRIP = "1"
# Don't split debug symbols into a -dbg package
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
# Skip QA checks that fire on ELF files in non-standard paths
INSANE_SKIP:${PN} = "already-stripped dev-so file-rdeps libdir ldflags textrel useless-rpaths"
FILES:${PN} = "${GPU_LIBDIR}"

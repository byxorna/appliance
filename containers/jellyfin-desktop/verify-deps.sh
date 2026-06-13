#!/bin/sh
set -eu

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  LD_SONAME=ld-linux-x86-64.so.2 ;;
    aarch64) LD_SONAME=ld-linux-aarch64.so.1 ;;
    *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

APPDIR=/opt/jellyfin-desktop
INTERP="${APPDIR}/usr/lib/${LD_SONAME}"

if [ ! -f "$INTERP" ]; then
    echo "FATAL: bundled linker missing: $INTERP" >&2
    ls -la "$APPDIR/usr/lib/" | grep ld >&2 || echo "(no ld-* files found)" >&2
    exit 1
fi

RESULT=$(
    export LD_LIBRARY_PATH="${APPDIR}/usr/lib:${APPDIR}/usr/bin"
    "$INTERP" --list "${APPDIR}/usr/bin/jellyfin-desktop" 2>&1 || true
)

echo "$RESULT"

FAIL=0
# GPU/Mesa libs are stripped from the AppDir and bind-mounted from the host
# at runtime. Filter them out so they don't cause false failures here.
HOST_GPU_LIBS="libEGL\.so|libEGL_mesa\.so|libgbm\.so|libGLESv2\.so|libglapi\.so|libGLdispatch\.so|libdrm\.so|libdrm_|libxshmfence\.so|libOpenGL\.so|libGL\.so|libGLX\.so|libGLX_mesa\.so|libGLESv1_CM\.so|libvulkan\.so"
FILTERED=$(echo "$RESULT" | grep -iE 'not found|cannot open|error while loading' | grep -vE "$HOST_GPU_LIBS" || true)
if [ -n "$FILTERED" ]; then
    echo "" >&2
    echo "FATAL: unresolved libraries in jellyfin-desktop:" >&2
    echo "$FILTERED" >&2
    FAIL=1
fi

GPU_MISSING=$(echo "$RESULT" | grep -iE 'not found|cannot open|error while loading' | grep -E "$HOST_GPU_LIBS" || true)
if [ -n "$GPU_MISSING" ]; then
    echo ""
    echo "OK (host-provided at runtime):"
    echo "$GPU_MISSING"
fi

if [ "$FAIL" -eq 1 ]; then
    exit 1
fi

echo "All runtime dependencies resolved."

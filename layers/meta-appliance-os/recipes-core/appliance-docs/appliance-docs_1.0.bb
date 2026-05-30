SUMMARY = "On-device manpages built from docs/*.md and README.md"
DESCRIPTION = "Converts project Markdown documentation to section 7 manpages \
at build time using a lightweight Python converter (no pandoc, no go-md2man). \
The appliance is self-replicating: everything needed to understand, rebuild, \
reflash, and maintain the system ships on the device itself."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://md2man.py"

inherit qemu

S = "${WORKDIR}"

# Source docs keyed by manpage name.  TODO-*.md are excluded (dev-only).
DOCS_DIR = "${REPO_ROOT}/docs"

python do_compile() {
    import subprocess, glob, os

    md2man = os.path.join(d.getVar("S"), "md2man.py")
    docs_dir = d.getVar("DOCS_DIR")
    repo_root = d.getVar("REPO_ROOT")
    outdir = os.path.join(d.getVar("B"), "man7")
    os.makedirs(outdir, exist_ok=True)

    # Map of source file -> manpage name
    pages = {}

    # docs/*.md -> appliance-<stem>(7), excluding TODO-*
    for md in sorted(glob.glob(os.path.join(docs_dir, "*.md"))):
        stem = os.path.splitext(os.path.basename(md))[0]
        if stem.startswith("TODO"):
            continue
        pages[md] = f"appliance-{stem}"

    # README.md -> appliance(7)
    readme = os.path.join(repo_root, "README.md")
    if os.path.exists(readme):
        pages[readme] = "appliance"

    for src, name in pages.items():
        out = os.path.join(outdir, f"{name}.7")
        bb.note(f"md2man: {src} -> {out}")
        subprocess.check_call([
            "python3", md2man, src, name, "7"
        ], stdout=open(out, "w"))
}

do_install() {
    install -d ${D}${mandir}/man7
    for f in ${B}/man7/*.7; do
        install -m 0644 "$f" ${D}${mandir}/man7/
    done
}

# Keep manpages in the main package, not the -doc split.
FILES:${PN} = "${mandir}"
PACKAGES = "${PN}"

# Pre-build the mandb whatis cache at image build time so man -k works
# on the read-only rootfs without needing to run mandb on the device.
pkg_postinst:${PN} () {
	if test -n "$D"; then
		if ${@bb.utils.contains('MACHINE_FEATURES', 'qemu-usermode', 'true', 'false', d)}; then
			$INTERCEPT_DIR/postinst_intercept update_mandb ${PKG} mlprefix=${MLPREFIX} binprefix=${MLPREFIX} bindir=${bindir} sysconfdir=${sysconfdir} mandir=${mandir}
		else
			$INTERCEPT_DIR/postinst_intercept delay_to_first_boot ${PKG} mlprefix=${MLPREFIX}
		fi
	else
		mandb -q
	fi
}

RDEPENDS:${PN} = "man-db"

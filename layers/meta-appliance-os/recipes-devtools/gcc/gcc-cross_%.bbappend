# GCC 13 has a parallel build race on aarch64: auto-generated source files
# (insn-recog.cc, insn-output.cc, etc.) may not be ready when the linker
# tries to build cc1/cc1plus, causing undefined-reference errors.
# Limiting PARALLEL_MAKE for this recipe works around the race.
PARALLEL_MAKE = "-j 2"

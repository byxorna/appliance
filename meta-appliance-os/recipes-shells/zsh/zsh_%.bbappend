# The upstream zsh recipe declares LICENSE = "zsh" which has no matching
# common-licenses text, causing do_create_spdx to fail. The zsh license
# is a permissive MIT-style license. Map it so SPDX generation works.
LICENSE = "MIT-like"
NO_GENERIC_LICENSE[MIT-like] = "LICENCE"

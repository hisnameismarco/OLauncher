#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
plugin_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
qsb_bin=${QSB:-/usr/lib/qt6/bin/qsb}
"$qsb_bin" --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o "$plugin_root/assets/spotlight_mode_field.frag.qsb" \
  "$plugin_root/assets/spotlight_mode_field.frag"

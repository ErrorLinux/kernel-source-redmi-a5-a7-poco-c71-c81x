#!/usr/bin/env bash
# Repack out/Image into an AVB-preserving boot image with the permissive cmdline.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="${1:?usage: $0 <stock-boot.img> [output-boot.img]}"
OUT="${2:-${ROOT}/out/boot/boot_serenity_custom_mglru_tuned.img}"

cd "${ROOT}"
mkdir -p out/boot

python3 serenity/tools/boottool.py repack \
    "${BASE}" out/Image "${OUT}" \
    --mode keepavb \
    --append 'androidboot.selinux=permissive enforcing=0'

python3 serenity/tools/boottool.py info "${OUT}" | head -25
sha256sum out/Image "${OUT}"

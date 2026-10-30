#!/usr/bin/env bash
# Clean rebuild of the patched serenity kernel using ThinLTO instead of Full LTO.
#
# The arm64 Image target still has to link a vmlinux (Image is produced by
# objcopy from it), but ThinLTO performs the LTO codegen in parallel and needs
# much less RAM than Full LTO, so it can finish on this 4 GB host.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG_DIR="${CLANG_DIR:-$HOME/clang-r450784e}"
JOBS="${JOBS:-2}"
LD_OPT="${LD_OPT:--O1}"

if [[ ! -x "${CLANG_DIR}/bin/clang" ]]; then
    echo "clang not found at ${CLANG_DIR}" >&2
    exit 1
fi

export PATH="${CLANG_DIR}/bin:${PATH}"
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu-

printf '%s\n' '-android13-8-00019-gf4321180a397' > "${ROOT}/.scmversion"
export BUILD_NUMBER=15212794
export KBUILD_BUILD_USER=build-user
export KBUILD_BUILD_HOST=build-host
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="Wed Apr 15 01:39:41 UTC 2026"

cd "${ROOT}"

LOG="${LOG:-/tmp/serenity-thin.log}"
exec >>"${LOG}" 2>&1

echo "=== clean rebuild start: $(date -Is) ==="
echo "JOBS=${JOBS} LD=ld.lld ${LD_OPT}"

# Remove every full-LTO object from the interrupted attempt.
make clean

# Stock GKI ABI: keep struct module layout even with BTF off.
if ! grep -q 'Keep these fields even when BTF is disabled' include/linux/module.h; then
    patch -p1 --forward < serenity/0001-module-keep-btf-tail-fields.patch
fi

# Optional thermal_sys.off=1 boot parameter.
if ! grep -q 'module_param_named(off, thermal_off' drivers/thermal/thermal_core.c; then
    patch -p1 --forward < serenity/0002-thermal-off-param.patch
fi

# Defensive MGLRU fix for clear_mm_walk().
if ! grep -q 'is_pgdat_mm_walk' mm/vmscan.c; then
    patch -p1 --forward < serenity/0003-lru-gen-guard-clear-mm-walk.patch
fi

# Validate the task walk in set_mm_walk() too.
if ! grep -q 'is_task_mm_walk' mm/vmscan.c; then
    patch -p1 --forward < serenity/0004-lru-gen-harden-mm-walk.patch
fi

make -s ARCH=arm64 LLVM=1 serenity_defconfig

scripts/config --file .config \
    --disable DEBUG_INFO \
    --disable DEBUG_INFO_BTF \
    --disable DEBUG_INFO_BTF_MODULES \
    --enable LRU_GEN \
    --enable LRU_GEN_ENABLED \
    --enable MQ_IOSCHED_KYBER \
    --enable CRYPTO_LZ4HC \
    --enable SECURITY_SELINUX_BOOTPARAM \
    --disable LTO_CLANG_FULL \
    --enable LTO_CLANG_THIN

make -s ARCH=arm64 LLVM=1 olddefconfig

echo "=== config check ==="
grep -E '^(CONFIG_LTO|CONFIG_CFI_CLANG|CONFIG_LRU_GEN|CONFIG_MQ_IOSCHED_KYBER|CONFIG_CRYPTO_LZ4HC|CONFIG_DEBUG_INFO)' .config || true

# ThinLTO still creates vmlinux, but the link is parallel and much lighter.
make -j"${JOBS}" LD="ld.lld ${LD_OPT}" Image

mkdir -p out
cp -f arch/arm64/boot/Image out/Image
echo "=== clean rebuild done: $(date -Is) ==="
ls -lh --time-style=long-iso out/Image arch/arm64/boot/Image
sha256sum out/Image
make -s ARCH=arm64 LLVM=1 kernelrelease

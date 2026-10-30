#!/usr/bin/env bash
# Build a serenity kernel with MGLRU kept enabled plus the safe VM/IO knobs.
#
# What this script changes in the kernel image:
#   - CONFIG_LRU_GEN=y, CONFIG_LRU_GEN_ENABLED=y (full MGLRU)
#   - CONFIG_MQ_IOSCHED_KYBER=y (already in serenity_defconfig)
#   - CONFIG_CRYPTO_LZ4HC=y (already in serenity_defconfig)
#   - 0003/0004 guard: never kfree() the static pgdat->mm_walk or a stale
#     reclaim_state->mm_walk pointer, and never inherit an unowned walk in
#     set_mm_walk() (0004 supersedes the guard added by 0003)
#
# Runtime tuning (zram size/algorithm, read_ahead_kb=64, kyber, optional CPU
# performance) lives in the separate Magisk/KernelSU module, not here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG_DIR="${CLANG_DIR:-$HOME/clang-r450784e}"
JOBS="${JOBS:-$(nproc)}"
NO_DEBUG_INFO="${NO_DEBUG_INFO:-1}"
LD_OPT="${LD_OPT:--O1}"

if [[ ! -x "${CLANG_DIR}/bin/clang" ]]; then
    echo "clang not found at ${CLANG_DIR}" >&2
    echo "set CLANG_DIR to an AOSP clang-r450784e checkout" >&2
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

# Validate the task walk in set_mm_walk() too, so a stale or corrupted
# reclaim_state->mm_walk is dropped instead of being dereferenced or freed.
if ! grep -q 'is_task_mm_walk' mm/vmscan.c; then
    patch -p1 --forward < serenity/0004-lru-gen-harden-mm-walk.patch
fi

make -s ARCH=arm64 LLVM=1 serenity_defconfig

if [[ "${NO_DEBUG_INFO}" == "1" ]]; then
    scripts/config --file .config \
        --disable DEBUG_INFO \
        --disable DEBUG_INFO_BTF \
        --disable DEBUG_INFO_BTF_MODULES
fi

# Keep MGLRU on, keep the stock GKI feature set, make kyber selectable at
# runtime (it is already built-in, this also covers a stale defconfig).
scripts/config --file .config \
    --enable LRU_GEN \
    --enable LRU_GEN_ENABLED \
    --enable MQ_IOSCHED_KYBER \
    --enable CRYPTO_LZ4HC \
    --enable SECURITY_SELINUX_BOOTPARAM

make -s ARCH=arm64 LLVM=1 olddefconfig

# Full LTO is memory hungry.  -O1 keeps the link inside a 4 GiB host.
make -j"${JOBS}" LD="ld.lld ${LD_OPT}" Image

if [[ "${BUILD_MODULES:-0}" == "1" ]]; then
    make -j"${JOBS}" LD="ld.lld ${LD_OPT}" modules
fi

mkdir -p out
cp -f arch/arm64/boot/Image out/Image
echo
echo "Image: out/Image"
make -s ARCH=arm64 LLVM=1 kernelrelease

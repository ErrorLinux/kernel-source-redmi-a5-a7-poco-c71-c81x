#!/usr/bin/env bash
# Build the GKI kernel Image for Xiaomi Redmi A5 / POCO C71 (serenity).
#
# The stock kernel is GKI 5.15.194 from android.googlesource.com/kernel/common,
# commit f4321180a397.  The tree in this directory is the exact source archive
# of that commit, with the stock .config recovered from the running kernel and
# saved as arch/arm64/configs/serenity_defconfig.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG_DIR="${CLANG_DIR:-$HOME/clang-r450784e}"
JOBS="${JOBS:-$(nproc)}"

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

# Reproduce the stock release string:
#   5.15.194-android13-8-00019-gf4321180a397-ab15212794
# .scmversion supplies the -android13-8-00019-g... part; BUILD_NUMBER supplies
# the -ab... suffix.  Keeping CONFIG_MODULE_SCMVERSION=y keeps the stock
# /sys/module/<name>/scmversion attribute; struct module layout is handled by
# the compatibility patch below.
printf '%s\n' '-android13-8-00019-gf4321180a397' > "${ROOT}/.scmversion"
export BUILD_NUMBER=15212794
export KBUILD_BUILD_USER=build-user
export KBUILD_BUILD_HOST=build-host
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="Wed Apr 15 01:39:41 UTC 2026"

cd "${ROOT}"

# Keep the stock struct module layout even when DEBUG_INFO_BTF_MODULES is off.
# The factory modules were built with BTF on; many exported-symbol CRCs contain
# struct module through a pointer, so this is required for ABI compatibility.
if ! grep -q 'Keep these fields even when BTF is disabled' include/linux/module.h; then
    patch -p1 --forward < serenity/0001-module-keep-btf-tail-fields.patch
fi

# Optional thermal_sys.off=1 boot parameter.  It is off by default; when
# enabled the thermal core keeps a slow poll but skips temperature/trip
# handling.
if ! grep -q 'module_param_named(off, thermal_off' drivers/thermal/thermal_core.c; then
    patch -p1 --forward < serenity/0002-thermal-off-param.patch
fi

make -s ARCH=arm64 LLVM=1 serenity_defconfig

# Dropping DWARF/BTF is enough to make full LTO link on a 4 GiB host.  It does
# not touch any ABI-affecting option: CFI (and its cfi_check field in struct
# module), LTO, MODVERSIONS and SCMVERSION all stay enabled.
if [[ "${NO_DEBUG_INFO:-0}" == "1" ]]; then
    scripts/config --file .config \
        --disable DEBUG_INFO \
        --disable DEBUG_INFO_BTF \
        --disable DEBUG_INFO_BTF_MODULES
fi

# Serenity tuning.  These are runtime/default knobs only; no exported type or
# symbol layout changes, so the stock GKI module ABI is preserved.
#   LRU_GEN_ENABLED : enable Multi-Gen LRU by default (reclaim/RAM pressure)
#   CRYPTO_LZ4HC    : let zram use lz4hc in addition to lz4/zstd/lzo-rle
#   SELINUX_BOOTPARAM: accept selinux= boot parameter in addition to the
#                      Android androidboot.selinux=permissive property
scripts/config --file .config \
    --enable LRU_GEN_ENABLED \
    --enable CRYPTO_LZ4HC \
    --enable SECURITY_SELINUX_BOOTPARAM
make -s ARCH=arm64 LLVM=1 olddefconfig

# Full LTO at the default -O2 needs a lot of RAM.  On a small host pass
# LD_OPT=-O1 to trade some codegen time for a much smaller working set.
MAKE_ARGS=()
if [[ -n "${LD_OPT:-}" ]]; then
    MAKE_ARGS+=("LD=ld.lld ${LD_OPT}")
fi
make -j"${JOBS}" "${MAKE_ARGS[@]}" Image

if [[ "${BUILD_MODULES:-0}" == "1" ]]; then
    make -j"${JOBS}" "${MAKE_ARGS[@]}" modules
fi

mkdir -p out
cp -f arch/arm64/boot/Image out/Image
echo
echo "Image: out/Image"
make -s ARCH=arm64 LLVM=1 kernelrelease

# Kernel Source for Redmi A5 / Redmi A7 / POCO C71 / POCO C81x

Custom Linux **5.15 GKI** source for the Unisoc **UMS9230** `serenity` platform
(Redmi A5 / POCO C71, with community reports for Redmi A7 / POCO C81x).

Repository: https://github.com/ErrorLinux/kernel-source-redmi-a5-a7-poco-c71-c81x

---

## Important: source provenance

> **This is a reconstructed / reverse-engineered source tree.**
>
> It is **not** an official Xiaomi kernel source release, and it was **not**
> uploaded by Xiaomi. It was assembled from the public Android Common Kernel,
> the stock firmware package, extracted config/DTB/DTBO data, and the patches
> and build scripts in `serenity/`.
>
> The GKI base is the public AOSP `android13-5.15-2025-12` branch at commit
> `f4321180a397`. The device configuration was recovered from the stock
> `boot.img` (`IKCONFIG`/`IKCFG_ST`). The device trees were decompiled from the
> stock `dtb.img` / `dtbo.img`.
>
> The Unisoc vendor modules (Mali GPU, touch, charger, fingerprint, SIPC, ...)
> are proprietary binaries from the stock firmware. They are **not** rebuilt
> from this tree. Keep the stock vendor_boot/vendor_dlkm modules, or obtain the
> Unisoc BSP source separately.
>
> This project is not affiliated with Xiaomi, Redmi, POCO, Unisoc, or Google.
> Flashing custom kernels can brick the device, wipe data, or break verified
> boot. Use at your own risk.

> **Tóm tắt tiếng Việt:** Đây là bản mã nguồn được phục dựng/dịch ngược từ
> firmware và các thành phần của máy, **không phải** bản do Xiaomi phát hành
> hoặc tải lên. Phần GKI dựa trên mã nguồn AOSP công khai; config, DTB/DTBO và
> một số thành phần được trích xuất từ firmware stock. Các module vendor của
> Unisoc vẫn là binary độc quyền, không được build lại từ source này.

The kernel is distributed under **GPL-2.0** (see `COPYING`). The reverse-
engineered device data and patches are provided under the same terms where
applicable. No warranty is provided.

---

## Supported devices

| Marketing name | Platform / board | Notes |
| :--- | :--- | :--- |
| Redmi A5 | `serenity`, UMS9230 | primary target |
| POCO C71 | `serenity`, UMS9230 | primary target |
| Redmi A7 | UMS9230 family | verify DTB/DTBO and vendor modules before flashing |
| POCO C81x | UMS9230 family | verify DTB/DTBO and vendor modules before flashing |

The kernel Image is common GKI code. The **DTB/DTBO and vendor modules are
device-specific**; do not mix images from a different board revision.

---

## Current reference build

Built from this tree with the patched MGLRU source and **ThinLTO** (low-memory
host). Full-LTO builds will work on a larger host but produce a different hash.

| Item | Value |
| :--- | :--- |
| Kernel release | `5.15.194-android13-8-00019-gf4321180a397-ab15212794` |
| Image | `out/Image` (36,022,784 bytes) |
| Image SHA-256 | `40105c82a93787d7671acf1ba21f97dd9f2503da8ef67afb0a02293b43f782c9` |
| Boot image | `out/boot/boot_serenity_mglru_tuned_thin.img` (64 MiB) |
| Boot SHA-256 | `632b87436c2cf708e0c91b1ece51fd068637c18cbcc2f1e656a0be2f3460e657` |
| `module_layout` CRC | `0x0222dd63` (matches stock base) |
| LTO mode | `CONFIG_LTO_CLANG_THIN=y` |
| CFI | `CONFIG_CFI_CLANG=y` |
| MGLRU | `CONFIG_LRU_GEN=y`, `CONFIG_LRU_GEN_ENABLED=y` |

The boot image keeps the stock AVB0/AVBf bytes, but the AVB signature is not
valid for the new kernel. An unlocked bootloader with verified boot disabled is
required.

---

## Features

- Full Multi-Gen LRU (`CONFIG_LRU_GEN_ENABLED=y`, not core-only).
- Defensive MGLRU guards in `clear_mm_walk()` and `set_mm_walk()`:
  - never `kfree()` the static `pgdat->mm_walk`;
  - never free/dereference a stale or invalid `reclaim_state->mm_walk`;
  - only free a live slab object owned by the current task.
- `CONFIG_MQ_IOSCHED_KYBER=y`.
- `CONFIG_CRYPTO_LZ4HC=y` for zram.
- SELinux permissive boot cmdline support (`CONFIG_SECURITY_SELINUX_BOOTPARAM=y`).
- Optional `thermal_sys.off=1` parameter (thermal bypass, off by default).
- Stock GKI module ABI preserved:
  - `CONFIG_CFI_CLANG=y`, `CONFIG_MODVERSIONS=y`, `CONFIG_MODULE_SCMVERSION=y`;
  - `struct module` compatibility patch (`0001`);
  - the reference build's `module_layout` CRC matches the stock base.

Runtime zram/sysctl/scheduler tuning is **not** baked into the kernel. It lives
in the optional Magisk/KernelSU module under `serenity/tuning/`.

---

## Repository layout

```
.
├── arch/arm64/configs/serenity_defconfig   # stock GKI config
├── configs/serenity_mglru_tuned.config     # reference patched ThinLTO config
├── serenity/
│   ├── 0001-module-keep-btf-tail-fields.patch
│   ├── 0002-thermal-off-param.patch
│   ├── 0003-lru-gen-guard-clear-mm-walk.patch
│   ├── 0004-lru-gen-harden-mm-walk.patch
│   ├── tools/boottool.py                    # AVB-preserving boot repacker
│   ├── tools/extract-ikconfig.py
│   ├── tuning/                              # optional Magisk/KernelSU module
│   ├── stock.config                         # config extracted from stock image
│   ├── dtb.dts / dtbo.dts                   # decompiled stock device trees
│   └── ...
├── build-serenity-thin.sh                   # clean ThinLTO build (4 GB host)
├── build-serenity-mglru-tuned.sh            # full-LTO MGLRU build (large host)
├── build-serenity.sh                        # base GKI build
├── repack-serenity-mglru-tuned.sh           # boot.img repacker
├── configs/
└── README.md
```

The original AOSP `README` is left in place. The project README is this file.

---

## Requirements

Recommended host:

- x86_64 Linux (Debian/Ubuntu/Deepin tested);
- **16 GiB RAM** for full LTO;
- **4 GiB RAM is possible** with ThinLTO + `JOBS=2` (slow but tested);
- 20 GiB free disk;
- AOSP clang **r450784e** (Android 13 / clang 14.0.7);
- Python 3, GNU make, `bc`, `bison`, `flex`, `libssl-dev`, `libelf-dev`;
- `adb`/`fastboot` for flashing.

Example packages (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install -y build-essential git python3 bc bison flex \
  libssl-dev libelf-dev libncurses-dev zip unzip curl \
  device-tree-compiler adb fastboot gcc-aarch64-linux-gnu
```

Get clang r450784e and point `CLANG_DIR` at it:

```bash
export CLANG_DIR="$HOME/clang-r450784e"
test -x "$CLANG_DIR/bin/clang" || {
  echo "Download AOSP clang-r450784e and set CLANG_DIR"; exit 1;
}
```

The AOSP toolchain is available from the Android prebuilt repository; the exact
revision used here is `clang-r450784e` (Android 13, clang 14.0.7). The kernel
build itself uses `LLVM=1` and `LLVM_IAS=1`.

---

## Quick build

Clone the repository:

```bash
git clone https://github.com/ErrorLinux/kernel-source-redmi-a5-a7-poco-c71-c81x.git
# SSH alternative:
# git clone git@github.com:ErrorLinux/kernel-source-redmi-a5-a7-poco-c71-c81x.git

cd kernel-source-redmi-a5-a7-poco-c71-c81x
export CLANG_DIR="$HOME/clang-r450784e"
```

### Option A: low-memory ThinLTO (recommended for 4 GB hosts)

```bash
JOBS=2 ./build-serenity-thin.sh
```

This script:

1. runs `make clean`;
2. applies the ABI/thermal/MGLRU patches if needed;
3. generates a fresh `serenity_defconfig`;
4. enables full MGLRU, kyber and lz4hc;
5. switches from Full LTO to **ThinLTO**;
6. builds `Image` and copies it to `out/Image`.

It keeps `CONFIG_CFI_CLANG=y`; the `module_layout` CRC remains compatible with
the stock vendor modules.

### Option B: full-LTO MGLRU build (large host)

```bash
make clean
JOBS=$(nproc) ./build-serenity-mglru-tuned.sh
```

This leaves the stock **Full LTO** mode enabled. Full LTO needs much more RAM
and can take a long time on a 4 GB machine. If the link is killed, use Option A.

### Why is `vmlinux` still required?

On arm64, `Image` is produced by `objcopy` from the linked `vmlinux`:

```text
objects -> vmlinux.o -> vmlinux -> arch/arm64/boot/Image
```

There is no supported way to produce a bootable `Image` without linking
`vmlinux`. The low-memory strategy is **ThinLTO**, not skipping the link.

---

## Manual build

```bash
make clean

export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu-
export PATH="$CLANG_DIR/bin:$PATH"

make -s ARCH=arm64 LLVM=1 serenity_defconfig

# Keep the stock GKI feature set and enable MGLRU / zram / kyber.
scripts/config --file .config \
  --enable LRU_GEN \
  --enable LRU_GEN_ENABLED \
  --enable MQ_IOSCHED_KYBER \
  --enable CRYPTO_LZ4HC \
  --enable SECURITY_SELINUX_BOOTPARAM \
  --disable DEBUG_INFO \
  --disable DEBUG_INFO_BTF \
  --disable DEBUG_INFO_BTF_MODULES

# Optional: low-memory ThinLTO instead of Full LTO.
scripts/config --file .config \
  --disable LTO_CLANG_FULL \
  --enable LTO_CLANG_THIN

make -s ARCH=arm64 LLVM=1 olddefconfig
make -j2 LD="ld.lld -O1" Image

mkdir -p out
cp arch/arm64/boot/Image out/Image
```

For a reproducible release string, export:

```bash
export BUILD_NUMBER=15212794
export KBUILD_BUILD_USER=build-user
export KBUILD_BUILD_HOST=build-host
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="Wed Apr 15 01:39:41 UTC 2026"
printf '%s\n' '-android13-8-00019-gf4321180a397' > .scmversion
```

Build scripts set these automatically.

---

## Building the Multi-Gen LRU version

MGLRU is enabled by two config options:

```text
CONFIG_LRU_GEN=y
CONFIG_LRU_GEN_ENABLED=y
```

`CONFIG_LRU_GEN_ENABLED=y` enables MGLRU by default at boot. At runtime:

```bash
cat /sys/kernel/mm/lru_gen/enabled
# expected on this arm64 build: 0x0003
```

The sysfs value is a capability bitmask, not a boolean:

| Bit | Value | Capability |
| :--- | :--- | :--- |
| 0 | `0x0001` | `LRU_GEN_CORE` |
| 1 | `0x0002` | `LRU_GEN_MM_WALK` |
| 2 | `0x0004` | `LRU_GEN_NONLEAF_YOUNG` |

`0x0003` means core + MM walk, which is **full MGLRU for this kernel**.
`0x0001` is core-only. `0x0007` would require
`CONFIG_ARCH_HAS_NONLEAF_PMD_YOUNG`, which is not enabled in this arm64
config. Writing `y` requests all capabilities; the kernel only displays the
ones it supports.

### Apply the guards to a fresh stock tree

The patches are already applied in this repository. If you start from an
unpatched GKI tree, apply them in order:

```bash
patch -p1 < serenity/0003-lru-gen-guard-clear-mm-walk.patch
patch -p1 < serenity/0004-lru-gen-harden-mm-walk.patch
```

`0004` builds on `0003`; apply `0003` first.

What they do:

- `clear_mm_walk()` checks whether the walk is the static per-node
  `&pgdat->mm_walk`, invalid, or not a slab object before calling `kfree()`.
- `set_mm_walk()` drops a stale `reclaim_state->mm_walk` instead of inheriting
  and later freeing it.
- A warning is emitted if an invalid walk is dropped:

```text
lru_gen: dropping invalid mm_walk <ptr>
```

This is a defensive fix. It prevents the observed `kfree()` panic, but it does
not repair the vendor reclaim path that corrupted `reclaim_state` originally.

### Verify the patch is in the built image

```bash
strings arch/arm64/boot/Image | grep 'dropping invalid mm_walk'
```

### Build MGLRU

Use either:

```bash
# Clean ThinLTO build with MGLRU, best for 4 GB
JOBS=2 ./build-serenity-thin.sh
```

or:

```bash
# Full LTO build with MGLRU, needs more RAM
make clean
JOBS=$(nproc) ./build-serenity-mglru-tuned.sh
```

### Runtime zram warning

The old crash was triggered by **4 GB zram + lz4** on a 4 GB phone. That is too
aggressive. Use about 50% of RAM (~2 GB) with `lz4hc`, and never reset a live
zram device. The optional tuning module does this only when zram is
unconfigured.

---

## Repack the boot image

Use the stock `boot.img` from the matching firmware package as the base:

```bash
./repack-serenity-mglru-tuned.sh \
  /path/to/stock/boot.img \
  out/boot/boot_serenity_mglru_tuned_thin.img
```

The script uses `serenity/tools/boottool.py` to preserve the AVB0/AVBf layout
and append:

```text
androidboot.selinux=permissive enforcing=0
```

Inspect the result:

```bash
python3 serenity/tools/boottool.py info out/boot/boot_serenity_mglru_tuned_thin.img
```

The stock AVB signature is not valid for the new kernel. Flash with an unlocked
bootloader and verified boot disabled.

---

## Flash

```bash
adb reboot bootloader
fastboot flash boot out/boot/boot_serenity_mglru_tuned_thin.img
fastboot reboot
```

Or in TWRP/OrangeFox:

```text
Install -> Install Image -> select the boot image -> Boot
```

Keep a known-good stock `boot.img` for recovery. If the device bootloops,
reflash the stock boot image from fastboot or recovery.

---

## Optional runtime tuning module

Source is in `serenity/tuning/` (Magisk/KernelSU). Build a zip if needed:

```bash
cd serenity/tuning
zip -r ../../serenity_tuning-v1.0.zip .
```

It applies:

| Knob | Value |
| :--- | :--- |
| `vm.swappiness` | `100` |
| `vm.page-cluster` | `0` |
| `vm.watermark_scale_factor` | `200` |
| `vm.vfs_cache_pressure` | `100` |
| `vm.dirty_ratio` / `dirty_background_ratio` | `20` / `5` |
| `lru_gen/enabled` | `y` (sysfs shows `0x0003` on this build: full supported MGLRU) |
| zram0 | 50% of RAM, `lz4hc`, only if unconfigured |
| `read_ahead_kb` | `64` on real block devices |
| scheduler | `kyber` if available |
| CPU governor | `schedutil`; `performance` opt-in |

`lz4hc` is the high-compression variant of LZ4: it compresses **slower** than
`lz4` and usually produces a better ratio; decompression is still fast. It was
chosen here for zram footprint, not for speed. If you prefer lower latency over
compression ratio, change `lz4hc` to `lz4` in the module and reboot.

Remove or disable `zram_12gb_fix` and any old `serenity_tweaks` line that writes
`1` to `lru_gen/enabled` (that is `0x0001`, core-only).

Some stock ROMs overwrite `vm.swappiness` from vendor init at boot completion.
On the stock serenity firmware, `init.ram.gms.rc` writes `150`; that can win
over the module's `100`. Check after boot and reapply if needed.

---

## Verify after boot

```bash
uname -r
# 5.15.194-android13-8-00019-gf4321180a397-ab15212794

cat /sys/kernel/mm/lru_gen/enabled
# 0x0003 on this kernel (full supported MGLRU)

cat /sys/block/zram0/comp_algorithm
cat /sys/block/zram0/disksize

cat /proc/sys/vm/swappiness
# module wants 100; some stock vendor init scripts overwrite it with 150

cat /sys/block/mmcblk0/queue/read_ahead_kb
cat /sys/block/mmcblk0/queue/scheduler

dmesg | grep 'dropping invalid mm_walk'
```

`dmesg` showing the guard warning means the guard is working, but the vendor
reclaim path is still producing bad pointers; report the log if it repeats.

---

## Troubleshooting

### Build killed at `LTO vmlinux.o`

- Use `build-serenity-thin.sh` with `JOBS=2`.
- Keep `LD_OPT=-O1`.
- Close memory-heavy applications.
- Do not run Full LTO on a 4 GB host unless you have enough swap and patience.
- Skipping `vmlinux` is not possible; see above.

### `Image` is not generated

Check that the link actually succeeded:

```bash
tail -50 /tmp/serenity-thin.log
ls -lh arch/arm64/boot/Image vmlinux
```

### Bootloop / vendor modules fail

- Verify you used the correct stock `boot.img` base.
- Keep the stock vendor_boot/vendor_dlkm modules.
- Check `module_layout` CRC against the stock base.
- Restore the stock boot image and capture ylog/pstore.

### AVB / verification error

- Unlock the bootloader.
- Disable verified boot / flash a disabled vbmeta according to your device
  recovery procedure.
- The repacker preserves AVB bytes but cannot re-sign Xiaomi's AVB key.

### 4 GB zram crash

Do not use 4 GB zram on a 4 GB device. Use ~2 GB and `lz4hc`; remove old
`zram_12gb_fix` modules before testing.

---

## Credits

- Android Common Kernel / AOSP GKI 5.15.
- Unisoc UMS9230 platform and the stock `serenity` firmware.
- The stock config, DTB/DTBO and vendor module layout were recovered from the
  factory firmware for interoperability and preservation.
- KernelSU / Magisk module format.

---

## License

The Linux kernel source is licensed under **GPL-2.0**; see `COPYING`.
Patches and original scripts in `serenity/` are provided under the same terms
where applicable. Vendor binaries and device data remain the property of their
respective owners.

**No warranty. Flash at your own risk.**

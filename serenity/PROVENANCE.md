# Provenance and reproduction record

This file records how the kernel identity was established.  Nothing here is a
guess based on the model name; every step is tied to bytes in the factory ROM
or to a public commit.

## 1. The factory artifacts

Factory package: `serenity_global_images_A15.0.32.0.VGWMIXM_15.0`.

| File | SHA-256 |
| :--- | :--- |
| `prebuilts/kernel` (copy of `boot.img` kernel) | `89762cce5bae8c653fabd878ad1f8991b8a63379abbfb3496fd5a7cfd069605e` |
| `serenity/stock.config` (recovered config) | `eb03e6badcccd7841043517a26838ad41473d041c09a72020690648deaf5064b` |

The kernel is at page offset 4096 in `boot.img`; its first 128 bytes and its
size (47,577,600 bytes) match `prebuilts/kernel` exactly.  The boot image is
header version 4 with `kernel_size=47577600` and `ramdisk_size=0`.

## 2. Kernel version

`strings -a prebuilts/kernel` gives:

```
Linux version 5.15.194-android13-8-00019-gf4321180a397-ab15212794
(build-user@build-host)
(Android (8508608, based on r450784e) clang version 14.0.7
 (https://android.googlesource.com/toolchain/llvm-project 4c603efb0cca074e9238af8b4106c30add4418f6),
 LLD 14.0.7)
#1 SMP PREEMPT Wed Apr 15 01:39:41 UTC 2026
```

Decoding the suffix:

| Part | Meaning |
| :--- | :--- |
| `5.15.194` | Linux stable base |
| `-android13-8` | Android 13 GKI, KMI generation 8 |
| `-00019-gf4321180a397` | 19 commits after `v5.15.194`, git `f4321180a397` |
| `-ab15212794` | Android build number 15212794 |
| `build-user@build-host` | `KBUILD_BUILD_USER` / `KBUILD_BUILD_HOST` |
| `Wed Apr 15 01:39:41 UTC 2026` | `KBUILD_BUILD_TIMESTAMP` |
| `clang 14.0.7` | AOSP clang r450784e, build 8508608 |

## 3. The public source commit

Commit page:
`https://android.googlesource.com/kernel/common/+/f4321180a397`

```
commit f4321180a3973d19b626b3eef51871199e4e1fac
parent c51ed0cc2d626bc93cdba91dc5a3e12914c0ed7e
committer xinxin Chen <chenxinxin@xiaomi.corp-partner.google.com>
date Tue Apr 14 18:39:41 2026 -0700
subject BACKPORT: PM: runtime: Do not clear needs_force_resume with enabled runtime PM
```

The parent chain contains `ANDROID: Initialize android13-5.15-2025-12`, which
is the branch named in the stock config path
(`common-android13-5.15-2025-12`).  The exact archive used here is:

```
https://android.googlesource.com/kernel/common/+archive/f4321180a397.tar.gz
SHA-256 0a7bf31e29c22c454312f6dc80084b0594bf71dfe95b3b93352e9c5c2609cb00
```

## 4. The stock config

The image has `CONFIG_IKCONFIG=y`.  `IKCFG_ST` is at `0x17b44a0`, followed by
a gzip stream.  `serenity/tools/extract-ikconfig.py` recovers it.  The result
is `serenity/stock.config`.

After `make ARCH=arm64 LLVM=1 serenity_defconfig`, before the custom tuning
options are applied, the generated `.config` differs from the stock config in
only two lines:

```
CONFIG_PAHOLE_VERSION=123 -> 127            (host pahole version, not target code)
CONFIG_UNUSED_KSYMS_WHITELIST="/mnt/.../abi_symbollist.raw" -> "abi_symbollist.raw"
```

The whitelist file is generated locally from the 37 `android/abi_gki_aarch64*`
lists in the same source commit.  `CONFIG_LOCALVERSION_AUTO=y`,
`CONFIG_MODULE_SCMVERSION=y`, `CONFIG_MODULE_SIG_PROTECT=y`,
`CONFIG_CFI_CLANG=y`, `CONFIG_LTO_CLANG_FULL=y` and every other code-affecting
option are unchanged.

## 5. Reproduction of the release string

The source tree is not a git checkout, so `.scmversion` supplies the SCM part:

```
-android13-8-00019-gf4321180a397
```

`BUILD_NUMBER=15212794` appends `-ab15212794`.  The build script exports the
same user, host, timestamp and version as the stock build.  `make kernelrelease`
and `include/config/kernel.release` both produce:

```
5.15.194-android13-8-00019-gf4321180a397-ab15212794
```

## 6. Toolchain

AOSP clang prebuilt `clang-r450784e`, checked out from
`platform/prebuilts/clang/host/linux-x86` at commit `0081f4e1` (the last commit
before it was removed as unused in March 2024):

```
Android (8508608, based on r450784e) clang version 14.0.7
LLD 14.0.7
```

## 7. Why the DTB and vendor modules are not rebuilt

The GKI Image does not contain the DTB.  `prebuilts/dtb.img` and
`prebuilts/dtbo.img` are Android DTBO tables produced by the Unisoc BSP; they
identify the platform as `sprd,ums9230` and the board as `sprd,serenity-go`.
The GKI source has no `arch/arm64/boot/dts/sprd/ums9230*` files.

The vendor modules are also Unisoc BSP output, not GKI source.  They are split
between two places on the stock device:

* 168 modules in the vendor_boot ramdisk, 65 loaded first (including
  `sipc-core.ko`, `sprd_thermal_ctl.ko`, `sprd_soc_id.ko`);
* 158 modules in vendor_dlkm (151 loaded).

The GKI Image itself only exports GKI symbols.  The ramdisk modules export the
`sblock_*`, `sbuf_*`, `smsg_*` and `sprd_*` symbols that the vendor_dlkm
modules need.  This is why a symbol such as `sblock_get` is absent from the
kernel Image but the vendor modules still load.

## 8. `struct module` and the BTF ABI trap

The stock image contains a `.BTF` section at file offset `0x22e1dfc`
(magic `0xeb9f`, 5,791,461 bytes).  Parsing it shows `struct module` is 960
bytes and contains the two BTF-only tail fields:

```
752  btf_data_size: unsigned int
760  btf_data  : void *
768  jump_entries ...
```

They come from `CONFIG_DEBUG_INFO_BTF_MODULES=y` in the stock config.  Many
exported symbols have types that reach `struct module` through a
`struct module *` (for example `struct kernel_param`, `struct device_driver`,
`struct platform_driver`, `struct mbox_chan` and `struct regmap`).  A build with
BTF disabled therefore produces different CRCs for thousands of symbols, even
though the BTF fields are never used at runtime:

```
module_layout         without BTF 0x4ccd63ed   stock 0x0222dd63
param_ops_uint        without BTF 0x52f43d2f   stock 0x7c75e4a8
```

`serenity/0001-module-keep-btf-tail-fields.patch` keeps those two fields
unconditional.  They are unused padding when BTF is off, but the struct layout
and the whole symbol ABI match the stock build.  The stock `.BTF` and the
factory modules independently confirm both values above.

The DTB, DTBO and vendor `.ko` files stay as stock prebuilts; only the GKI
`Image` is rebuilt.

## 9. Custom changes in this build

The base build was first validated with the exact stock config and the
`struct module` compatibility patch.  The final build then applied:

* `serenity/0002-thermal-off-param.patch` — adds `thermal_sys.off`, default
  `0`, with an opt-in bypass of temperature/trip handling (including critical
  shutdown);
* `CONFIG_LRU_GEN_ENABLED=y` — Multi-Gen LRU enabled by default;
* `CONFIG_CRYPTO_LZ4HC=y` — extra compressor for a rebuilt zram module;
* `CONFIG_SECURITY_SELINUX_BOOTPARAM=y` — permits `selinux=` in addition to
  the Android `androidboot.selinux=permissive` property.

The exported symbol table did not change: `vmlinux.symvers` remains
`eae9668aa309f4427b109ad46f375a6735b8e7e130327bf1e5a2e1d0851097c0`.
The final `out/Image` is 41,679,360 bytes with SHA-256
`cee47fb20e405ea8ba070cbcd8dfeb4d503e49e8419984a8e59355d7baba2676`.

Two boot images were repacked from the stock `boot.img` with
`serenity/tools/boottool.py --mode keepavb`: the normal permissive image and a
variant with `thermal_sys.off=1`.  The stock AVB0/AVBf bytes are retained, but
the AVB signature is not valid for the new kernel; verified boot must be
disabled.

The supplied `aarch64_android13-5.15_kernelsu.ko` is a KernelSU LKM supplied
separately from this source repository.  It is not built into this
Image), has an empty `__versions` section, and passed the official
`check_symbol` check against this `vmlinux` (`rc=0`).  It must be installed via
KernelSU Manager's LKM path, not `insmod`.

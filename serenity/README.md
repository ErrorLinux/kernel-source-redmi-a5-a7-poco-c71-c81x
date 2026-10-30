# Stock kernel evidence

Files here were recovered from the stock factory package, not written by
hand.  They are reference material; the build itself only needs
`arch/arm64/configs/serenity_defconfig` and `.scmversion`.

| File | Source |
| :--- | :--- |
| `stock.config` | the gzip config embedded in `prebuilts/kernel` (`IKCFG_ST` at `0x17b44a0`) |
| `dtb.dts` | `dtc -I dtb -O dts` of the single FDT in `prebuilts/dtb.img` |
| `dtbo.dts` | `dtc -I dtb -O dts` of the single FDT in `prebuilts/dtbo.img` |

The two image files are Android DTBO tables, not raw FDTs.  The 64-byte
header is `dt_table_header`:

```
magic 0xd7b7ab1e, total 141378, header 32, entry 32, count 1,
entries offset 32, page 2048, version 0
```

`tools/unpack-dtbo.py` extracts the FDT; `tools/extract-ikconfig.py` recovers
the config.  Both are re-runnable against the stock package.

The DTB identifies the platform, the DTBO identifies the board:

```
dtb.img  -> model "Spreadtrum UMS9230 1H10 SoC",  compatible "sprd,ums9230"
dtbo.img -> model "Spreadtrum UMS9230 6H10 SERENITY Board",
            compatible "sprd,serenity-go"
```

There is a public Unisoc reference for this silicon in the Motorola
`kernel-sprd` tree (`ums9230-base.dts`, `ums9230-6h10-go-overlay.dts`), but
the stock Xiaomi DTBO is heavily customized and is kept as a prebuilt.  The
kernel Image does not contain the DTB, so replacing the Image does not
require rebuilding the DTB.

## Kernel identity

```
Linux version 5.15.194-android13-8-00019-gf4321180a397-ab15212794
(build-user@build-host) #1 SMP PREEMPT Wed Apr 15 01:39:41 UTC 2026
```

* base: Linux 5.15.194
* Android Common Kernel branch: `android13-5.15-2025-12`
* commit: `f4321180a397` (the last of 19 commits after v5.15.194)
* KMI generation: 8 (`-android13-8`)
* build number: 15212794 (`-ab15212794`)
* compiler: AOSP clang r450784e, Android (8508608) clang 14.0.7

The stock `prebuilts/kernel` is byte-for-byte the kernel inside
`boot.img` at page offset 4096, so the version string and config belong to
the image the device actually boots.

## Module layout

The stock module ecosystem is split across two partitions:

| Source | `.ko` files | loaded first stage | notes |
| :--- | ---: | ---: | :--- |
| vendor_boot ramdisk | 168 | 65 | includes `sipc-core.ko`, `sprd_thermal_ctl.ko`, `sprd_soc_id.ko` |
| vendor_dlkm | 158 | 151 | the `prebuilts/modules` set in the device tree |

107 module names overlap, so 61 ramdisk-only modules (the SIPC/SBU/SMSG and
thermal/soc-id providers) are not in `prebuilts/modules`.  They are essential:
the GKI Image does not export `sblock_get`, `sbuf_read`, `smsg_ch_open`,
`sprd_get_soc_id` or `create_gpu_cooling_device`; the ramdisk modules export
them for the vendor_dlkm modules.  If a rebuilt vendor_boot ramdisk omits
them, vendor_dlkm module loading will fail even with a perfectly valid GKI
Image.

## Build and validation reports

| File | Contents |
| :--- | :--- |
| `VALIDATION.md` | final Image hashes and the 328-module ABI result |
| `BUILD-NOTES.md` | host limits, debug/BTF choice and the struct module trap |
| `PROVENANCE.md` | how the public GKI commit, config and toolchain were identified |
| `0001-module-keep-btf-tail-fields.patch` | keeps `struct module` ABI when BTF is off |
| `0002-thermal-off-param.patch` | adds the opt-in `thermal_sys.off` parameter |
| `BoardConfig.vendor-ramdisk-modules.patch` | installs the stock 168-module vendor_boot ramdisk |
| `tools/extract-vendor-ramdisk-modules.py` | extracts `.ko` + `modules.load` from stock `vendor_boot.img` |
| `tools/boottool.py` | AVB-preserving boot image repacker used for the custom boot images |
| `tuning/` | optional Magisk/KernelSU userspace tuning module (zram/RAM/thermal switch) |

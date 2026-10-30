# ABI and compatibility validation

Build date: 2026-10-23 (host: 4 cores, 3.7 GiB RAM, 21 GiB swap).

## Kernel artifact

| Item | Value |
| :--- | :--- |
| Image | `out/Image` |
| Image size | 41,679,360 bytes (40 MiB) |
| Image SHA-256 | `cee47fb20e405ea8ba070cbcd8dfeb4d503e49e8419984a8e59355d7baba2676` |
| `vmlinux.symvers` SHA-256 | `eae9668aa309f4427b109ad46f375a6735b8e7e130327bf1e5a2e1d0851097c0` |
| `System.map` SHA-256 | `95f68c40ab277e117e04fea990aaac741760cc434262518b777a307605e35991` |
| Release string | `5.15.194-android13-8-00019-gf4321180a397-ab15212794` |
| Exported versioned symbols | 8,575 |

The Image is the raw arm64 `Image` (not `Image.gz`) with the stock release
string, compiler identity and build timestamp.  `CONFIG_LTO_CLANG_FULL=y`,
`CONFIG_CFI_CLANG=y`, `CONFIG_MODVERSIONS=y` and
`CONFIG_MODULE_SCMVERSION=y` are all still enabled; only DWARF/BTF are
disabled for the 3.7 GiB host.

The `vmlinux.symvers` file is **byte-identical** to the validated base build
before the custom changes.  Adding the thermal parameter and the tuning
options therefore did not change any exported symbol CRC.

## Stock module validation

Command:

```bash
./validate-abi.sh vmlinux.symvers \
  ../android_device_xiaomi_serenity_lineage-lineage-23.2/prebuilts \
  /tmp/opencode/vendor_boot_out/lib/modules
```

Result:

```text
modules: 328
symbol references checked: 17648
symbols resolved by vmlinux: 16512
symbols not exported by vmlinux (module-to-module): 1136
stock module_layout CRC: 0x0222dd63
built module_layout CRC: 0x0222dd63
module_layout: OK

All resolved symbol CRCs match the stock modules.
```

The 328 modules are:

* 158 `vendor_dlkm` modules from `prebuilts/modules`
* 2 `system_dlkm` GKI modules (`zram.ko`, `zsmalloc.ko`)
* 168 `vendor_boot` ramdisk modules, extracted from the stock
  `vendor_boot.img` (65 of them are in the first-stage `modules.load`) with
  `serenity/tools/extract-vendor-ramdisk-modules.py`

A sample of the CRCs that the stock modules and this Image agree on:

| Symbol | CRC |
| :--- | :--- |
| `module_layout` | `0x0222dd63` |
| `kmalloc_caches` | `0xea0fd5fe` |
| `param_ops_uint` | `0x7c75e4a8` |
| `platform_driver_unregister` | `0xb68b66dd` |
| `mbox_send_message` | `0xec55920d` |
| `page_endio` | `0x4cf99ea5` |
| `contig_page_data` | `0xee4103ff` |
| `kmem_cache_alloc_trace` | `0x5239aaef` |

## Custom kernel changes

### Thermal bypass

`drivers/thermal/thermal_core.c` now has a module parameter named `off`.  The
object is linked into the built-in `thermal_sys` module, so the boot parameter
is:

```text
thermal_sys.off=1
```

and the runtime sysfs node is:

```text
/sys/module/thermal_sys/parameters/off
```

Default is `0` (stock thermal handling).  When set, `thermal_zone_device_update`
keeps the polling work armed but skips temperature updates and trip handling,
including critical-temperature shutdown.  This is intentionally dangerous and
is opt-in.

The patch is `serenity/0002-thermal-off-param.patch`.  It applies cleanly from
a pristine source tree with `patch -p1 --forward`.

### RAM / zram configuration

The build enables:

```text
CONFIG_LRU_GEN_ENABLED=y          # Multi-Gen LRU enabled by default
CONFIG_CRYPTO_LZ4HC=y             # extra compressor available to a rebuilt zram module
CONFIG_SECURITY_SELINUX_BOOTPARAM=y
```

The stock `zram.ko` / `zsmalloc.ko` are **not** replaced, so the module ABI is
preserved.  The stock zram module remains at its default `lzo-rle`.  The
historical validation used the old `serenity_tweaks-v1.0.zip` with `lz4`; the
current optional module in `serenity/tuning/` uses `lz4` with 60% zram and full
MGLRU.

## KernelSU LKM

The supplied `aarch64_android13-5.15_kernelsu.ko` was checked against the
freshly built `vmlinux` with the official KernelSU `check_symbol` tool:

```text
rc=0
```

The LKM has 233 undefined symbols, an empty `__versions` section and vermagic
`5.15.202-android13-5.15.202_r00-dirty SMP preempt mod_unload modversions aarch64`.
All 233 symbol names exist in the custom vmlinux.  It cannot be loaded with a
plain `insmod`; use KernelSU Manager's LKM installation path, which patches
`init_boot` and uses `ksuinit`.  `ksuinit` resolves the symbols and rewrites
the LKM vermagic if the kernel reports a version mismatch (the LKM says
5.15.202, this kernel is 5.15.194).

LKM SHA-256:
`d58d71d00e1ff49998a9c6d690fa2d8aa9567959ecff399a1b9ccc20199e68f0`

## Boot images

Both images are 67,108,864 bytes, contain the custom Image at page offset 4096
and keep the stock AVB0/AVBf bytes in place:

| Image | Kernel command line | SHA-256 |
| :--- | :--- | :--- |
| `boot_serenity_custom.img` | `androidboot.selinux=permissive enforcing=0` | `46bcfe755f3dca81d7bef95efe07d6b597bc3858535853aa9ffe5922b42521dd` |
| `boot_serenity_custom_thermal_off.img` | `androidboot.selinux=permissive enforcing=0 thermal_sys.off=1` | `af0822d9e9b29a33d8249e02f253a3ea41a805c64b568ed33cb973fc962acf45` |

The AVB region is preserved byte-for-byte, but it is **not a valid signature
for the new kernel**.  The device must have an unlocked bootloader with
verified boot disabled, as described by the original permissive-boot guide.

## Not validated on hardware

There is no Redmi A5 / POCO C71 device attached to this workspace.  The
following are verified statically, not at runtime:

* stock module load with all 328 `.ko` files;
* KernelSU LKM symbol resolution;
* boot image layout and kernel extraction;
* presence of the `thermal_sys.off` parameter and the SELinux cmdline tokens.

Thermal behavior, MGLRU, zram tuning, SELinux mode and KernelSU must still be
confirmed on a real device.  Keep the stock `boot.img` and `init_boot.img` for
recovery.

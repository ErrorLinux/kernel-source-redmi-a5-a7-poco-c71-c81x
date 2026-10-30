# Build notes

## Host used for this run

* 4 CPU cores
* 3.7 GiB RAM
* 21 GiB swap (5.6 GiB partition + 16 GiB swapfile)

The stock configuration is a full-LTO, CFI, debug-info, BTF kernel.  With the
stock `.config` the final `ld.lld -r -o vmlinux.o` step alone needed well over
the available RAM: the process sat at ~3 GiB RSS plus ~9 GiB swapped for more
than 40 minutes, with the machine at ~90% CPU and heavy swap I/O.  A retry with
`LD_OPT=-O1` behaved the same way.  That is a host limitation, not a source
problem.

To get a usable Image on this host, the final build keeps every
ABI-affecting option:

* `CONFIG_LTO_CLANG_FULL=y`
* `CONFIG_CFI_CLANG=y`
* `CONFIG_SHADOW_CALL_STACK=y`
* `CONFIG_MODVERSIONS=y`
* `CONFIG_MODULE_SIG_PROTECT=y`
* `CONFIG_MODULE_SCMVERSION=y`
* `CONFIG_ARM64_PTR_AUTH*`, `CONFIG_ARM64_BTI*`, `CONFIG_INIT_STACK_ALL_ZERO=y`

and only turns off the debug-only payload:

```
# CONFIG_DEBUG_INFO is not set
# CONFIG_DEBUG_INFO_BTF is not set
# CONFIG_DEBUG_INFO_BTF_MODULES is not set
```

`CONFIG_CFI_CLANG` adds the `cfi_check` member to `struct module`; it stays on.
However, `CONFIG_DEBUG_INFO_BTF_MODULES` also adds two fields
(`btf_data_size`, `btf_data`) to `struct module`, and many exported symbols
have types that reach `struct module` through `struct module *` pointers.
Turning BTF off therefore changes thousands of symbol CRCs, not just
`module_layout`, even though the fields are unused without BTF.

`include/linux/module.h` carries a small compatibility change
(`serenity/0001-module-keep-btf-tail-fields.patch`): the two BTF fields are
compiled in even when `CONFIG_DEBUG_INFO_BTF_MODULES` is off.  They are unused
padding in that build, but the layout and every type CRC match the stock
BTF-enabled kernel.  With the patch the no-debug build has the stock
`module_layout` CRC (`0x0222dd63`) and all stock module symbol CRCs match.

The config diff against the stock config is recorded in
`serenity/config.no-debug.diff`: the debug options, the host `pahole` version,
the local whitelist path, and the three tuning options (`LRU_GEN_ENABLED`,
`CRYPTO_LZ4HC`, `SECURITY_SELINUX_BOOTPARAM`) plus the generated zram choice
line.  The source patch is what keeps the ABI fixed.

For a byte-for-byte reproduction of the stock build (including DWARF and BTF),
build on a machine with at least 16 GiB RAM and run the script with the stock
`.config` (no `DEBUG_INFO` override).  The source, defconfig, compiler and
release string are already exact.

## Final result

The final rebuild with `NO_DEBUG_INFO=1` and the `struct module` compatibility
patch completed on 2026-10-23.  It adds the opt-in `thermal_sys.off` parameter
and the RAM/SELinux tuning options.  The resulting `out/Image` is 41,679,360
bytes with SHA-256
`cee47fb20e405ea8ba070cbcd8dfeb4d503e49e8419984a8e59355d7baba2676`.
`vmlinux.symvers` is unchanged from the base build:
`eae9668aa309f4427b109ad46f375a6735b8e7e130327bf1e5a2e1d0851097c0`.

All 328 stock modules (vendor_dlkm, system_dlkm and the vendor_boot ramdisk)
were checked: 17,648 symbol references, 16,512 resolved by the kernel, 1,136
module-to-module, and no CRC mismatch.  `module_layout` is `0x0222dd63` on both
sides.  The full report is in `serenity/VALIDATION.md`.

The same host also built two AVB-preserving boot images from the stock
`boot.img` and validated the supplied KernelSU LKM with the official
`check_symbol` tool (`rc=0`).  No hardware boot test was possible.

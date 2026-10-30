#!/usr/bin/env python3
"""Extract the stock vendor_boot ramdisk modules into a directory.

The stock Xiaomi/Unisoc vendor_boot ramdisk contains 168 modules, including
the 61 modules that are not present in the device tree's prebuilts/modules.
They provide sblock_*, sbuf_*, smsg_* and other vendor symbols, so a rebuilt
vendor_boot must keep them.

Usage:
    ./extract-vendor-ramdisk-modules.py vendor_boot.img OUTPUT_DIR

Requirements: python3, lz4, cpio.
"""
import argparse
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

VENDOR_BOOT_MAGIC = b"VNDRBOOT"
HEADER_V3_SIZE = 2112
HEADER_V4_SIZE = 2128


def parse_header(data):
    if data[:8] != VENDOR_BOOT_MAGIC:
        raise SystemExit("not a vendor_boot image (missing VNDRBOOT magic)")

    # vendor_boot_img_hdr_v3/v4, packed.
    fmt = "<8sIIIII2048sI16sIIQIIII"
    if struct.calcsize(fmt) != HEADER_V4_SIZE:
        raise SystemExit("internal header size mismatch")
    values = struct.unpack_from(fmt, data, 0)
    (_, version, page_size, _kernel_addr, _ramdisk_addr, ramdisk_size,
     _cmdline, _tags_addr, _name, header_size, dtb_size, _dtb_addr,
     _table_size, _table_num, _table_entry_size, _bootconfig_size) = values

    if version not in (3, 4):
        raise SystemExit(f"unsupported vendor_boot header version {version}")
    if header_size < HEADER_V3_SIZE or header_size > page_size:
        raise SystemExit(f"unexpected header size {header_size}")
    if page_size < 4096 or page_size & (page_size - 1):
        raise SystemExit(f"unexpected page size {page_size}")

    ramdisk_off = page_size
    ramdisk_end = ramdisk_off + ramdisk_size
    if ramdisk_size == 0 or ramdisk_end > len(data):
        raise SystemExit("vendor ramdisk is empty or truncated")

    return page_size, ramdisk_off, ramdisk_size, dtb_size


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("vendor_boot", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()

    if shutil.which("lz4") is None or shutil.which("cpio") is None:
        raise SystemExit("lz4 and cpio are required")

    data = args.vendor_boot.read_bytes()
    _page, ramdisk_off, ramdisk_size, _dtb_size = parse_header(data)
    args.output.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="vendor-ramdisk-") as tmp:
        tmp = Path(tmp)
        lz4_path = tmp / "ramdisk.lz4"
        lz4_path.write_bytes(data[ramdisk_off:ramdisk_off + ramdisk_size])

        extract_dir = tmp / "root"
        extract_dir.mkdir()
        lz4 = subprocess.Popen(
            ["lz4", "-dc", str(lz4_path)], stdout=subprocess.PIPE)
        cpio = subprocess.Popen(
            ["cpio", "-idm", "--no-absolute-filenames"],
            cwd=extract_dir, stdin=lz4.stdout)
        assert lz4.stdout is not None
        lz4.stdout.close()
        cpio_rc = cpio.wait()
        lz4_rc = lz4.wait()
        if cpio_rc or lz4_rc:
            raise SystemExit(f"lz4/cpio failed: lz4={lz4_rc} cpio={cpio_rc}")

        modules = extract_dir / "lib" / "modules"
        if not modules.is_dir():
            raise SystemExit("ramdisk has no /lib/modules directory")
        ko = sorted(modules.glob("*.ko"))
        if not ko:
            raise SystemExit("ramdisk has no .ko files")

        for path in ko:
            shutil.copy2(path, args.output / path.name)
        load = modules / "modules.load"
        if load.exists():
            shutil.copy2(load, args.output / "modules.load")

    print(f"copied {len(ko)} modules to {args.output}")
    print("add these lines to the device BoardConfig.mk:")
    print("BOARD_VENDOR_RAMDISK_KERNEL_MODULES := "
          "$(wildcard $(DEVICE_PATH)/prebuilts/vendor_ramdisk_modules/*.ko)")
    print("BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := "
          "$(strip $(shell cat "
          "$(DEVICE_PATH)/prebuilts/vendor_ramdisk_modules/modules.load))")


if __name__ == "__main__":
    main()

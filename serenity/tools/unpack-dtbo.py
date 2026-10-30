#!/usr/bin/env python3
"""Unpack an Android DTBO/DTB table image into the FDT blobs it contains.

The stock prebuilts/dtb.img and prebuilts/dtbo.img both use the Android
dt_table_header layout (magic 0xd7b7ab1e, big-endian fields).  Decompile the
result with: dtc -I dtb -O dts file.dtb
"""
import argparse
import pathlib
import struct


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=pathlib.Path)
    parser.add_argument("-o", "--outdir", type=pathlib.Path, required=True)
    args = parser.parse_args()

    data = args.image.read_bytes()
    magic, total, header_size, entry_size, count, entries_off, page_size, version = (
        struct.unpack_from(">8I", data, 0)
    )
    if magic != 0xD7B7AB1E:
        raise SystemExit(f"not a DTBO table: magic 0x{magic:08x}")

    args.outdir.mkdir(parents=True, exist_ok=True)
    print(
        f"total={total} header={header_size} entry={entry_size} "
        f"count={count} page={page_size} version={version}"
    )
    for index in range(count):
        size, offset = struct.unpack_from(">2I", data, entries_off + index * entry_size)
        blob = data[offset:offset + size]
        out = args.outdir / f"{args.image.stem}.{index}.dtb"
        out.write_bytes(blob)
        print(f"  [{index}] {size} bytes at 0x{offset:x} -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

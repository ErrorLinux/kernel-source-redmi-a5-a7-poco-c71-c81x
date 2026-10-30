#!/usr/bin/env python3
"""Extract the gzip-compressed kernel config embedded by CONFIG_IKCONFIG.

The stock ARM64 Image contains the marker IKCFG_ST followed by a gzip stream.
This is the same layout scripts/extract-ikconfig looks for in a vmlinux.
"""
import argparse
import pathlib
import zlib


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=pathlib.Path)
    parser.add_argument("-o", "--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    data = args.image.read_bytes()
    marker = data.find(b"IKCFG_ST")
    if marker < 0:
        raise SystemExit("IKCFG_ST not found; CONFIG_IKCONFIG is probably off")

    start = marker + len(b"IKCFG_ST")
    decompressor = zlib.decompressobj(31)  # gzip wrapper
    config = decompressor.decompress(data[start:])
    end = config.find(b"IKCFG_ED")
    if end >= 0:
        config = config[:end]

    args.output.write_bytes(config)
    print(f"{args.output}: {len(config)} bytes (marker at 0x{marker:x})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

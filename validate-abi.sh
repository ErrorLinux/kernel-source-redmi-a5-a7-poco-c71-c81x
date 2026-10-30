#!/usr/bin/env bash
# Compare the CRCs recorded in the stock prebuilt modules against the CRCs
# exported by the kernel just built.  A mismatch means the module will refuse
# to load (or, for module_layout, that struct module differs).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYMVERS="${1:-${ROOT}/vmlinux.symvers}"
STOCK="${2:-${ROOT}/../android_device_xiaomi_serenity_lineage-lineage-23.2/prebuilts}"
RAMDISK="${3:-}"

if [[ ! -f "${SYMVERS}" ]]; then
    echo "missing ${SYMVERS}; build the kernel first" >&2
    exit 1
fi

python3 - "${SYMVERS}" "${STOCK}" "${RAMDISK}" <<'PY'
import glob
import os
import subprocess
import sys

symvers, stock, ramdisk = sys.argv[1], sys.argv[2], sys.argv[3]

kernel = {}
with open(symvers) as f:
    for line in f:
        parts = line.split()
        if len(parts) >= 2 and parts[0].startswith("0x"):
            kernel[parts[1]] = int(parts[0], 16)

modules = sorted(glob.glob(os.path.join(stock, "modules", "*.ko")) +
                 glob.glob(os.path.join(stock, "modules_system", "*.ko")))
if ramdisk:
    modules += sorted(glob.glob(os.path.join(ramdisk, "*.ko")))
if not modules:
    print(f"no .ko files under {stock}", file=sys.stderr)
    sys.exit(1)

checked = 0
missing = 0
bad = []
module_layout = None
module_layout_bad = []

for ko in modules:
    out = subprocess.run(["modprobe", "--dump-modversions", ko],
                         text=True, capture_output=True)
    if out.returncode != 0 or not out.stdout:
        print(f"cannot read versions from {os.path.basename(ko)}: {out.stderr.strip()}",
              file=sys.stderr)
        continue
    for line in out.stdout.splitlines():
        fields = line.split()
        if len(fields) != 2 or not fields[0].startswith("0x"):
            continue
        crc, name = int(fields[0], 16), fields[1]
        checked += 1
        if name not in kernel:
            missing += 1
            continue
        if name == "module_layout":
            module_layout = crc
            if kernel[name] != crc:
                module_layout_bad.append((ko, crc, kernel[name]))
        elif kernel[name] != crc:
            bad.append((os.path.basename(ko), name, crc, kernel[name]))

print(f"modules: {len(modules)}")
print(f"symbol references checked: {checked}")
print(f"symbols resolved by vmlinux: {checked - missing}")
print(f"symbols not exported by vmlinux (module-to-module): {missing}")
if module_layout is not None:
    print(f"stock module_layout CRC: 0x{module_layout:08x}")
    built = kernel.get("module_layout")
    if built is not None:
        print(f"built module_layout CRC: 0x{built:08x}")
    print("module_layout: " + ("MISMATCH" if module_layout_bad else "OK"))

if module_layout_bad or bad:
    print(f"\nCRC mismatches: {len(bad) + len(module_layout_bad)}")
    for ko, name, stock_crc, built_crc in (module_layout_bad + bad)[:40]:
        print(f"  {os.path.basename(ko)}: {name}: stock 0x{stock_crc:08x} built 0x{built_crc:08x}")
    sys.exit(1)

print("\nAll resolved symbol CRCs match the stock modules.")
PY

# Serenity 4GB Tuning (kernel + module)

## Kernel image

`build-serenity-mglru-tuned.sh` builds a GKI 5.15 serenity image with:

- `CONFIG_LRU_GEN=y`
- `CONFIG_LRU_GEN_ENABLED=y` (full MGLRU, not core-only)
- `CONFIG_MQ_IOSCHED_KYBER=y` (already in `serenity_defconfig`)
- `CONFIG_CRYPTO_LZ4HC=y` (already in `serenity_defconfig`)
- `serenity/0003-lru-gen-guard-clear-mm-walk.patch`
- `serenity/0004-lru-gen-harden-mm-walk.patch`

The patch is defensive: `clear_mm_walk()` no longer calls `kfree()` on the
static `pgdat->mm_walk` or on a corrupted pointer left in
`current->reclaim_state->mm_walk`.  It only frees a pointer that is still a
live slab object.  It stops the two observed panics (`&pgdat->mm_walk` and
`ffffffff0029f208`), but it does not repair whatever vendor path corrupted
`reclaim_state`; keep an eye on `/sys/fs/pstore` and ylog.

Build:

```bash
cd kernel-source-serenity

# 4 GB host (tested): ThinLTO, low memory
JOBS=2 ./build-serenity-thin.sh

# 16 GB+ host: full LTO
NO_DEBUG_INFO=1 JOBS=$(nproc) ./build-serenity-mglru-tuned.sh
```

## Module

The module is a separate Magisk/KernelSU module.  It sets runtime knobs that
cannot be baked into the kernel image:

| Knob | Value | Why |
|---|---|---|
| `vm.swappiness` | `100` | Android zram default; not the old 200 |
| `vm.page-cluster` | `0` | random zram faults should not read 128 KiB |
| `vm.watermark_scale_factor` | `200` | earlier reclaim before hard pressure |
| `vm.vfs_cache_pressure` | `100` | default; avoids inode-cache bloat from `1` |
| `vm.dirty_ratio` / `dirty_background_ratio` | `20` / `5` | Android-like writeback |
| `lru_gen/enabled` | `y` | full MGLRU caps |
| zram0 | 50% of RAM, `lz4hc`, only if unconfigured | ~2 GB swap on 4 GB, never reset live zram |
| `read_ahead_kb` | `64` on real block devices | UFS/eMMC readahead |
| scheduler | `kyber` if listed | lower latency on blk-mq |
| CPU governor | `schedutil` default; `performance` opt-in | max clocks only when requested |

Install the zip in Magisk/KernelSU, then reboot.  Log:
`/data/local/tmp/serenity_tuning.log`.

Enable max CPU clocks (optional, not recommended for sustained load):

```bash
su -c 'setprop persist.serenity.cpu_performance 1'
# reboot, or rerun the module service
```

Disable:

```bash
su -c 'setprop persist.serenity.cpu_performance 0'
```

## Conflicts

- Remove `zram_12gb_fix` (or any module that resets a live zram / sets
  `swappiness=200`).
- `serenity_tweaks` writes `1` to `/sys/kernel/mm/lru_gen/enabled`, which is
  **core-only** MGLRU.  On this kernel the default is full MGLRU.  Remove that
  line or let this module's `service.sh` re-apply `y` after boot.
- Do not set 12 GB zram on a 4 GB phone; it turns RAM pressure into swap
  thrash and was the strongest trigger of the old panic.

## Rollback

Remove the module and reboot; all sysctls/scheduler changes are runtime-only.
Flash the stock `boot.img` or the previous `boot_serenity_custom.img` to roll
back the kernel.

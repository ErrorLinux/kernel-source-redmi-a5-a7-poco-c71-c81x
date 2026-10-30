#!/system/bin/sh
# Serenity 4GB tuning: early pass.
# Best effort: never abort boot if a knob does not exist.
MODDIR=${0%/*}
LOG=/data/local/tmp/serenity_tuning.log
set +e

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

write_file() {
    [ -e "$1" ] || return 0
    echo "$2" > "$1" 2>/dev/null && log_msg "wrote $1=$2"
}

# --- MGLRU ---------------------------------------------------------------
# "y" enables every supported cap (core + MM walk + nonleaf young), which is
# what CONFIG_LRU_GEN_ENABLED=y gives on the custom kernel.  On a stock kernel
# this turns MGLRU on at runtime.  Do not write "1": that is core-only.
write_file /sys/kernel/mm/lru_gen/enabled y

# --- VM / zram-friendly defaults ----------------------------------------
# swappiness=100 is the Android zram default; page-cluster=0 avoids reading
# 128 KiB chunks for random zram faults.  Do not use the old 12 GB zram
# module: it resets a live zram and drives swappiness to 200.
write_file /proc/sys/vm/swappiness 100
write_file /proc/sys/vm/page-cluster 0
write_file /proc/sys/vm/watermark_scale_factor 200
write_file /proc/sys/vm/vfs_cache_pressure 100
write_file /proc/sys/vm/dirty_ratio 20
write_file /proc/sys/vm/dirty_background_ratio 5

# --- zram ---------------------------------------------------------------
# Never reset a live zram0.  Only configure it when Android/init left it at 0.
if [ -e /sys/block/zram0/disksize ]; then
    cur_size=$(cat /sys/block/zram0/disksize 2>/dev/null)
    if [ "$cur_size" = "0" ] || [ -z "$cur_size" ]; then
        percent=$(getprop persist.serenity.zram_percent)
        case "$percent" in
            ''|*[!0-9]*) percent=50 ;;
        esac
        [ "$percent" -ge 20 ] 2>/dev/null || percent=20
        [ "$percent" -le 75 ] 2>/dev/null || percent=75

        # lz4hc is compiled into the kernel (CONFIG_CRYPTO_LZ4HC=y); the
        # stock zram module can use it through the crypto API.
        write_file /sys/block/zram0/comp_algorithm lz4hc

        mem_kb=$(sed -n 's/^MemTotal:[[:space:]]*\([0-9][0-9]*\).*/\1/p' /proc/meminfo 2>/dev/null)
        if [ -n "$mem_kb" ]; then
            size_bytes=$((mem_kb * percent / 100 * 1024))
            write_file /sys/block/zram0/disksize "$size_bytes"
            mkswap /dev/block/zram0 >/dev/null 2>&1
            swapon /dev/block/zram0 >/dev/null 2>&1
            log_msg "zram configured: ${percent}% of ${mem_kb} KiB"
        fi
    else
        log_msg "zram already active; not resetting it"
    fi
fi

# --- I/O ----------------------------------------------------------------
# 64 KiB readahead on real block devices; skip zram/loop/ram.
for q in /sys/block/*/queue; do
    [ -d "$q" ] || continue
    dev=${q%/queue}
    dev=${dev##*/}
    case "$dev" in
        zram*|loop*|ram*) continue ;;
    esac
    write_file "$q/read_ahead_kb" 64
    if grep -qw kyber "$q/scheduler" 2>/dev/null; then
        write_file "$q/scheduler" kyber
    fi
done

log_msg "post-fs-data done"
exit 0

#!/system/bin/sh
# Serenity 4GB tuning: late pass, after Android and vendor init have settled.
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

i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 120 ]; do
    sleep 2
    i=$((i + 1))
done

# Let other modules' service.sh scripts finish (serenity_tweaks writes
# lru_gen/enabled=1, which is core-only) before re-applying full MGLRU.
sleep 5

# Re-apply after vendor post-boot scripts; some ROMs reset these.
write_file /sys/kernel/mm/lru_gen/enabled y
write_file /proc/sys/vm/swappiness 100
write_file /proc/sys/vm/page-cluster 0
write_file /proc/sys/vm/watermark_scale_factor 200
write_file /proc/sys/vm/vfs_cache_pressure 100
write_file /proc/sys/vm/dirty_ratio 20
write_file /proc/sys/vm/dirty_background_ratio 5

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

# CPU performance is opt-in.  Pinning all cores to max helps short bursts but
# hurts sustained gaming/battery/thermal on a 4 GB Unisoc.  Enable with:
#   setprop persist.serenity.cpu_performance 1
# Disable with:
#   setprop persist.serenity.cpu_performance 0
if [ "$(getprop persist.serenity.cpu_performance)" = "1" ]; then
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        gov="$cpu/cpufreq/scaling_governor"
        [ -e "$gov" ] || continue
        write_file "$gov" performance
    done
    log_msg "CPU performance governor enabled"
else
    log_msg "CPU governor left at kernel/ROM default (schedutil)"
fi

log_msg "service done"
exit 0

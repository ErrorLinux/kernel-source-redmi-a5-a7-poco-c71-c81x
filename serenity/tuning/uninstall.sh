#!/system/bin/sh
# Remove the runtime log.  All knobs are runtime-only and reset on reboot.
rm -f /data/local/tmp/serenity_tuning.log
exit 0

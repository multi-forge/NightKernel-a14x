#!/system/bin/sh
MODDIR=${0%/*}

# Neutralize vendor recovery restore scripts via bind-mount
if [ -f /vendor/bin/install-recovery.sh ]; then
    mount -o bind "$MODDIR/system/vendor/bin/install-recovery.sh" /vendor/bin/install-recovery.sh
fi

if [ -f /vendor/recovery-from-boot.p ]; then
    mount -o bind "$MODDIR/system/vendor/recovery-from-boot.p" /vendor/recovery-from-boot.p
fi

if [ -f /system/bin/install-recovery.sh ]; then
    mount -o bind "$MODDIR/system/bin/install-recovery.sh" /system/bin/install-recovery.sh
fi

if [ -f /system/recovery-from-boot.p ]; then
    mount -o bind "$MODDIR/system/recovery-from-boot.p" /system/recovery-from-boot.p
fi

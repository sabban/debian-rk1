#!/usr/bin/env sh

MOUNT_POINT="./mnt"
DISK_IMAGE="./disk-rk1.img"

umount "${MOUNT_POINT}/proc"
umount "${MOUNT_POINT}/sys"
umount "${MOUNT_POINT}/dev/pts"
umount "${MOUNT_POINT}/dev"

umount "${MOUNT_POINT}/boot/boot"
umount /dev/mapper/rk1-home
umount /dev/mapper/rk1-var
umount /dev/mapper/rk1-tmp
umount /dev/mapper/rk1-root

dmsetup remove rk1-home
dmsetup remove rk1-var
dmsetup remove rk1-tmp
dmsetup remove rk1-root

ABS_PATH=$(realpath "${DISK_IMAGE}")
kpartx -d "${ABS_PATH}"

#!/usr/bin/env sh

DISK_IMAGE=disk-rk1.img
MOUNT_POINT=./mnt

DEVICE=$(losetup -f)

losetup "${DEVICE}" "${DISK_IMAGE}"

BOOT=$(fdisk -l "${DEVICE}" | grep "${DEVICE}" |  sed -n 2p | awk '{print $1}')
VOLUME=$(fdisk -l "${DEVICE}" | grep "${DEVICE}" |  sed -n 3p | awk '{print $1}')

echo "BOOT: ${BOOT}"
echo "VOLUME: ${VOLUME}"

partprobe "${DEVICE}"

lvscan
lvchange -ay /dev/mapper/rk1-root
lvchange -ay /dev/mapper/rk1-var
lvchange -ay /dev/mapper/rk1-tmp
lvchange -ay /dev/mapper/rk1-home

mount /dev/mapper/rk1-root "${MOUNT_POINT}"
mkdir -p "${MOUNT_POINT}/tmp"
mkdir -p "${MOUNT_POINT}/var"
mkdir -p "${MOUNT_POINT}/home"
mkdir -p "${MOUNT_POINT}/boot"

mount "${BOOT}" "${MOUNT_POINT}/boot/boot"
mount /dev/mapper/rk1-tmp "${MOUNT_POINT}/tmp"
mount /dev/mapper/rk1-var "${MOUNT_POINT}/var"
mount /dev/mapper/rk1-home "${MOUNT_POINT}/home"

mount --bind /dev "${MOUNT_POINT}/dev"
mount --bind /dev/pts "${MOUNT_POINT}/dev/pts"
mount  /proc "${MOUNT_POINT}/proc" -t proc
mount --bind /sys "${MOUNT_POINT}/sys"

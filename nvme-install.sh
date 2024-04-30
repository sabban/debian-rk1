#!/usr/bin/env sh
# Define source and target disks
DEVICE="/dev/nvme0n1"

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Create a partition table on the target disk
parted --script "${DEVICE}" \
    mklabel gpt \
    mkpart primary fat32 16MiB 200MiB \
    mkpart primary 200MiB 100%


BOOT=$(fdisk -l "${DEVICE}" | grep "${DEVICE}" |  sed -n 2p | awk '{print $1}')
VOLUME=$(fdisk -l "${DEVICE}" | grep "${DEVICE}" |  sed -n 3p | awk '{print $1}')


# create the boot partition
mkfs.vfat -F32 -n boot "${BOOT}"

mkdir -p /mnt/target
mount "${BOOT}" /mnt/target/boot
rsync -axHAWX --numeric-ids --info=progress2 /boot/boot /mnt/target/boot
umount /mnt/target

# install u-boot blob
if [ -f "/usr/lib/u-boot/u-boot-rockchip.bin" ]; then
    dd if="/usr/lib/u-boot/u-boot-rockchip.bin" of="${DEVICE}" seek=1 bs=32k conv=fsync
else
    echo "u-boot-rockchip.bin not found"
    exit 1
fi


PV_TO_REMOVE=$(pvs --noheadings|grep -v $DEVICE|awk '{print $1}')
pvcreate "${VOLUME}"
vgextend rk1 "${VOLUME}"
pvmove "${PV_TO_REMOVE}"
vgreduce rk1 "${PV_TO_REMOVE}"

# Format and make file systems - adjust these as per your specific setup
# Example: assuming the first partition is root (`/`) and formatted as ext4

# Mount the target filesystem to copy files


# Mount necessary directories and chroot into new environment

echo "Migration from MMC disk to NVMe disk completed successfully!"
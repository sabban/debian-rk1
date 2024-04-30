#!/usr/bin/env sh
#picocom /dev/ttyS[2|1|4|5] -b 115200

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

if [ -z "${RELEASE}" ]; then
    RELEASE=bookworm
fi

if [ -z "${CHROOT_DIR}" ]; then
    CHROOT_DIR=./rootfs
fi

if [ -z "${MOUNT_POINT}" ]; then
    MOUNT_POINT=./mnt

    if [ ! -d "${MOUNT_POINT}" ]; then
        mkdir -p "${MOUNT_POINT}"
    fi
fi

# Create rootfs
if [ ! -d "${CHROOT_DIR}" ]; then
    if uname -m | grep -q arm64; then
        debootstrap --arch arm64 "${RELEASE}" "${CHROOT_DIR}" http://ftp.debian.org/debian/
    else
        debootstrap --arch arm64 --foreign "${RELEASE}" "${CHROOT_DIR}" http://ftp.debian.org/debian/

        if [ -f /usr/bin/qemu-aarch64-static ]; then
            cp /usr/bin/qemu-aarch64-static "${CHROOT_DIR}/usr/bin/"
        else
            echo "Please install qemu-user-static"
            exit 1
        fi

        chroot "${CHROOT_DIR}" /debootstrap/debootstrap --second-stage
    fi
else
    echo "Rootfs already exists, skipping its creation"
fi

# Create disk image
DISK_IMAGE="./disk-rk1.img"

if  ! command -v realpath ; then
    echo "Please install realpath to be able to cleanup at the end the script"
    exit 1
fi

dd if=/dev/zero of="${DISK_IMAGE}" bs=1M count=2000

parted --script "${DISK_IMAGE}" \
    mklabel gpt \
    mkpart primary fat32 16MiB 200MiB \
    mkpart primary 200MiB 100%

DEVICE=$(losetup -f)

losetup "${DEVICE}" "${DISK_IMAGE}"

BOOT=$(fdisk -l "${DEVICE}" | grep "${DEVICE}" |  sed -n 2p | awk '{print $1}')
VOLUME=$(fdisk -l "${DEVICE}" | grep "${DEVICE}" |  sed -n 3p | awk '{print $1}')

echo "BOOT: ${BOOT}"
echo "VOLUME: ${VOLUME}"

partprobe "${DEVICE}"

mkfs.vfat -F32 -n boot "${BOOT}"

pvcreate "${VOLUME}"
vgcreate rk1 "${VOLUME}"  --config 'devices{ filter = [ "a/dev/loop.*/", "r/dev/mapper/.*/" ] }'
lvcreate -L 1G -n root rk1
lvcreate -L 100M -n tmp rk1
lvcreate -L 350M -n var rk1
#lvcreate -L 10M -n home rk1

mkfs.ext4 -L root /dev/mapper/rk1-root
mkfs.ext4 -L tmp /dev/mapper/rk1-tmp
mkfs.ext4 -L var /dev/mapper/rk1-var
#mkfs.ext4 -L home /dev/mapper/rk1-home

e2label /dev/mapper/rk1-root root
e2label /dev/mapper/rk1-tmp tmp
e2label /dev/mapper/rk1-var var
#e2label /dev/mapper/rk1-home home

mount /dev/mapper/rk1-root "${MOUNT_POINT}"
mkdir -p "${MOUNT_POINT}/tmp"
mkdir -p "${MOUNT_POINT}/var"
#mkdir -p "${MOUNT_POINT}/home"
mkdir -p "${MOUNT_POINT}/boot/boot"

mount "${BOOT}" "${MOUNT_POINT}/boot/boot"
mount /dev/mapper/rk1-tmp "${MOUNT_POINT}/tmp"
mount /dev/mapper/rk1-var "${MOUNT_POINT}/var"
#mount /dev/mapper/rk1-home "${MOUNT_POINT}/home"

rsync -apzq --delete "${CHROOT_DIR}/" "${MOUNT_POINT}/"
cp -a packages/*.deb "${MOUNT_POINT}/root"

# install packages in chroot
cat << EOF | chroot "${MOUNT_POINT}" /bin/bash
apt-get update
apt-get install -y mtd-utils
for package in /root/*.deb; do
    dpkg -i "\$package"
done
EOF

#unlock root account
cat << EOF | chroot "${MOUNT_POINT}" /bin/bash
passwd -u root
EOF

# install u-boot blob
if [ -f "${MOUNT_POINT}/usr/lib/u-boot/u-boot-rockchip.bin" ]; then
    dd if="${MOUNT_POINT}/usr/lib/u-boot/u-boot-rockchip.bin" of="${DEVICE}" seek=1 bs=32k conv=fsync
else
    echo "u-boot-rockchip.bin not found"
    exit 1
fi

# add user
if [ -z "${USER}" ]; then
    USER="admin"
fi

if [ -z "${SSH_PUB_KEY_FILE}" ]; then
    echo "SSH_PUB_KEY_FILE is not set"
    exit 1
fi

SSH_PUB_KEY=$(cat "${SSH_PUB_KEY_FILE}")

if [ -z "${BOOT_ARGS}" ]; then
    BOOT_ARGS=""
fi

mount --bind /dev "${MOUNT_POINT}/dev"
mount --bind /dev/pts "${MOUNT_POINT}/dev/pts"
mount  /proc "${MOUNT_POINT}/proc" -t proc
mount --bind /sys "${MOUNT_POINT}/sys"

# install packages in chroot
cat << EOF | chroot "${MOUNT_POINT}" /bin/bash
apt-get install -y flash-kernel openssh-server cloud-init lvm2 sudo net-tools locales
EOF

# add user and its ssh key
cat << EOF | chroot "${MOUNT_POINT}" /bin/bash
useradd -m -s /bin/bash "${USER}"
usermod -aG sudo "${USER}"
mkdir -p /home/"${USER}"/.ssh
echo "${SSH_PUB_KEY}" > /home/"${USER}"/.ssh/authorized_keys
echo "${USER}" ALL=(ALL) NOPASSWD:ALL > /etc/sudoers.d/90-"${USER}"
EOF

# configure boot
cat << EOF >> "${MOUNT_POINT}/etc/flash-kernel/db"
Machine: Turing Machines RK1
Kernel-Flavors: any
Method: generic
Boot-Kernel-Path: /boot/boot/vmlinuz
Boot-Initrd-Path: /boot/boot/initrd.img
EOF

cat <<EOF >> "${MOUNT_POINT}/etc/default/u-boot"
U_BOOT_ROOT="root=/dev/mapper/rk1-root"
EOF

cat <<EOF >> "${MOUNT_POINT}/etc/flash-kernel/machine"
Turing Machines RK1
EOF

cat <<EOF | chroot "${MOUNT_POINT}" /bin/bash
cp /usr/lib/linux-image-5.10.160-rockchip/rockchip/rk3588-turing-rk1.dtb /boot/boot/
mkdir -p /boot/boot/overlays
cp -a /usr/lib/linux-image-5.10.160-rockchip/rockchip/overlay/rk3588*.dtbo /boot/boot/overlays
EOF

cat > "${MOUNT_POINT}/boot/boot/bootEnv.txt" << EOF
bootargs=root=/dev/rk1/root rootfstype=ext4 rootwait rw console=ttyS9,115200 console=ttyS2,1500000 console=tty1 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1 systemd.unified_cgroup_hierarchy=0
fdtfile=rk3588-turing-rk1.dtb
overlay_prefix=rk3588
overlays=
EOF

# Configure network
# Would have preferred to use cloud init but didn't work out for some reason
cat > "${MOUNT_POINT}/etc/network/interfaces" << 'EOF'
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
iface end0 inet dhcp
# This is an autoconfigured IPv6 interface
iface end0 inet6 auto
EOF

cat > "${MOUNT_POINT}/boot/boot/boot.cmd" << 'EOF'
# This is a boot script for U-Boot
#
# Recompile with:
# mkimage -A arm64 -O linux -T script -C none -n "Boot Script" -d boot.cmd boot.scr

setenv load_addr "0x7000000"
setenv overlay_error "false"

echo "Boot script loaded from ${devtype} ${devnum}"

if test -e ${devtype} ${devnum}:${distro_bootpart} /bootEnv.txt; then
    load ${devtype} ${devnum}:${distro_bootpart} ${load_addr} /bootEnv.txt
    env import -t ${load_addr} ${filesize}
fi

load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} ${fdtfile}
fdt addr ${fdt_addr_r} && fdt resize 0x10000

for overlay_file in ${overlays}; do
    for file in "${overlay_prefix}-${overlay_file}.dtbo ${overlay_prefix}-${overlay_file} ${overlay_file}.dtbo ${overlay_file}"; do
        test -e ${devtype} ${devnum}:${distro_bootpart} /overlays/${file} \
        && load ${devtype} ${devnum}:${distro_bootpart} ${fdtoverlay_addr_r} /overlays/${file} \
        && echo "Applying device tree overlay: /overlays/${file}" \
        && fdt apply ${fdtoverlay_addr_r} || setenv overlay_error "true"
    done
done
if test "${overlay_error}" = "true"; then
    echo "Error applying device tree overlays, restoring original device tree"
    load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r} ${fdtfile}
fi

load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /vmlinuz
load ${devtype} ${devnum}:${distro_bootpart} ${ramdisk_addr_r} /initrd.img

booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r}
EOF

cat <<EOF |chroot "${MOUNT_POINT}"
mkimage -A arm64 -O linux -T script -C none -n "Boot Script" -d /boot/boot/boot.cmd /boot/boot/boot.scr
FK_IGNORE_EFI=yes update-initramfs  -c -k all
EOF

ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/rk1-root)
TMP_UUID=$(blkid -s UUID -o value /dev/mapper/rk1-tmp)
VAR_UUID=$(blkid -s UUID -o value /dev/mapper/rk1-var)
BOOT_UUID=$(blkid -s UUID -o value "${BOOT}")


cat << EOF >> "${MOUNT_POINT}/etc/fstab"
UUID="${ROOT_UUID}" / ext4 errors=remount-ro 0 1
UUID="${BOOT_UUID}" /boot/boot vfat defaults 0 2
UUID="${TMP_UUID}" /tmp ext4 defaults 0 2
UUID="${VAR_UUID}" /var ext4 defaults 0 2
#LABEL=home /home ext4 defaults 0 2
EOF

cp nvme-install.sh "${MOUNT_POINT}/usr/bin/nvme-install.sh"
chmod u+x "${MOUNT_POINT}/usr/bin/nvme-install.sh"

umount "${MOUNT_POINT}/proc"
umount "${MOUNT_POINT}/sys"
umount "${MOUNT_POINT}/dev/pts"
umount "${MOUNT_POINT}/dev"

umount "${MOUNT_POINT}/boot/boot"
#umount /dev/mapper/rk1-home
umount /dev/mapper/rk1-var
umount /dev/mapper/rk1-tmp
umount /dev/mapper/rk1-root

#dmsetup remove rk1-home
dmsetup remove rk1-var
dmsetup remove rk1-tmp
dmsetup remove rk1-root

ABS_PATH=$(realpath "${DISK_IMAGE}")
kpartx -d "${ABS_PATH}"

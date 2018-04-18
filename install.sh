#!/usr/bin/env bash

###############################################################################
#                       Configuration variables
###############################################################################

mnt="temporary_mount_point"
arch="amd64"
release="jessie"
repo="http://ftp.fr.debian.org/debian"
hostname="nohost"

###############################################################################
#                       Configurations end
###############################################################################

yell() { echo >&2 -e "\nERROR: $@\n"; }
die() { yell "$@"; exit 1; }
run() { "$@"; code=$?; [ $code -ne 0 ]&& die "command [$*] failed with erro code $code"; }
usage() {
  die "$0 <device>"
}

if [ $UID -ne 0 ]; then
    die "You must be root"
fi

if [ $# -lt 1 ] ; then
  yell "No device found"
  usage
fi
device="$1"
bloc=$(echo "$device" | grep -o "^[a-zA-Z/]*")

run mkfs.ext4 "$device"
run mkdir -p "$mnt"
run mount "$device" "$mnt"
run debootstrap --arch "$arch" "$release" "$mnt" "$repo"
run mount -t proc none "$mnt/proc"
run mount -o bind /dev "$mnt/dev"
run chroot "$mnt"
uuid=$(blkid | grep "$device" | cut -d ' ' -f 2)
run echo -e "proc /proc proc defaults\n$uuid    /    ext4 errors=remount-ro 0 1" > "$mnt/etc/fstab"
run echo "$hostname" > "$mnt/etc/hostname"
run tee "$mnt/etc/network/interfaces" << EOF
auto lo
iface lo inet loopback
allow-hotplug eth0
auto eth0
iface eth0 inet dhcp
EOF

# TODO
cat << EOF | chroot "$mnt"
apt-get update ; apt-get install linux-image-amd64 console-data grub2
EOF

run umount "$mnt/{dev,proc}$
run umount $mnt
run qemu-system-x86_64 $bloc

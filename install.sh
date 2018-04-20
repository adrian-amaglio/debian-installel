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
  die "$0 <device>" \
    "-t | --test : Start qemu after the installation. Not implemented" \
    "-i | --install <package list> : Install the provided packages. Not implemented" \
    "-c | --clean [YES|no] : Delete the temporar mountpoints" \
    "-e | --exec : Execute commands in the chroot environment. - to read them from stdin." \


}

if [ $UID -ne 0 ]; then
    die "You must be root"
fi

if [ $# -lt 1 ] ; then
  yell "No device found"
  usage
fi

echo "Choosing device"
device="$1"
bloc=$(echo "$device" | grep -o "^[a-zA-Z/]*")

echo "Formating"
run mkfs.ext4 "$device"

echo "Preparing filesystem"
run mkdir -p "$mnt"
run mount "$device" "$mnt"

echo "debootstraping"
run debootstrap --arch "$arch" "$release" "$mnt" "$repo"

echo "Preparing chroot"
run mount -t proc none "$mnt/proc"
run mount -o bind /dev "$mnt/dev"

echo "Configuring new system"
uuid=$(blkid | grep "$device" | cut -d ' ' -f 2)
run echo -e "proc /proc proc defaults\n$uuid    /    ext4 errors=remount-ro 0 1" > "$mnt/etc/fstab"
run echo "$hostname" > "$mnt/etc/hostname"
run tee "$mnt/etc/network/interfaces" > /dev/null << EOF
auto lo
iface lo inet loopback
allow-hotplug eth0
auto eth0
iface eth0 inet dhcp
EOF
run echo 'PATH=$PATH:/usr/bin:/bin:/sbin:/usr/sbin' > "$mnt/root/.bashrc"

echo "Chrooting"
cat << EOF | chroot "$mnt"
apt-get update -y
apt-get install -y linux-image-amd64 console-data grub2
EOF

# TODO setup grub manually
echo "Cleaning fs"
run umount "$mnt"/{dev,proc}
run umount "$mnt"
run rm -r "$mnt"

echo "Testing"
run qemu-system-x86_64 $bloc

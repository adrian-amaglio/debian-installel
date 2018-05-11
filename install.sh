#!/bin/bash

# https://github.com/adrianamaglio/driglibash
declare -A usage
declare -A varia

version="alpha nightly 0.0.1 pre-release unstable"
summary="$0 [options] <device>"

usage[t]="Start qemu after the installation"
varia[t]=tst
tst=false

usage[i]="Install the provided package. Not implemented"
varia[i]=install
declare -a install

usage[k]="Keep the temporar mountpoints"
varia[k]=keep
keep=false

usage[e]="bash command file to execute in the chroot. - to read from stdin"
varia[e]=execute
declare -a execute

usage[m]="Path of the temporar mount point"
varia[m]=mnt
mnt="temporary_mount_point"

usage[a]="The architecture of installed system as supported by debootstrap"
varia[a]=arch
arch="amd64"

usage[r]="The release of installed system as supported by debootstrap"
varia[r]=release
release="jessie"

usage[s]="Source repository of installed system"
varia[s]=repo
repo="http://ftp.fr.debian.org/debian"

usage[n]="The hostname"
varia[n]=hostname
hostname="nohost"

usage[c]="file:dest Copy the <file> to <dest> into the new system"
varia[c]=copy
declare -a copy

. /bin/driglibash-args

###############################################################################
#                              Actual script
###############################################################################


if [ $# -lt 1 ] ; then die "No device found" ; fi
root_or_die

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
run cat > "$mnt/etc/network/interfaces" << EOF
auto lo
iface lo inet loopback
allow-hotplug eth0
auto eth0
iface eth0 inet dhcp
EOF
run echo 'PATH=$PATH:/usr/bin:/bin:/sbin:/usr/sbin' > "$mnt/root/.bashrc"

echo "Chrooting"
cat << EOF | chroot "$mnt"
apt-get update -y ${install[@]}
apt-get install -y linux-image-amd64 console-data grub2
EOF
# TODO setup grub manually
# TODO set passwd

echo "Cleaning fs"
run umount "$mnt"/{dev,proc}
run umount "$mnt"
if [ -z "$arg_keep" ] ; then
  run rm -r "$mnt"
fi

if [ -n "$arg_test" ] ; then
  echo "Testing"
  run qemu-system-x86_64 $bloc
fi

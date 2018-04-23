#!/bin/bash

###############################################################################
#                       Configuration variables
###############################################################################

tst=false
declare -a install
keep=false
declare -a execute
mnt="temporary_mount_point"
arch="amd64"
release="jessie"
repo="http://ftp.fr.debian.org/debian"
hostname="nohost"

summary="$0 [options] <device>"
declare -A usage
usage[t]="tst Start qemu after the installation"
usage[i]="install Install the provided package. Not implemented"
usage[k]="keep Keep the temporar mountpoints"
usage[e]="execute bash command file to execute in the chroot. - to read from stdin"
usage[m]="mnt Path of the temporar mount point"

###############################################################################
#                       Configurations end
###############################################################################

yell() { echo >&2 -e "$@"; }
die() { yell "$@"; exit 1; }
need_root() { if [ "$UID" -ne 0 ] ; then die "You need to be root" ; fi }
run() { "$@"; code=$?; [ $code -ne 0 ]&& die "command [$*] failed with erro code $code"; }
usage() { die "$summary\n$(for key in "${!usage[@]}" ; do echo "  -$key $( echo ${usage[$key]} | cut -d ' ' -f 2- )"; done)\n  -h print this help and exit."; }

while getopts ":tke:i:m:h" opt; do
  case $opt in
    h) usage;;
    :) die "Option -$OPTARG requires an argument.";;
    \?) die "Invalid option: -$OPTARG";;
    *)
      name=$(echo ${usage[$opt]} | cut -d ' ' -f 1 )
      if [ "${!name}" == "false" ] ; then eval $name=true
      elif [ -n "$( declare -p "$name" 2>/dev/null | grep 'declare \-a')" ] ; then safe="${!name} $OPTARG" ; eval $name=\$safe
      else eval $name=\$OPTARG
      fi;;
  esac
done ; shift $((OPTIND-1))

if [ $# -lt 1 ] ; then
  yell "No device found"
  usage
fi
need_root

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

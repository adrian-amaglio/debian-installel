#!/bin/bash

# https://github.com/adrianamaglio/driglibash
declare -A usage
declare -A varia

version="alpha nightly 0.0.1 pre-release unstable"
summary="$0 [options] <device>"

usage[t]="Start qemu after the installation"
varia[t]=arg_test
arg_test=false

usage[i]="Install the provided package. Plus 'linux-image-amd64 console-data grub2'"
varia[i]=install
install=

usage[e]="bash commands to execute in the chroot."
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
release="stretch"

usage[s]="Source repository of installed system"
varia[s]=repo
repo="http://ftp.fr.debian.org/debian"

usage[n]="The hostname"
varia[n]=hostname
hostname="nohost"

usage[p]="Root password"
varia[p]=password
password=toor

usage[l]="System locale"
varia[l]=locale
locale=en_US.UTF-8

usage[q]="Quickstart packs (sysadmin, webserver, network)"
varia[q]=packs
declare -a packs

usage[c]="file:dest Copy the <file> to <dest> into the new system"
varia[c]=copy
declare -a copy

. driglibash-args

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
clean "umount '$mnt' -A --recursive"


echo "debootstraping"
run debootstrap --arch "$arch" "$release" "$mnt" "$repo"


echo "copying files"
for file in "${copy[@]}" ; do
  from=$(cut -d ':' -f 1)
  to=$(cut -d ':' -f 2)
  run cp "$from" "$mnt/$to"
done


echo "Preparing chroot"
run mount -t proc none "$mnt/proc"

# To access physical devices
run mount -o bind /dev "$mnt/dev"
run mount -o bind /sys "$mnt/sys"


echo "Configuring new system"
uuid=$(blkid | grep "$device" | cut -d ' ' -f 2)
run echo -e "proc /proc proc defaults\n$uuid    /    ext4 errors=remount-ro 0 1" > "$mnt/etc/fstab"
run echo "$hostname" > "$mnt/etc/hostname"
run cat > "$mnt/root/.bashrc" <<EOF
PATH=$PATH:/usr/bin:/bin:/sbin:/usr/sbin:/sbin
export DEBIAN_FRONTEND=noninteractive
/usr/bin/setterm -blength 0
EOF


echo "Chrooting"
chroot "$mnt" <<EOF
  apt update  -q -y --force-yes
  apt install -q -y --force-yes linux-image-amd64 console-data grub2 locales $install
  sed  's/#$locale/$locale/g' /etc/locale.gen
  locale-gen
  grub-update
  grub-install "$bloc"
EOF


echo "Installing custom packs"
for pack in "$packs" ; do
  case "$pack" in
    '*sysadmin*')
      echo 'apt install vim openssh-server git' | chroot "$mnt"
    ;;
    '*webserver*')
      echo 'apt install nginx ; systemctl enable nginx ; systemctl start nginx' | chroot "$mnt"
    ;;
    '*network*')
      echo 'git clone https://github.com/dahus/gateway && cd gateway && gateway.sh -i && cd .. && rm -rf gateway' | chroot "$mnt"
    ;;
    *)
      die "pack '$pack' not supported"

esac


echo "Executing custom commands"
for cmd in "${execute[@]}" ; do
  cat "$cmd" | chroot "$mnt"
done


echo "Setting root password"
if [ -n "$password" ] ; then
  echo -e "$password\n$password" | chroot "$mnt"
fi


echo "Cleaning fs"
umount temporary_mount_point/{dev,sys,proc,}
run rm -r "$mnt"

if [ "$arg_test" == "true" ] ; then
  echo "Testing"
  run qemu-system-x86_64 $bloc
fi
clean

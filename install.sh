#!/bin/bash

# https://github.com/adrianamaglio/driglibash
declare -A usage
declare -A varia
driglibash_run_retry=true

version="alpha nightly 0.0.1 pre-release unstable"
summary="$0 [options]"

usage[t]="Start qemu after the installation to test the system"
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
repo="http://localhost:3142/ftp.fr.debian.org/debian"

usage[n]="The hostname"
varia[n]=hostname
hostname="nohost"

usage[p]="Root password"
varia[p]=password
password=toor

usage[l]="System locale"
varia[l]=locale
locale="en_US.UTF-8 UTF-8"

usage[q]="Quickstart packs (sysadmin, webserver, network)"
varia[q]=packs
declare -a packs

usage[c]="file:dest Copy <file> to <dest> into the new system"
varia[c]=copy
declare -a copy

usage[v]="The installed OS starts in RAM"
varia[v]=start_in_ram
start_in_ram=false

usage[d]="The device where we will install the system"
varia[d]=root_device
root_device=

usage[b]="The device where we will install the boot"
varia[b]=boot_device
boot_device=

usage[k]="Keep everything in place and wait before cleaning. Used to debug."
varia[k]=keep_and_wait
keep_and_wait=false

usage[o]="Only mount target"
varia[o]=only_mount
only_mount=false

. driglibash-args

###############################################################################
#                              Actual script
###############################################################################

chroot_run(){
  run echo "$@" | chroot "$mnt"
}

mount_all(){
  mount_partitions
  mount_misc
}

mount_partitions(){
  run mkdir -p "$mnt"
  run mount "$device" "$mnt"
  clean "umount $mnt -A --recursive"
}

mount_misc(){
  run mount -t proc none "$mnt/proc"
  # To access physical devices
  run mount -o bind /dev "$mnt/dev"
  run mount -o bind /sys "$mnt/sys"
}

wait_for_user(){
  run echo "$1"
  run echo "Appuyer sur entrer pour reprendre le programme"
  read
}

root_or_die

echo "Choosing device"
device="$root_device"
# The bloc device is where grub will be physically installed
bloc=$(echo "$boot_device" | grep -o "^[a-zA-Z/]*")

if "$only_mount" ; then
  mount_all
  wait_for_user
  die 'End of dry script'
fi

echo "Formating"
# TODO no confirmation ?
run mkfs.ext4 "$root_device"
run mkfs.fat "$boot_device"


echo "Mounting partitions"
mount_partitions

echo "debootstraping"
run debootstrap --arch "$arch" "$release" "$mnt" "$repo"

echo "copying files"
for file in "${copy[@]}" ; do
  from=$(cut -d ':' -f 1)
  to=$(cut -d ':' -f 2)
  run cp "$from" "$mnt/$to"
done

echo "Mounting additionnal items"
mount_misc

echo "Configuring new system"
uuid=$(blkid | grep "$device" | cut -d ' ' -f 2)
run echo -e "proc /proc proc defaults\n$uuid    /    ext4 errors=remount-ro 0 1" > "$mnt/etc/fstab"
run echo "$hostname" > "$mnt/etc/hostname"
run cat > "$mnt/root/.bashrc" <<EOF
PATH=$PATH:/usr/bin:/bin:/sbin:/usr/sbin:/sbin
export DEBIAN_FRONTEND=noninteractive
/usr/bin/setterm -blength 0
EOF

if "$start_in_ram" ; then
  # TODO in live-initramfs; add 'toram' to your boot parameters.
  echo start in ram not implemented not implemented
fi



echo "Chrooting"
chroot "$mnt" <<EOF
  apt-get update  -q -y 
  apt-get install -q -y linux-image-amd64 console-data grub2 locales $install
  echo "$locale" > "/etc/locale.gen"
  locale-gen
  update-grub
  grub-install "$bloc"
EOF


echo "Installing custom packs"
for pack in "$packs" ; do
  if [ -n "$pack" ] ; then
  case "$pack" in
    *sysadmin*)
      chroot_run 'apt install vim openssh-server git'
      chroot_run 'git clone https://github.com/adrianamaglio/driglibash && cd driglibash && cp driglibash-* /usr/bin && cd .. && rm -rf driglibash'
    ;;
    *webserver*)
      echo 'Nginx will be installed, just add your webapp conf in /etc/nginx/sites-enabled'
      chroot_run 'apt install nginx ; systemctl enable nginx ; systemctl start nginx'
    ;;
    *network*)
      chroot_run 'git clone https://github.com/dahus/gateway && cd gateway && gateway.sh -i && cd .. && rm -rf gateway'
    ;;
    *)
      die "pack '$pack' not supported"
  esac
  fi
done


echo "Executing custom commands"
for cmd in "${execute[@]}" ; do
  chroot_run "$cmd"
done


echo "Setting root password"
if [ -n "$password" ] ; then
  chroot_run "echo -e \"$password\n$password\" | passwd"
fi

if "$keep_and_wait" ; then
  wait_for_user
fi

echo "Cleaning fs"
clean


if [ "$arg_test" != "false" ] ; then
  echo "Testing"
  run qemu-system-x86_64 $bloc
fi

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

usage[N]="Network configuration format: interface-ip/mask-gateway . If ip is 'dhcp' interface will query dhcp server."
varia[N]=network
network=

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

usage[p]="Root password. Will be read from stdin if empty."
varia[p]=password
password=

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
varia[o]=dry
dry=false

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
  run mount "$root_device" "$mnt"
  if [ -n "$boot_device" ] ; then
    run mkdir -p "$mnt/boot"
    run mount "$boot_device" "$mnt/boot"
  fi
  clean "umount $mnt -A --recursive"
}

mount_misc(){
  run mount -t proc none "$mnt/proc"
  # To access physical devices
  run mount -o bind /dev "$mnt/dev"
  run mount -o bind /sys "$mnt/sys"
  # mount /dev/pts ? apt install complain about its absence
}

wait_for_user(){
  section "Time for a pause"
  run echo "Press 'Enter' to continue"
  read
}

try_test(){
  if [ "$arg_test" != "false" ] ; then
    section "Testing installed system"
    run qemu-system-x86_64 "$bloc"
  fi
}

root_or_die

section "Choosing device"
# The bloc device is where grub will be physically installed
bloc=$(echo "$boot_device" | grep -o "^[a-zA-Z/]*")

if "$dry" ; then
  section "Dry Run - mount"
  mount_all
  wait_for_user
  try_test
  die 'End of dry script'
fi

section "Reading password"
if [ -z "$password" ] ; then
  read password
fi

section "Formating"
# TODO no confirmation ?
run mkfs.ext4 "$root_device"
run mkfs.ext2 "$boot_device"


section "Mounting partitions"
mount_partitions

section "debootstraping"
run debootstrap --arch "$arch" "$release" "$mnt" "$repo"

# boot crypted
section "Installing cryptsetup in initramfs"
run echo 'CRYPTSETUP=y' >> /etc/cryptsetup-initramfs/conf-hook
#run cp key "$mnt/root/"
#run echo 'FILES="/root/key"' >> /etc/initramfs-tools/initramfs.conf
#run update-initramfs -ut
#echo "$mnt/etc/initramfs-tools/conf.d/cryptsetup" <<EOF
## This will setup non-us keyboards in early userspace,
## necessary for punching in passphrases.
#KEYMAP=y
#
## force busybox and cryptsetup on initramfs
#BUSYBOX=y
#CRYPTSETUP=y
#
## and for systems using plymouth instead, use the new option
#FRAMEBUFFER=y
#EOF
echo 'export CRYPTSETUP=y' >> "$mnt/etc/environment"
#echo 'export FILES="./key"' >> "$mnt/etc/initramfs-tools/initramfs.conf"
chroot_run 'update-initramfs -ut'


section "copying files"
for file in "${copy[@]}" ; do
  from=$(cut -d ':' -f 1)
  to=$(cut -d ':' -f 2)
  run cp "$from" "$mnt/$to"
done


section "Mounting additionnal items"
mount_misc

section "Configuring new system"
uuid=$(blkid | grep "$root_device" | cut -d ' ' -f 2)
run echo -e "proc /proc proc defaults\n$uuid    /    ext4 errors=remount-ro 0 1" > "$mnt/etc/fstab"
# TODO set noauto to /boot if needed

# Set hostname
run echo "$hostname" > "$mnt/etc/hostname"

# Fix path and remove noisy beep
run cat > "$mnt/root/.bashrc" <<EOF
PATH=$PATH:/usr/bin:/bin:/sbin:/usr/sbin:/sbin
/usr/bin/setterm -blength 0
EOF
# Be sure this fucking beep is gone
echo 'set bell-style none' >> "$mnt/etc/inputrc"
# TODO find a third method to kill this doomed beep


section "Set up networking"
# Networking can be eth0-dhcp or eth0-10.0.0.1/24-10.0.0.254
# iface-ip-gateway
if [ -n "$network" ] ; then
  # Disable the unpredictable naming (since we are not on the future host)
  run ln -s /dev/null "$mnt/etc/udev/rules.d/80-net-setup-link.rules"

  interface="$(echo "$static_network" | cut -d '-' -f 1)"
  ip="$(echo "$static_network" | cut -d '-' -f 2)"
  netmask="$(ipcalc $ip -n |grep Netmask| cut -d ' ' -f 4)"
  ip="$(echo "$static_network" | cut -d '/' -f 1)"
  gateway="$(echo "$static_network" | cut -d '-' -f 3)"

  if [ "$ip" = "dhcp" ] ; then
    run cat >> "$mnt/etc/network/interfaces" <<EOF
      auto eth0
      allow-hotplug eth0
      iface $interface inet dhcp
EOF
  else
    run cat >> "$mnt/etc/network/interfaces" <<EOF
      allow-hotplug $interface
      iface $interface inet static
        address $ip
        netmask $netmask
        gateway $gateway
EOF
  fi
fi


section "Creating root SSH key to connect"
ssh_key_passphrase=="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 200)"
run ssh-keygen -b 4096 -f ../ssh/$hostname -P "$ssh_key_passphrase"
run mkdir -p "$mnt/root/.ssh/"
cat ../ssh/$hostname.pub >> "$mnt/root/.ssh/authorized_keys"
run sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/g' "$mnt/etc/ssh/sshd_config"
cat > ../ssh/config <<EOF
Host $hostname
  HostName $ip
  User root
  IdentityFile "$(pwd)/../ssh/$hostname"
EOF


if "$start_in_ram" ; then
  # TODO in live-initramfs; add 'toram' to your boot parameters.
  echo 'start in ram not implemented'
fi



section "Installing selected software"
chroot "$mnt" <<EOF
  export DEBIAN_FRONTEND=noninteractive
  apt-get update  -q -y 
  apt-get install -q -y linux-image-amd64 console-data grub2 locales $install
EOF

section "Installing custom packs"
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
  else
    echo "No package selected"
  fi
done

section "Generating locales"
chroot "$mnt" <<EOF
  echo "$locale" > "/etc/locale.gen"
  locale-gen
EOF

section "Installing grub"
chroot "$mnt" <<EOF
  update-grub
  grub-install "$bloc"
EOF

section "Executing custom commands"
for cmd in "${execute[@]}" ; do
  chroot_run "$cmd"
done

section "Setting root password"
if [ -n "$password" ] ; then
  chroot_run "echo -e \"$password\n$password\" | passwd"
fi

if "$keep_and_wait" ; then
  wait_for_user
fi

section "Cleaning fs"
clean

try_test

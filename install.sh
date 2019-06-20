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
#repo=
#repo="http://ftp.fr.debian.org/debian"
repo="http://localhost:3142/ftp.fr.debian.org/debian"

usage[n]="The hostname"
varia[n]=hostname
hostname="nohost"

#usage[p]="Root password. Will be read from stdin if empty."
#varia[p]=password
#password=

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


usage[b]="The device where grub will be installed"
varia[b]=boot_device
boot_device=

usage[k]="Keep everything in place and wait before cleaning. Used to debug."
varia[k]=keep_and_wait
keep_and_wait=false

usage[o]="Only mount target"
varia[o]=dry
dry=false

usage[O]="Secret output directory"
varia[O]=secret_dir
secret_dir="./debian-secrets"

. driglibash-args

###############################################################################
#                              Actual script
###############################################################################

chroot_run(){
  run echo "$@" | chroot "$mnt"
  if [ "$?" -ne 0 ] ; then
    die "Error, chroot command [$@] exited with code '$?'"
  fi
}

wait_for_user(){
  section "Time for a pause"
  run echo "Press 'Enter' to continue"
  read
}

mount_misc(){
  run mkdir -p "$mnt"/{proc,dev,sys}
  run mount -t proc none "$mnt/proc"
  # To access physical devices
  run mount -o bind /dev "$mnt/dev"
  run mount -o bind /sys "$mnt/sys"
  # mount /dev/pts ? apt install complain about its absence
}

root_or_die


section "Testing for existing secrets"
secret_dir="$(realpath -m "$secret_dir/$hostname")"
if ! [ -d "$secret_dir" ] ; then
  run mkdir -p "$secret_dir"
fi
if [ -n "$(ls -A $secret_dir)" ]; then
  die "Secret dir '$secret_dir' is not empty"
fi


section "debootstraping"
# Debootstrap may fail when the target is an existing system
if [ -n "$(ls -A $mnt)" ]; then
  die "Secret dir '$mnt' is not empty. Won’t deboustrap it."
fi
run debootstrap --verbose --arch "$arch" "$release" "$mnt" "$repo"


section "Mounting additionnal items"
mount_misc


section "Installing selected software"
#XXX use chroot_run
chroot "$mnt" <<EOF
  export DEBIAN_FRONTEND=noninteractive
  apt-get update  -q -y 
  apt-get install -q -y linux-image-amd64 console-data grub2 locales sudo lvm2 $install
EOF
# TODO watershed ?


section "copying files"
for file in "${copy[@]}" ; do
  from=$(cut -d ':' -f 1)
  to=$(cut -d ':' -f 2)
  run cp "$from" "$mnt/$to"
done



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


section "Set up networking"
# Networking can be eth0-dhcp or eth0-10.0.0.1/24-10.0.0.254
# iface-ip-gateway
if [ -n "$network" ] ; then
  # Disable the unpredictable naming (since we are not on the future host)
  run ln -s /dev/null "$mnt/etc/udev/rules.d/80-net-setup-link.rules"

  interface="$(echo "$network" | cut -d '-' -f 1)"
  ip="$(echo "$network" | cut -d '-' -f 2)"
  netmask="$(ipcalc $ip -n |grep Netmask| cut -d ' ' -f 4)"
  ip="$(echo "$network" | cut -d '/' -f 1)"
  gateway="$(echo "$network" | cut -d '-' -f 3)"

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


# TODO add dyndn service


if "$start_in_ram" ; then
  # TODO in live-initramfs; add 'toram' to your boot parameters.
  echo 'start in ram not implemented'
fi


section "Installing custom packs"
for pack in "$packs" ; do
  if [ -n "$pack" ] ; then
  case "$pack" in
    *sysadmin*)
      chroot_run 'export DEBIAN_FRONTEND=noninteractive ; apt install -y vim openssh-server git'
      chroot_run 'git clone https://github.com/adrian-amaglio/driglibash && cd driglibash && cp driglibash-* /usr/bin && cd .. && rm -rf driglibash'
    ;;
    *webserver*)
      echo 'Nginx will be installed, just add your webapp conf in /etc/nginx/sites-enabled'
      chroot_run 'DEBIAN_FRONTEND=noninteractive apt install nginx ; systemctl enable nginx ; systemctl start nginx'
    ;;
    *)
      die "pack '$pack' not supported"
  esac
  else
    echo "No package selected"
  fi
done


section "Creating root SSH key to connect"
ssh_key_passphrase=="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 200)"
run ssh-keygen -b 4096 -f "$secret_dir/$hostname" -P "$ssh_key_passphrase"
run mkdir -p "$mnt/root/.ssh/"
run mkdir -p "$secret_dir"
cat "$secret_dir/$hostname.pub" >> "$mnt/root/.ssh/authorized_keys"
run sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/g' "$mnt/etc/ssh/sshd_config"
cat > "$secret_dir/ssh_conf" <<EOF
Host $hostname
  HostName $ip
  User root
  IdentityFile "$secret_dir/$hostname"
EOF


section "Generating locales"
chroot_run echo "$locale" > "/etc/locale.gen"
chroot_run locale-gen


section "Installing grub"
chroot_run update-grub
chroot_run grub-install "$boot_device"


section "Executing custom commands"
for cmd in "${execute[@]}" ; do
  chroot_run "$cmd"
done


if [ "$arg_test" != "false" ] ; then
  section "Testing installed system"
  run qemu-system-x86_64 "$boot_device"
fi

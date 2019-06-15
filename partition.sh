#!/bin/bash

# https://github.com/adrianamaglio/driglibash
declare -A usage
declare -A varia
driglibash_run_retry=true

version="alpha nightly 0.0.1 pre-release unstable"
summary="$0 [options]"

usage[r]="The device that will be root"
varia[r]=root_device
root_device=

usage[R]="Root mode (simple/luks/plain)."
varia[R]=root_mode
root_mode=plain

usage[b]="The device that will be boot"
varia[b]=boot_device
boot_device=

usage[s]="Soft: do not write changes on disks"
varia[s]=soft
soft=false

usage[p]="Path of the temporar mount point"
varia[p]=mnt
mnt="temporary_mount_point"

. driglibash-args

root_or_die

wait_for_user(){
  section "Partitions are mounted"
  run echo "Press 'Enter' to continue"
  read
}

mount_partitions(){
  run mkdir -p "$mnt"
  run mount "$root_part" "$mnt"
  if [ -n "$boot_part" ] ; then
    run mkdir -p "$mnt/boot"
    run mount "$boot_part" "$mnt/boot"
  fi  
  clean pre "umount $mnt -A --recursive"
}

mount_misc(){
	run mkdir -p "$mnt"/{proc,dev,sys}
  run mount -t proc none "$mnt/proc"
  # To access physical devices
  run mount -o bind /dev "$mnt/dev"
  run mount -o bind /sys "$mnt/sys"
  # mount /dev/pts ? apt install complain about its absence
}

mount_all(){
  mount_partitions
  mount_misc
}


if [ -n "$root_device" ] ; then
  section "Preparing root device"
  if [ "$root_mode" = "plain" ] ; then
	  root_part="/dev/mapper/crypt"
	  if [ ! -e "$root_part" ] ; then
      run cryptsetup --cipher aes-xts-plain64 open --type plain "$root_device" crypt
      clean post 'cryptsetup close crypt'
    fi
  elif [ "$root_mode" = "simple" ] ; then
    root_part="$root_device"1
    run parted -s "$root_device" mklabel msdos -- mkpart primary ext4 1 -1
  elif [ "$root_mode" = "luks" ] ; then
    die 'luks mode is not implemented'
    pass=
    # TODO
  fi

	if ! "$soft" ; then
    run mkfs.ext4 "$root_part"
  fi
else
  die "No root device supplied"
fi


if [ -n "$boot_device" ] ; then
  section "Preparing boot device"
	boot_part="$boot_device"1
	if ! "$soft" ; then
    run parted -s "$boot_device" mklabel msdos -- mkpart primary ext2 1 -1
    run mkfs.ext2 "$boot_part"
  fi
fi


mount_all

wait_for_user

clean

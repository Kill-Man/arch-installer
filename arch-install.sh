#!/bin/sh

# This script is meant to be completely POSIX compliant so that a change of the
# default shell for the Arch installer ISO doesn't break anything. If this is
# not the case, or this script is just broken, feel free to make a pull request
# or something.

## Load defaults if there are any
while getopts d: flags; do
	case $flags in
		d) PATH=$PATH:.; . "$OPTARG";; # need to add to path since /bin/sh doesn't read from current dir
		?) echo "Usage: $0 [-d defaultfile]"; exit 1;;
	esac
done

## Colors
nocolor='\033[0m'
red='\033[31m'
green='\033[32m'

## Helper functions
# prints [DEFAULT] and returns 0 if passed variable is non-empty, does nothing and returns 1 otherwise
has-default() {
	[ "$1" ] && printf "${green}[DEFAULT]${nocolor} "
}

# returns 0 if input is y or yes (case insensitive) and 1 otherwise
yes() {
	read yes_or_no
	case $(echo "$yes_or_no" | awk '{print tolower($0)}') in
		y|yes) 0;;
		*) 1;;
	esac
}

## Set keyboard layout
if has-default "$keyboard_layout"; then
	if loadkeys "$keyboard_layout" 2>/dev/null; then
		echo "Keyboard layout set to $keyboard_layout"
	else
		echo "${red}[WARNING]${nocolor} Keyboard layout $keyboard_layout not found; defaulting to us"
	fi
else
	while true; do
		printf 'Enter keyboard layout to use (nothing for default (US QWERTY), ? for list of options): '
		read keyboard_layout
		case "$keyboard_layout" in
			'?') find /usr/share/kbd/keymaps -name '*.map.gz' | awk -F '/' '{print substr($NF, 1, length($NF)-length(".map.gz"))}' | sort | less;;
			'') echo Keeping default US QWERTY layout; break;;
			*) loadkeys "$keyboard_layout" 2>/dev/null && break || echo "Layout $keyboard_layout not found";;
		esac
	done
fi

## Connect to the internet
echo 'Detecting internet connection...'
if ping -q -c 1 -W 1 8.8.8.8 2>/dev/null; then
	echo '...internet connection detected'
else
	echo '...internet connection not detected'
	echo 'Attempting to find network device'
	network_device=$(ip a | awk '/state UP/{print substr($2, 1, length($2)-1); exit}')
	if [ "$network_device" ]; then
		echo "Found network device $network_device"
	else
		echo 'Network device could not be found automatically'
		while true; do
			ip a | awk '/^[0-9]+:/{print $1 " " substr($2, 1, length($2)-1)}'
			printf 'Select a device from the above list (? for more detailed list): '
			read device_num
		  if [ "$device_num" = '?' ]; then
				ip a
			elif [ "$device_num" -gt 0 ] 2>/dev/null && [ "$device_num" -le $(awk '/^[0-9]+:/{count++} END{print count}') ]; then
				network_device=$(ip a | awk "/^$device_num:/{print substr(\$2, 1, length(\$2)-1); exit}")
				break
			else
				echo 'Enter a number corresponding to a device in the list'
		done
	fi
	iwctl station "$network_device" scan
	while true; do
		iwctl station "$network_device" get-networks
		echo "Listed above are networks detected by $network_device"
		printf 'Enter the name of the network: '
		read network_name
		printf 'Does the network have a passphrase? [Y/n] '
		if yes; then
			printf "Enter $network_name's passphrase: "
			read network_passphrase
			if iwctl "--passphrase=$network_passphrase" station "$network_device" connect "$network_name"; then
				echo "Connected to $network_name"
				break
			fi
		else
			if iwctl station "$network_device" connect "$network_name"; then
				echo "Connected to $network_name"
				break
			fi
		fi
		echo 'Something went wrong, did you enter the credentials correctly?'
	done
fi

## Update the system clock
echo 'Synchronizing time with network clock'
timedatectl set-ntp true

## Get disk to be used
if has-default "$block_device"; then
	if lsblk | awk '/disk/{print $1}' | grep -Fx "$block_device" > /dev/null; then
		"Block device /dev/$block_device will be used"
	else
		"${red}[ERROR]${nocolor} Block device /dev/$block_device not found"
		exit 2
	fi
else
	while true; do
		lsblk | awk '/disk/{print $1}'
		printf 'Enter the name of the block device to write to (ex. sdX, ? for more detailed list): '
		read block_device
		case block_device in
			'?') fdisk -l;;
			*)
				if lsblk | awk '/disk/{print $1}' | grep -Fx "$block_device" >/dev/null; then
					break
				else
					"Device /dev/$block_device not found"
				fi
				;;
		esac
	done
fi

## Save partition table
echo 'Attempting to back up partition table...'
if sfdisk -d "/dev/$block_device" > "${block_device}.dump" 2>/dev/null; then
	echo '...done'
else
	echo '...no table to save (you can safely partition automatically)'
fi

## Detect UEFI
if ls /sys/firmware/efi/efivars >/dev/null 2>&1; then
	uefi_mode=true
	echo 'UEFI mode detected'
else
	echo 'BIOS mode detected'
fi

## Get partition method
if has-default "$partition_method"; then
  case "$partition_method" in
		automatic|manual) echo "$partition_method partitioning will be done";;
		*)
			echo "Invalid partitioning method $partition_method, falling back to manual"
			partition_method='manual'
	esac
else
	while true; do
		echo '${red}!!WARNING!!${nocolor} automatic partitioning will wipe the whole drive'
		printf 'Would you like manual or automatic partitioning: '
		read partition_method
		case "$partition_method" in
			manual|automatic) break;;
			*) echo "Invalid partitioning method $partition_method"
		esac
	done
fi

## Partition the disk
while true; do
	if [ "$partition_method" = 'automatic' ]; then
		if has-default "$swap_size"; then
			echo "Swap size will be $swap_size"
		else
			while ! echo "$swap_size" | grep -E '[0-9]+(M|G)'; do
				if [ "$swap_size" ]; then
					echo 'Invalid swap size'
				fi
				printf 'Enter swap size (must end with M or G, such as 8G or 512M): '
				read swap_size
			done
		fi
		if [ "$uefi_mode" ]; then
			cat << EOF | gdisk "/dev/$block_device"
o
Y
n


+550M
ef00
n


+$swap_size
8200
n



8300
w
Y
EOF
			efi_part="/dev/${block_device}1"
			swap_part="/dev/${block_device}2"
			root_part="/dev/${block_device}3"
		else
			cat << EOF | fdisk "/dev/$block_device"
o
n



+$swap_size
t

82
n




t

83
w
EOF
			swap_part="/dev/${block_device}1"
			root_part="/dev/${block_device}2"
		fi
	else
		echo 'Launching partition software'
		echo 'The script will continue when you finish'
		[ "$uefi_mode" ] && gdisk "/dev/$block_device" || fdisk "/dev/$block_device"
		while true; do
			fdisk -l "/dev/$block_device"
			if [ "$uefi_mode" ]; then
				printf 'Enter the EFI partition number: '
				read efi_part
			fi
			printf 'Enter the swap partition number: '
			read swap_part
			printf 'Enter the root partition number: '
			read root_part
			if [ "$uefi_mode" ] && [ $(lsblk | grep -E "${block_device}(${swap_part}|${root_part}|${efi_part})") -eq 3 ] || [ $(lsblk | grep -E "${block_device}(${swap_part}|${root_part})") -eq 2 ]; then
				break
			else
				echo 'One of those partition numbers do not exist'
			fi
		done
	fi
	fdisk -l "/dev/$block_device"
	printf "Is this how you want $block_device to be partitioned?"
	yes && break || echo 'Restoring partition table'; sfdisk "/dev/$block_device" < "${block_device}.dump"
done

## Formatting and mounting partitions
if [ "$uefi_mode" ]; then
	mkfs.fat -F32 "$efi_part"
	mkdir /mnt/efi
	mount "$efi_part" /mnt/efi
fi
mkswap "$swap_part"
swapon "$swap_part"
mkfs.ext4 "$root_part"
mount "$root_part" /mnt

## Installing essential packages
echo 'Bootstrapping pacman...'
pacstrap /mnt base linux linux-firmware
echo '...bootstrapping complete'

echo 'Generating fstab file'
genfstab -U /mnt >> /mnt/etc/fstab

## TODO chroot

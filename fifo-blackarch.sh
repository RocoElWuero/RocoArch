#!/usr/bin/env bash

status="${1}"
NORMAL='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
alias pause="read -s -n 1 -p 'Press any key to continue . . .' && echo ''"

contains_element() {
	#check if an element exist in a string
	for e in "${@:2}"; do [[ "${e}" == "${1}" ]] && break; done
}
saveEfi() {
	while true; do
		lsblk | grep -Ev "sr0|loop" && echo -e "${GREEN}=====================================${NORMAL}" && fdisk -l | head --lines=-6
		unset devices
		devices=($(fdisk -l | grep -E "^/dev/.*" | awk '{print $1}'))
		read -r "What is your EFI partition? " efi
		pause
		if [[ ${device} =~ ^[0-9]+$ && ${device} -ge 0 && ${device} -le $((${#devices[*]} - 1)) ]]; then
			device="${devices[${device}]}"
			break
		elif [[ ${device} =~ ^/dev/[a-z][a-z|0-9]+$ ]]; then
			break
		else
			clear
		fi
	done
	while true; do
		lsblk | grep -Ev "sr0|loop" && echo -e "${GREEN}=====================================${NORMAL}" && fdisk -l | head --lines=-6
		unset devices
		devices=($(fdisk -l | grep -E "^/dev/.*" | awk '{print $1}'))
		read -r "What is your Windows DATA partition? " data
		if [[ ${device} =~ ^[0-9]+$ && ${device} -ge 0 && ${device} -le $((${#devices[*]} - 1)) ]]; then
			device="${devices[${device}]}"
			break
		elif [[ ${device} =~ ^/dev/[a-z][a-z|0-9]+$ ]]; then
			break
		else
			clear
		fi
	done
	mount "${data}" /mnt
	touch "/mnt/${efi/\/dev\//}.dd"
	shred -zvuf "/mnt/${efi/\/dev\//}.dd"
	dd if="${efi}" of="/mnt/${efi/\/dev\//}.dd" conv=noerror,sync #https://poesiabinaria.net/2015/10/9-trucos-para-manejar-cadenas-de-caracteres-en-bash-y-no-morir-en-el-intento/
	[[ "$(sha512sum "/mnt/${efi/\/dev\//}.dd")" != "$(sha512sum "${efi}")" ]] && echo -e "${RED}Error Backup to EFI partition! => 1${NORMAL}" && exit 1
	umount "${data}"
	echo -e "${GREEN}Successfully EFI mode!${NORMAL}"
}
check_trim() { #https://www.compuhoy.com/como-habilito-trim-en-linux/
	[[ -n $(hdparm -I /dev/sda | grep "TRIM" 2>/dev/null) ]] && TRIM=1
}
verifyEfiBoot() {
	[[ ! -d /sys/firmware/efi/efivars/ ]] && echo -e "${RED}Error in EFI mode! => 2${NORMAL}" && exit 2
	mount -t efivarfs efivarfs /sys/firmware/efi/efivars
	echo -e "${GREEN}Successfully EFI mode!${NORMAL}"
}
updateDateAndTime() {
	timedatectl status
	[[ $(timedatectl status | grep "Time zone: UTC") ]] && timedatectl set-timezone America/Mexico_City
	[[ ${?} -ne 0 ]] && echo -e "${RED}Error in date and time update! => 3${NORMAL}" && exit 3
	echo ""
	timedatectl status
	echo -e "${GREEN}Successfully date and time updated!${NORMAL}"
}
selectKeymap() {
	echo -e "${BLUE}KEYMAP - https://wiki.archlinux.org/index.php/KEYMAP${NORMAL}"
	loadkeys en
	[[ ${?} -ne 0 ]] && echo -e "${RED}Error in Keymap! => 4${NORMAL}" && exit 4
	echo -e "${GREEN}Successfully keymap selected!${NORMAL}"
}
configure_mirrorlist() {
	# Modified from: https://stackoverflow.com/a/24628676
	echo -e "${BLUE}MIRRORLIST - https://wiki.archlinux.org/index.php/Mirrors${NORMAL}"
	[[ -f /etc/pacman.d/mirrorlist ]] && mv /etc/pacman.d/mirrorlist /etc/pacman.d/.mirrorlist.bkp
	reflector --country 'United States' --sort rate --protocol http --protocol https --save /etc/pacman.d/mirrorlist
	[[ ${?} -ne 0 ]] && echo -e "${RED}Error in Mirrorlist! => 5${NORMAL}" && exit 5
	echo -e "${GREEN}Successfully downloaded mirrorlist!${NORMAL}"
	# allow global read access (required for non-root yaourt execution)
	chmod +r /etc/pacman.d/mirrorlist
	vim  /etc/pacman.d/mirrorlist
}
create_partition() {
	while true; do
		lsblk | grep -Ev "sr0|loop" && echo -e "${GREEN}=====================================${NORMAL}" && fdisk -l | head --lines=-6
		devices=($(fdisk -l | grep -E "^Disk /dev/.*:" | grep -v "loop" | awk '{print $2}' | tr ":" " "))
		i=0
		for device in ${devices[*]}; do
			echo "${i}) ${devices[${i}]}"
			i=$((i+1))
		done && i=1
		read -p "What is your device to partition/format? " device
		if [[ ${device} =~ ^[0-9]+$ && ${device} -ge 0 && ${device} -le $((${#devices[*]} - 1)) ]]; then
			device="${devices[${device}]}"
			break
		elif [[ ${device} =~ ^/dev/[a-z][a-z|0-9]+$ ]]; then
			break
		fi
	done
	echo -e "${GREEN}Device ${device} select!${NORMAL}"
	hdparm -i "${device}"
	fdisk -l "${device}"
	echo -e "${RED}You should select the partition in mode \"dos\" and with ONE Partition (because with the Logical Volumes will be SEVERAL)${NORMAL}"
	pause
	cfdisk "${device}"
	[[ ${?} -ne 0 ]] && echo -e "${RED}Error in Cfdisk! => 6${NORMAL}" && exit 6
	echo -e "${GREEN}Successfully partitioned!${NORMAL}"
	lsblk
}
setup_luks() {
	echo -e "${BLUE}LUKS - https://wiki.archlinux.org/index.php/LUKS${NORMAL}"
	echo -e "${GREEN}The Linux Unified Key Setup or LUKS is a disk-encryption specification created by Clemens Fruhwirth and originally intended for Linux.${NORMAL}"
	echo -e "${RED}\tDo not use this for boot partitions.${NORMAL}"

	echo -e "${RED}\tCapital letters is OPPER CASE.${NORMAL}"
	cryptsetup --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 5000 --use-random --verify-passphrase luksFormat "${device}"
	[[ ${?} -ne 0 ]] && echo -e "${RED}Error in Cryptsetup ciphered! => 7${NORMAL}" && exit 7
	echo -e "${GREEN}Successfully Cipher!${NORMAL}"
	if [[ $TRIM -eq 1 ]]; then
		cryptsetup open --type luks --allow-discards "${device}" crypt
		[[ ${?} -ne 0 ]] && echo -e "${RED}Error in Cryptsetup open! => 7${NORMAL}" && exit 7
		echo -e "${GREEN}Successfully Cryptsetup opened!${NORMAL}"
	else
		cryptsetup open --type luks "${device}" crypt
		[[ ${?} -ne 0 ]] && echo -e "${RED}Error in Cryptsetup open! => 7${NORMAL}" && exit 7
		echo -e "${GREEN}Successfully Cryptsetup opened!${NORMAL}"
	fi
	LUKS=1
	LUKS_DISK=$(echo "${OPT}" | sed 's/\/dev\///')
}
: << block
	setup_luks() { #================================================================================================================================
		echo -e "$ {BLUE}LUKS - https://wiki.archlinux.org/index.php/LUKS$ {NORMAL}"
		echo -e "$ {GREEN}The Linux Unified Key Setup or LUKS is a disk-encryption specification created by Clemens Fruhwirth and originally intended for Linux. {NORMAL}"
		echo -e "$ {RED}\tDo not use this for boot partitions.$ {NORMAL}"
		block_list=($ (lsblk | grep 'part' | awk '{print "/dev/" substr($ 1,3)}'))
		PS3="$ prompt1"
		echo -e "Select partition:"
		select OPT in "$ {block_list[@]}"; do
			if contains_element "$ OPT" "$ {block_list[@]}"; then
				echo -e "$ {RED}\tCapital letters is OPPER CASE.$ {NORMAL}"
				cryptsetup --cipher aes-xts-plain64 --key-size 512 --hash sha512 --iter-time 5000 --use-random --verify-passphrase luksFormat "$ OPT"
				[[ $ {?} -ne 0 ]] && echo -e "$ {RED}Error in Cryptsetup ciphered!$ {NORMAL}" && exit 6
				echo -e "$ {GREEN}Successfully Cipher!$ {NORMAL}"
				if [[ $ TRIM -eq 1 ]]; then
					cryptsetup open --type luks --allow-discards "$ OPT" crypt
					[[ $ {?} -ne 0 ]] && echo -e "$ {RED}Error in Cryptsetup open!$ {NORMAL}" && exit 6
					echo -e "$ {GREEN}Successfully Cryptsetup opened!$ {NORMAL}"
				else
					cryptsetup open --type luks "$ OPT" crypt
					[[ $ {?} -ne 0 ]] && echo -e "$ {RED}Error in Cryptsetup open!$ {NORMAL}" && exit 6
					echo -e "$ {GREEN}Successfully Cryptsetup opened!$ {NORMAL}"
				fi
				LUKS=1
				LUKS_DISK=$ (echo "$ {OPT}" | sed 's/\/dev\///')
				break
			elif [[ $ OPT == "Cancel" ]]; then
				break
			else
				invalid_option
			fi
		done
	}
block
setup_lvm() {
	echo -e "${BLUE}LVM - https://wiki.archlinux.org/index.php/LVM${NORMAL}"
	echo -e "${GREEN}LVM is a logical volume manager for the Linux kernel; it manages disk drives and similar mass-storage devices.${NORMAL}"
	echo -e "${RED}\tLast partition will take 100% of free space left.${NORMAL}"

	pvcreate /dev/mapper/crypt
	pvs
	pause
	vgcreate lvm /dev/mapper/crypt
	pvs
	pause

	number_partitions=0
	while true; do
		read -p "Enter the NUMBER of logical volumes/partitions (bigger than 1) [ex: / /home swap etc. ]: " number_partitions
		[[ ${number_partitions} -gt 1 ]] && break
	done
	i=1
	#while [[ ${i} -le ${number_partitions} ]]; do
	pvs
	lsblk | grep -Ev "sr0|loop" && echo -e "${GREEN}=====================================${NORMAL}" && fdisk -l | head --lines=-6
	echo -e "${GREEN}1024 MB = 1 GB\n2048 MB = 2 GB\n4096 MB = 4 GB\n8192 MB = 8 GB${NORMAL}"
	for ((i=1; i<number_partitions; ++i)); do
		printf "%s" "Enter ${i}ª partition name [ex: home]: "
		read -r partition_name
		if [[ ${i} -eq ${number_partitions} ]]; then
			lvcreate -l 100%FREE lvm -n "${partition_name}"
			lvs
		else
			printf "%s" "Enter ${i}ª partition size [ex: 25G, 200M]: "
			read -r partition_size
			lvcreate -L "${partition_size}" lvm -n "${partition_name}"
			lvs
		fi
		#i=$((i + 1))
	done
	LVM=1
}
: << block
	setup_lvm() { #================================================================================================================================
		echo -e "$ {BLUE}LVM - https://wiki.archlinux.org/index.php/LVM$ {NORMAL}"
		echo -e "$ {GREEN}LVM is a logical volume manager for the Linux kernel; it manages disk drives and similar mass-storage devices.$ {NORMAL}"
		echo -e "$ {RED}\tLast partition will take 100% of free space left.$ {NORMAL}"
		if [[ $ {LUKS} -eq 1 ]]; then
			pvcreate /dev/mapper/crypt
			pvs
			vgcreate lvm /dev/mapper/crypt
			pvs
		else
			block_list=($ (lsblk | grep 'part' | awk '{print "/dev/" substr($1,3)}'))
			PS3="$ prompt1"
			echo -e "Select partition:"
			select OPT in "$ {block_list[@]}"; do
				if contains_element "$ OPT" "$ {block_list[@]}"; then
					pvcreate "$ OPT"
					vgcreate lvm "$ OPT"
					break
				else
					invalid_option
				fi
			done
		fi
		number_partitions=0
		while true; do
			read -p "Enter the number of logical volumes/partitions (bigger than 1): " number_partitions
			[[ $ {number_partitions} -gt 1 ]] && break
		done
		i=1
		#while [[ $ {i} -le $ {number_partitions} ]]; do
		for ((i=1; i<number_partitions; ++i)); do
			printf "%s" "Enter $ iª partition name [ex: home]: "
			read -r partition_name
			if [[ $ i -eq $ number_partitions ]]; then
				lvcreate -l 100%FREE lvm -n "$ {partition_name}"
				lvs
			else
				printf "%s" "Enter $ iª partition size [ex: 25G, 200M]: "
				read -r partition_size
				lvcreate -L "$ {partition_size}" lvm -n "$ {partition_name}"
				lvs
			fi
			#i=$ ((i + 1))
		done
		LVM=1
	}
block
create_partition_scheme() {
	echo -e "${BLUE}https://wiki.archlinux.org/index.php/Partitioning${NORMAL}"
	echo -e "${GREEN}Partitioning a hard drive allows one to logically divide the available space into sections that can be accessed independently of one another.${NORMAL}"
	echo -e "${GREEN}LVM+LUKS${NORMAL}"
	create_partition
	pause
	setup_luks
	pause
	setup_lvm
}
format_partitions() { #================================================================================================================================
	print_title "https://wiki.archlinux.org/index.php/File_Systems"
	print_info "This step will select and format the selected partition where archlinux will be installed"
	print_danger "\tAll data on the ROOT and SWAP partition will be LOST."
	i=0

	block_list=($(lsblk | grep 'part\|lvm' | awk '{print substr($1,3)}'))

	# check if there is no partition
	if [[ ${#block_list[@]} -eq 0 ]]; then
		echo "No partition found"
		exit 0
	fi

	partitions_list=()
	for OPT in "${block_list[@]}"; do
		check_lvm=$(echo "$OPT" | grep lvm)
		if [[ -z $check_lvm ]]; then
			partitions_list+=("/dev/$OPT")
		else
			partitions_list+=("/dev/mapper/$OPT")
		fi
	done

	# partitions based on boot system
	if [[ $UEFI -eq 1 ]]; then
		partition_name=("root" "EFI" "swap" "another")
	else
		partition_name=("root" "swap" "another")
	fi

	select_filesystem() {
		filesystems_list=("btrfs" "ext2" "ext3" "ext4" "f2fs" "jfs" "nilfs2" "ntfs" "reiserfs" "vfat" "xfs")
		PS3="$prompt1"
		echo -e "Select filesystem:\n"
		select filesystem in "${filesystems_list[@]}"; do
			if contains_element "${filesystem}" "${filesystems_list[@]}"; then
				break
			else
				invalid_option
			fi
		done
	}

	disable_partition() {
		#remove the selected partition from list
		unset partitions_list["${partition_number}"]
		partitions_list=("${partitions_list[@]}")
		#increase i
		[[ ${partition_name[i]} != another ]] && i=$((i + 1))
	}

	format_partition() {
		read_input_text "Confirm format $1 partition"
		if [[ $OPTION == y ]]; then
			[[ -z $3 ]] && select_filesystem || filesystem=$3
			mkfs."${filesystem}" "$1" \
				"$([[ ${filesystem} == xfs || ${filesystem} == btrfs || ${filesystem} == reiserfs ]] && echo "-f")" \
				"$([[ ${filesystem} == vfat ]] && echo "-F32")" \
				"$([[ $TRIM -eq 1 && ${filesystem} == ext4 ]] && echo "-E discard")"
			fsck "$1"
			mkdir -p "$2"
			mount -t "${filesystem}" "$1" "$2"
			disable_partition
		fi
	}

	format_swap_partition() {
		read_input_text "Confirm format $1 partition"
		if [[ $OPTION == y ]]; then
			mkswap "$1"
			swapon "$1"
			disable_partition
		fi
	}

	create_swap() {
		swap_options=("partition" "file" "skip")
		PS3="$prompt1"
		echo -e "Select ${BYellow}${partition_name[i]}${Reset} filesystem:\n"
		select OPT in "${swap_options[@]}"; do
			case "$REPLY" in
			1)
				select partition in "${partitions_list[@]}"; do
					#get the selected number - 1
					partition_number=$((REPLY - 1))
					if contains_element "${partition}" "${partitions_list[@]}"; then
						format_swap_partition "${partition}"
					fi
					break
				done
				swap_type="partition"
				break
				;;
			2)
				total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2/1024}' | sed 's/\..*//')
				dd if=/dev/zero of="${MOUNTPOINT}"/swapfile bs=1M count="${total_memory}" status=progress
				chmod 600 "${MOUNTPOINT}"/swapfile
				mkswap "${MOUNTPOINT}"/swapfile
				swapon "${MOUNTPOINT}"/swapfile
				i=$((i + 1))
				swap_type="file"
				break
				;;
			3)
				i=$((i + 1))
				swap_type="none"
				break
				;;
			*)
				invalid_option
				;;
			esac
		done
	}

	check_mountpoint() {
		if mount | grep "$2"; then
			echo "Successfully mounted"
			disable_partition "$1"
		else
			echo "WARNING: Not Successfully mounted"
		fi
	}

	set_efi_partition() {
		efi_options=("/boot/efi" "/boot")
		PS3="$prompt1"
		echo -e "Select EFI mountpoint:\n"
		select EFI_MOUNTPOINT in "${efi_options[@]}"; do
			if contains_element "${EFI_MOUNTPOINT}" "${efi_options[@]}"; then
				break
			else
				invalid_option
			fi
		done
	}

	while true; do
		PS3="$prompt1"
		if [[ ${partition_name[i]} == swap ]]; then
			create_swap
		else
			echo -e "Select ${BYellow}${partition_name[i]}${Reset} partition:\n"
			select partition in "${partitions_list[@]}"; do
				#get the selected number - 1
				partition_number=$((REPLY - 1))
				if contains_element "${partition}" "${partitions_list[@]}"; then
					case ${partition_name[i]} in
					root)
						ROOT_PART=$(echo "${partition}" | sed 's/\/dev\/mapper\///' | sed 's/\/dev\///')
						ROOT_MOUNTPOINT="${partition}"
						format_partition "${partition}" "${MOUNTPOINT}"
						;;
					EFI)
						set_efi_partition
						read_input_text "Format ${partition} partition"
						if [[ $OPTION == y ]]; then
							format_partition "${partition}" "${MOUNTPOINT}${EFI_MOUNTPOINT}" vfat
						else
							mkdir -p "${MOUNTPOINT}${EFI_MOUNTPOINT}"
							mount -t vfat "${partition}" "${MOUNTPOINT}${EFI_MOUNTPOINT}"
							check_mountpoint "${partition}" "${MOUNTPOINT}${EFI_MOUNTPOINT}"
						fi
						;;
					another)
						printf "%s" "Mountpoint [ex: /home]:"
						read -r directory
						[[ $directory == "/boot" ]] && BOOT_MOUNTPOINT=$(echo "${partition}" | sed 's/[0-9]//')
						select_filesystem
						read_input_text "Format ${partition} partition"
						if [[ $OPTION == y ]]; then
							format_partition "${partition}" "${MOUNTPOINT}${directory}" "${filesystem}"
						else
							read_input_text "Confirm fs=""${filesystem}"" part=""${partition}"" dir=""${directory}"""
							if [[ $OPTION == y ]]; then
								mkdir -p "${MOUNTPOINT}${directory}"
								mount -t "${filesystem}" "${partition}" "${MOUNTPOINT}""${directory}"
								check_mountpoint "${partition}" "${MOUNTPOINT}${directory}"
							fi
						fi
						;;
					esac
					break
				else
					invalid_option
				fi
			done
		fi
		#check if there is no partitions left
		if [[ ${#partitions_list[@]} -eq 0 && ${partition_name[i]} != swap ]]; then
			break
		elif [[ ${partition_name[i]} == another ]]; then
			read_input_text "Configure more partitions"
			[[ $OPTION != y ]] && break
		fi
	done
	pause_function
}

mount -o remount,size=2G /run/archiso/cowspace

case $status in
	1)
		saveEfi
		check_trim
		verifyEfiBoot
		selectKeymap
		pause
		configure_mirrorlist
		pause
		create_partition_scheme
		pause
		;;
	2)
		;;
esac
exit 0








: << M
	#https://youtu.be/nkJvqfYmyLU?t=761
	vgdisplay #Information to Volumen groups
	lvmdiskscan -l #Scan physical volumes
	vgextend <volumeGroup> <device> #Add physical volumen to volumen group
	vgextend vg-example /dev/sdb
	lvextend -L +<size> <logicalVolume> #Extend the logical volume
	lvextend -L +10G /dev/mapper/lv-example
	resize2fs -p <logicalVolume> #Update the volumen group
	resize2fs -p /dev/mapper/lv-example
	df -h
M

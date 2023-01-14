#!/bin/bash

# Ask if user is on a laptop
read -p "Are you on a laptop? (y/n) " is_laptop

# Check if user is using UEFI
if [ -d "/sys/firmware/efi/efivars" ]; then
    is_uefi=true
else
    is_uefi=false
fi

# List available drives
lsblk

# Ask user which drive to install Arch on
read -p "Which drive do you want to install Arch on? (e.g. sda) " drive
drive_path="/dev/$drive"
# Ask user if they want to delete all partitions on the drive
read -p "Do you want to delete all partitions on the drive? (y/n) " choice
if [ "$choice" == "y" ]; then
    sgdisk --zap-all $drive
fi
# Check if system is UEFI or BIOS
is_uefi=false
if [ -d "/sys/firmware/efi/" ]; then
    is_uefi=true
fi

# Create a new GPT partition table
sgdisk --zap-all $drive_path

# Create boot partition
if [ "$is_uefi" == true ]; then
  # Create boot partition
  sgdisk --new=1:0:+300M --typecode=1:ef00 $drive
  mkfs.fat -F 32 ${drive}1
else
  # Create boot partition
  sgdisk --new=1:0:+200M --typecode=1:8300 $drive
  mkfs.ext4 ${drive}1
fi


# Create root partition
sgdisk --new=2:0:+25G --typecode=2:8300 $drive_path
mkfs.ext4 ${drive}3
mount ${drive}3 /mnt

# Make sure the drive is at least 500GB
hdd_size=$(lsblk -b | grep -w ${drive} | awk '{print $4}')
if [ $hdd_size -gt 500000000000 ]; then
  echo "Hard drive is greater than 500GB."
  read -p "Enter desired swap partition size (in GB): " swap_size
  swap_size=$((swap_size*1.5))
  sgdisk --new=3:0:+"$swap_size"G --typecode=3:8200 $drive_path
  mkswap ${drive}2
  swapon ${drive}2
else
echo "Hard drive is less than 500GB."
  read -p "Enter desired swap partition size (in GB, less than 8GB): " swap_size
  if [ $swap_size -gt 8 ]; then
    echo "Invalid swap size. Swap partition must be less than 8GB."
    exit
  fi
  sgdisk --new=3:0:+"$swap_size"G --typecode=3:8200 $drive_path
  mkswap ${drive}2
  swapon ${drive}2
fi
# Install Pre-req's
pacstrap /mnt base base-devel
# Install base and base-devel packages
pacman -S neofetch nano
# Generate fstab
genfstab /mnt >> /mnt/etc/fstab
genfstab -U /mnt >> /mnt/etc/fstab
# Arch-chroot
arch-chroot /mnt
# Install NetworkManager
pacman -S networkmanager
systemctl enable NetworkManager
# Install GRUB
if [ "$is_uefi" == "y" ]; then
    pacman -S grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    pacman -S grub
    grub-install --target=i386-pc ${drive}
fi
grub-mkconfig -o /boot/grub/grub.cfg
# Set root
read -p "What would you like the root password to be?"
echo "Enter the root password:"
read -s root_password
if [ -z "$root_password" ]; then
    echo "Root user is disabled."
else
    # Do something with the root password
    echo "Root password entered: $root_password"
read -p "Root user is successfully enabled"
fi
# Setting Desktop Enviroment 
echo "Which desktop environment would you like to install? (gnome, kde, xfce, lxde, type skip to skip this step)"
read desktop
if [ $desktop == "gnome" ]; then
  pacman -S gnome
elif [ $desktop == "kde" ]; then
  pacman -S kde
elif [ $desktop == "xfce" ]; then
  pacman -S xfce
elif [ $desktop == "lxde" ]; then
  pacman -S lxde
elif [ $desktop == "skip" ]; then
  echo "Do you want to skip selecting a desktop environment? (y/n)"
read skip_desktop
if [ $skip_desktop == "n" ]; then
  echo "Which desktop environment would you like to install? (gnome, kde, xfce, lxde)"
  read desktop
  if [ $desktop == "gnome" ]; then
    pacman -S gnome
    useradd
  elif [ $desktop == "kde" ]; then
    pacman -S kde
  elif [ $desktop == "xfce" ]; then
    pacman -S xfce
  elif [ $desktop == "lxde" ]; then
    pacman -S lxde
  else
    echo "Invalid selection."
    exit
  fi
else
  echo "Skipping desktop environment selection."
fi
else
  echo "Invalid selection."
  exit
fi
echo "Which display server would you like to use? (xorg, wayland)"
read display_server
if [ $display_server == "xorg" ]; then
  pacman -S xorg-server
elif [ $display_server == "wayland" ]; then
  pacman -S wayland
else
  echo "Invalid selection."
  exit
fi
#Checking if user has an nvidia card
nvidia_check=$(lspci | grep -i nvidia)
if [ -n "$nvidia_check" ]; then
  echo "Nvidia card detected."
  if [ $display_server == "wayland" ]; then
    echo "Do you want to install the Nvidia drivers for Wayland? (y/n)"
    read nvidia_wayland
    if [ $nvidia_wayland == "y" ]; then
      pacman -S nvidia-wayland
    else
      echo "Nvidia Wayland drivers will not be installed."
    fi
  else
    echo "Do you want to install the Nvidia drivers for Xorg? (y/n)"
    read nvidia_xorg
    if [ $nvidia_xorg == "y" ]; then
      pacman -S nvidia
    else
      echo "Nvidia Xorg drivers will not be installed."
    fi
  fi
else
  echo "Nvidia card not detected."
fi
#Unmounting drives and rebooting
umount -R /mnt
echo "Unmounting all file systems."
echo "The script is finished. The computer will now reboot."
reboot

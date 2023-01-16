#!/bin/bash

# Ask if user is on a laptop
read -p "Are you on a laptop? (y/n) " is_laptop

# Check if user is using UEFI
if [ -d "/sys/firmware/efi" ]; then
    is_uefi=true
else
    is_uefi=false
fi

# List available drives
lsblk

# Ask user which drive to install Arch on
read -p "Which drive do you want to install Arch on? (e.g. sda) " drive
drive_path="/dev/$drive"
if [ ! -b $drive_path ]; then
   echo "$drive_path does not exist!"
   exit 1
fi
# Ask user if they want to delete all partitions on the drive
read -p "Do you want to delete all partitions on the drive? (y/n) " choice
if [ "$choice" == "y" ]; then
    sgdisk --zap-all $drive_path
fi

# Create a new GPT partition table
sgdisk --zap-all $drive_path

# Create boot partition
if [ "$is_uefi" == true ]; then
    sgdisk --new=1:0:+300M --typecode=1:ef00 $drive
    mkfs.fat -F 32 ${drive_path}1
else
    sgdisk --new=1:0:+200M $drive
    mkfs.ext4 ${drive}1
fi

# Create root partition
sgdisk --new=2:0:+25G --typecode=2:8300 $drive_path
mkfs.ext4 ${drive}3
mount ${drive_path}3 /mnt


# Make sure the drive is at least 500GB
hdd_size=$(lsblk -b | grep -w ${drive} | awk '{print $4}')
if [ $hdd_size -gt 500000000000 ]; then
  echo "Hard drive is greater than 500GB."
  read -p "Enter desired swap partition size (in GB): " swap_size
  swap_size_bytes=$((swap_size*1024*1024*1024))
  swap_size=$((swap_size*1.5))
  sgdisk --new=3:0:+"$swap_size_bytes"B --typecode=3:8200 $drive_path
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
    grub-install --target=i386-pc $drive_path
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
# Setting hostname
read -p "Enter the hostname: " hostname
echo $hostname > /mnt/etc/hostname
# Setting Desktop Enviroment
desktop_selected=false
while [ $desktop_selected == false ]
do
    echo "Which desktop environment would you like to install? (gnome, kde, xfce, Cinnamon, type skip to skip this step)"
    read desktop
    if [ $desktop == "skip" ]; then
        echo "Do you want to skip selecting a desktop environment? (y/n)"
        read skip_desktop
        if [ $skip_desktop == "n" ]; then
# gnome desktop environment
if [ $desktop == "gnome" ]; then
  pacman -S gnome
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable gdm.service
    echo "exec gnome-session" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable gdm.service
    echo "exec gnome-session" >> /etc/X11/xinit/xinitrc
  else
    echo "Invalid selection."
    exit
  fi
    
# kde desktop environment
elif [ $desktop == "kde" ]; then
  pacman -S kde
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable sddm.service
    echo "exec startplasma-x11" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable sddm.service
    echo "exec startplasma" >> /etc/X11/xinit/xinitrc
  else
    echo "Invalid selection."
    exit
  fi
# xfce desktop environment
elif [ $desktop == "xfce" ]; then
  pacman -S xfce
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable lightdm.service
    echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable lightdm.service
    echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
  else
    echo "Invalid selection."
    exit
  fi
# xfce desktop environment
elif [ $desktop == "xfce" ]; then
  pacman -S xfce
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable lightdm.service
    echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable lightdm.service
    echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
  else
    echo "Invalid selection."
    exit
  fi
  # Cinnamon desktop environment
elif [ $desktop == "Cinnamon" ]; then
  pacman -S cinnamon
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable lightdm.service
    echo "exec cinnamon-session" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable lightdm.service
    echo "exec cinnamon-session" >> /etc/X11/xinit/xinitrc
 fi
            desktop_selected=true
        fi
    else
# gnome desktop environment
if [ $desktop == "gnome" ]; then
  pacman -S gnome
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable gdm.service
    echo "exec gnome-session" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable gdm.service
    echo "exec gnome-session" >> /etc/X11/xinit/xinitrc
  else
    echo "Invalid selection."
    exit
  fi
    
# kde desktop environment
elif [ $desktop == "kde" ]; then
  pacman -S kde
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable sddm.service
    echo "exec startplasma-x11" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable sddm.service
    echo "exec startplasma" >> /etc/X11/xinit/xinitrc
  else
    echo "Invalid selection."
    exit
  fi
# xfce desktop environment
elif [ $desktop == "xfce" ]; then
  pacman -S xfce
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable lightdm.service
    echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable lightdm.service
    echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
  else
    echo "Invalid selection."
    exit
  fi
# xfce desktop environment
elif [ $desktop == "xfce" ]; then
  pacman -S xfce
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable lightdm.service
    echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable lightdm.service
    echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
  else
    echo "Invalid selection."
    exit
  fi
  # Cinnamon desktop environment
elif [ $desktop == "Cinnamon" ]; then
  pacman -S cinnamon
  echo "Which display server would you like to use? (xorg, wayland)"
  read display_server
  if [ $display_server == "xorg" ]; then
    pacman -S xorg-server
    systemctl enable lightdm.service
    echo "exec cinnamon-session" >> /etc/X11/xinit/xinitrc
  elif [ $display_server == "wayland" ]; then
    pacman -S wayland
    systemctl enable lightdm.service
    echo "exec cinnamon-session" >> /etc/X11/xinit/xinitrc
 fi
        desktop_selected=true
    fi
    
if
skip_desktop=true
while [ $skip_desktop == true ]
do
    echo "Which desktop environment would you like to install? (gnome, kde, xfce, Cinnamon, type skip to skip this step)"
    read desktop
    if [ $desktop == "skip" ]; then
        echo "Do you want to skip selecting a desktop environment? (y/n)"
        read skip_desktop
        if [ $skip_desktop == "n" ]; then
            skip_desktop=false
        fi
  # Ask user if they want to install Pamac package manager
read -p "Do you want to install a Package Manager? (It works like an appstore) (y/n) " pm

if [ "$pm" == "y" ]; then
    pacman -S pamac
    echo "Pamac has been installed. Use the Pamac GUI or the 'pamac' command to search and install packages."
else
    echo "A package manager has not been installed. Use 'pacman' command to search and install packages."
fi

else
  echo "Skipping desktop environment selection."
fi
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

# Set locale
echo "Enter your desired locale (e.g. en_US.UTF-8): "
read locale
echo $locale >> /etc/locale.gen
locale-gen
echo "LANG=$locale" >> /etc/locale.conf

# Show available main timezones
timedatectl list-timezones | cut -f1 -d/

# Set timezone
echo "Select your desired main timezone from the list above: "
read main_timezone

# Check if the main timezone has any sub timezones
sub_timezones=$(timedatectl list-timezones | grep ^$main_timezone | cut -f2 -d/)
if [ -z "$sub_timezones" ]; then
    # Main timezone has no sub timezones
    timezone="$main_timezone"
else
    # Main timezone has sub timezones
    echo "Select your desired sub timezone from the list below: "
    echo "$sub_timezones"
    read sub_timezone
    timezone="$main_timezone/$sub_timezone"
fi
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc



# Adding a user
read -p "Enter the username you want to create: " username
useradd -m -g wheel $username

# disabling root user
echo "do you want to disable root user? (y/n)"
read disable_root
if [ $disable_root == "y" ]; then
  passwd -l root
fi
#Unmounting drives and rebooting
umount -R /mnt
echo "Unmounting all file systems."
echo "The script is finished. The computer will now reboot."
echo "Thank you for using my script $username :)"
reboot

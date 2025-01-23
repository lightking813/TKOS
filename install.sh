#!/bin/bash

# Function to check if we have a Wi-Fi interface
check_wifi() {
    # Use `iw dev` to check for Wi-Fi interfaces
    if iw dev | grep -q "Interface"; then
        return 0  # Wi-Fi interface found
    else
        return 1  # No Wi-Fi interface found
    fi
}

# Check if Wi-Fi interface exists
if check_wifi; then
    echo "Wi-Fi interface detected."
    
    # Ask the user if they want to connect to Wi-Fi
    read -p "Would you like to connect to a Wi-Fi network? (y/n): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        # Use iwctl or wifi-menu for connection
        echo "Please select a Wi-Fi network..."
        # This assumes the system uses `iwctl` or another command to connect to Wi-Fi
        iwctl station device scan  # Replace 'device' with your network interface name (e.g., wlan0)
        
        # List available networks
        iwctl station device get-networks
        
        # Prompt the user to select and connect to a network
        read -p "Enter the SSID of the network you want to connect to: " ssid
        read -sp "Enter the Wi-Fi password: " password
        echo

        # Attempt connection (replace 'device' with your interface, e.g., wlan0)
        iwctl station device connect "$ssid" "$password"
        
        # Check if connection is successful
        if iwctl station device show | grep -q "Connected"; then
            echo "Successfully connected to Wi-Fi."
        else
            echo "Failed to connect to Wi-Fi. Please check your credentials or network."
            exit 1
        fi
    else
        echo "Wi-Fi connection skipped."
    fi
else
    echo "No Wi-Fi interface found. Proceeding without Wi-Fi."
fi

# Continue with the rest of your installation script
echo "Proceeding with the installation..."

# Ask user which drive to install Arch on
lsblk
read -p "Which drive do you want to install Arch on? (e.g. sda) " drive
drive_path="/dev/$drive"
sector_size=$(blockdev --getss "$drive_path")
default_start_sector=$((sector_size * 1))

# Check if the drive is using UEFI
is_uefi=false
if [ -d "/sys/firmware/efi/" ]; then
    is_uefi=true
    boot_label=msdos
else
    boot_label=gpt
fi

# Check if lowercase labels are supported
if [ "$boot_label" = "msdos" ]; then
    echo "Lowercase labels are not supported. Converting to uppercase."
    boot_label="${boot_label^^}"
elif [ "$boot_label" = "gpt" ]; then
    if command -v e2label >/dev/null 2>&1; then
        echo "Lowercase labels are supported."
    else
        echo "Lowercase labels are not supported. Converting to uppercase."
        boot_label="${boot_label^^}"
    fi
else
    echo "Unsupported boot label type: $boot_label"
    exit 1
fi

# Ask user if they want to format the drive
read -p "Do you want to format the drive? (y/n) If 'n' is selected, the script will end. " choice
if [ "$choice" == "n" ]; then
    echo "Exiting the script."
    exit 1
elif [ "$choice" == "y" ]; then
    umount -R /mnt /mnt/boot /mnt/home 2>/dev/null || true
    echo "Making sure swap partition isn't still connected..."
    swapoff -a
    wipefs -a "$drive_path"
fi

# Check if the drive has been formatted
lsblk | grep -q "/dev/$drive"
if [ $? -ne 0 ]; then
    echo "Partitions have not been created. Exiting script."
    exit 1
fi
# Check if the drive already has a recognized disk label
existing_label=$(parted -s "$drive_path" print 2>/dev/null | awk '/^Partition Table:/{print $3}')
if [ "$existing_label" = "$boot_label" ]; then
    echo "Disk label '$boot_label' already exists on the drive. Skipping label creation."
else
    # Create the disk label
    parted -s "$drive_path" mklabel "$boot_label" --align=optimal
    if [ $? -ne 0 ]; then
        echo "Failed to create disk label '$boot_label'. Exiting..."
        exit 1
    fi
fi

# Calculate the start and end sectors for the boot partition
boot_start_sector=$default_start_sector
if [ "$is_uefi" == true ]; then
    boot_end_sector=$((boot_start_sector + 300 * 1024 * 1024 / sector_size - 1))

    parted -s "$drive_path" mkpart primary fat32 "${boot_start_sector}s" "${boot_end_sector}s" --align=optimal
    parted -s "$drive_path" set 1 esp on
    fatlabel "${drive_path}1" "$boot_label"
    mkfs.fat -F32 "${drive_path}1"
else
    boot_end_sector=$((boot_start_sector + 200 * 1024 * 1024 / sector_size - 1))

    parted -s "$drive_path" mkpart primary ext4 "${boot_start_sector}s" "${boot_end_sector}s" --align=optimal
    parted -s "$drive_path" set 1 esp off
    e2label "${drive_path}1" "$boot_label"
    mkfs.ext4 "${drive_path}1"
fi

# Calculate the root partition size
root_size_bytes=$((25 * 1024 * 1024 * 1024))
root_start_sector=$((swap_end_sector + 1))
root_end_sector=$((root_start_sector + root_size_bytes / sector_size - 1))

# Create root partition
echo "Creating root partition with size 25GB..."
parted -s "$drive_path" mkpart primary ext4 "${root_start_sector}s" "${root_end_sector}s" --align=optimal
parted -s "$drive_path" set 3 root on
mkfs.ext4 "${drive_path}3"

# Calculate the remaining space for the home partition
drive_size_bytes=$(blockdev --getsize64 "$drive_path")
home_start_sector=$((root_end_sector + 1))

# Create home partition with the remaining disk space
echo "Creating home partition with the remaining disk space..."
parted -s "$drive_path" mkpart primary ext4 "${home_start_sector}s" 100% --align=optimal
parted -s "$drive_path" set 4 home on
mkfs.ext4 "${drive_path}4"

# Delay to allow partition changes to be recognized
sleep 10

# Mount partitions
swapon "${drive_path}2"
echo "Mounting partitions..."
if swapon -s | grep -q "${drive_path}2"; then
    echo "Swap disk is configured."
else
    echo "No swap disk found."
fi
mount "${drive_path}3" /mnt
mkdir -p /mnt/boot
mount "${drive_path}1" /mnt/boot
mkdir -p /mnt/home
mount "${drive_path}4" /mnt/home

# Display disk and partition information
lsblk

# Install Pre-req's
if ! mount | grep -q '/mnt/boot'; then
    echo "Boot partition is not mounted. Please mount it before proceeding."
    exit 1
fi

root_space=$(df -h /mnt/ | awk '{print $4}')
if [[ $root_space < "25G" ]]; then
    echo "The root partition does not have enough space to install Arch Linux. Please make sure the partition has at least 25GB of free space."
    exit 1
fi

lsblk | grep -q "/dev/$drive"
if [ $? -ne 0 ]; then
    echo "Partitions have not been created. Exiting script."
    exit 1
fi

current_root_device=$(mount | grep "on / " | awk '{print $1}')
if [[ "$current_root_device" == "$drive_path"* ]]; then
    echo "You cannot install Arch Linux on the drive containing the current root partition."
    exit 1
fi

pacstrap /mnt base base-devel
# Install base and base-devel packages
# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab
# Arch-chroot
arch-chroot /mnt
pacman -S neofetch nano

# Check if a device requires Wi-Fi (for example, check if 'iwconfig' or 'lspci' shows a Wi-Fi device)
if lspci | grep -i network | grep -i wifi; then
    echo "Wi-Fi device found. Checking if linux-firmware is installed..."

    # Check if the linux-firmware package is installed (for Arch Linux)
    if ! pacman -Q linux-firmware &>/dev/null; then
        echo "linux-firmware not installed. Installing..."
        sudo pacman -Syu --noconfirm linux-firmware
    else
        echo "linux-firmware is already installed."
    fi
else
    echo "No Wi-Fi device found. No need to install linux-firmware."
fi

# Install NetworkManager
pacman -S networkmanager
systemctl enable NetworkManager
fi
# Install GRUB
if [ "$is_uefi" == "true" ]; then
    pacman -S grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
    if [ $? -ne 0 ]; then echo "grub-install failed"; fi
else
    pacman -S grub
    grub-install --target=i386-pc $drive_path()
    if [ $? -ne 0 ]; then echo "grub-install failed"; fi
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
# Setting Desktop Environment
desktop_selected=false

while [ $desktop_selected == false ]; do
    echo "Which desktop environment would you like to install? (gnome, kde, xfce, Cinnamon, or type 'skip' to skip this step)"
    read desktop

    if [ $desktop = "skip" ]; then
        echo "Desktop environment selection skipped."
        desktop_selected=true

    # gnome desktop environment
    elif [ $desktop = "gnome" ]; then
        pacman -S gnome
        echo "Which display server would you like to use? (xorg, wayland)"
        read display_server

        if [ $display_server = "xorg" ]; then
            pacman -S xorg-server
            systemctl enable gdm.service
            echo "exec gnome-session" >> /etc/X11/xinit/xinitrc
            desktop_selected=true

        elif [ $display_server = "wayland" ]; then
            pacman -S wayland
            systemctl enable gdm.service
            echo "exec gnome-session" >> /etc/X11/xinit/xinitrc
            desktop_selected=true

        else
            echo "Invalid selection."
            exit
        fi

    # kde desktop environment
    elif [ $desktop = "kde" ]; then
        pacman -S kde
        echo "Which display server would you like to use? (xorg, wayland)"
        read display_server

        if [ $display_server = "xorg" ]; then
            pacman -S xorg-server
            systemctl enable sddm.service
            echo "exec startplasma-x11" >> /etc/X11/xinit/xinitrc
            desktop_selected=true

        elif [ $display_server = "wayland" ]; then
            pacman -S wayland
            systemctl enable sddm.service
            echo "exec startplasma" >> /etc/X11/xinit/xinitrc
            desktop_selected=true

        else
            echo "Invalid selection."
            exit
        fi

    # xfce desktop environment
    elif [ $desktop = "xfce" ]; then
        pacman -S xfce
        echo "Which display server would you like to use? (xorg, wayland)"
        read display_server

        if [ $display_server = "xorg" ]; then
            pacman -S xorg-server
            systemctl enable lightdm.service
            echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
            desktop_selected=true

        elif [ $display_server = "wayland" ]; then
            pacman -S wayland
            systemctl enable lightdm.service
            echo "exec startxfce4" >> /etc/X11/xinit/xinitrc
            desktop_selected=true

        else
            echo "Invalid selection."
            exit
        fi
 # Cinnamon desktop environment
    elif [ $desktop = "Cinnamon" ]; then
        pacman -S cinnamon
        echo "Which display server would you like to use? (xorg, wayland)"
        read display_server

        if [ $display_server = "xorg" ]; then
            pacman -S xorg-server
            systemctl enable lightdm.service
            echo "exec cinnamon-session" >> /etc/X11/xinit/xinitrc
            desktop_selected=true

        elif [ $display_server = "wayland" ]; then
            pacman -S wayland
            systemctl enable lightdm.service
            echo "exec cinnamon-session" >> /etc/X11/xinit/xinitrc
            desktop_selected=true

        else
            echo "Invalid selection."
            exit
        fi

    fi
done

skip_desktop=false

while [ $skip_desktop == false ]; do
    echo "Which desktop environment would you like to install? (gnome, kde, xfce, Cinnamon, type 'skip' to skip this step)"
    read desktop

    if [ $desktop = "skip" ]; then
        echo "Do you want to skip selecting a desktop environment? (y/n)"
        read skip_desktop

        if [ $skip_desktop = "n" ]; then
            skip_desktop=false
        else
            echo "Skipping desktop environment selection."
            skip_desktop=true
            exit
        fi
    fi
done
# Ask user if they want to install Pamac package manager
read -p "Do you want to install a Package Manager? (It works like an appstore) (y/n) " pm

if [ "$pm" == "y" ]; then
    pacman -S pamac
    echo "Pamac has been installed. Use the Pamac GUI or the 'pamac' command to search and install packages."
else
    echo "A package manager has not been installed. Use 'pacman' command to search and install packages."
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

# Ask if user is on a laptop
read -p "Are you on a laptop? (y/n) " is_laptop
if [ $is_laptop == "y" ]; then
    pacman -S tlp
else
    echo "You are not using a laptop. If you are, please install tlp later as it's designed to improve battery life."
fi
# Adding a user
read -p "Enter the username you want to create: " username
useradd -m -g wheel $username

# disabling root user
echo "Do you want to disable the root user? (y/n)"
read disable_root
if [ $disable_root == "y" ]; then
    passwd -l root
fi
#Unmounting drives and rebooting
umount -R /mnt
echo "Unmounting all file systems."
echo "The script is finished. The computer will now reboot."
echo "Thank you for using my script $username :)"
fi
reboot

#!/bin/bash
# encoding: utf-8

################################################
#                 Variaveis                    #
################################################

pacman -S --noconfirm dialog

HNAME=$(dialog  --clear --inputbox "Digite o nome do Computador" 10 25 --stdout)

KERNEL=$(dialog  --clear --radiolist "Selecione o Kernel" 15 30 4 "linux" "" ON "linux-lts" "" OFF "linux-hardened" "" OFF "linux-zen" "" OFF --stdout)

ZONE=$(dialog  --clear --menu "Select Sua country/zone." 20 35 15 $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "/" | sed "s/\/.*//g" | sort -ud | sort | awk '{ printf "\0"$0"\0"  " . " }') --stdout)
SUBZONE=$(dialog  --clear --menu "Select Sua country/zone." 20 35 15 $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "$ZONE/" | sed "s/$ZONE\///g" | sort -ud | sort | awk '{ printf "\0"$0"\0"  " . " }') --stdout)

LOCALE=$(dialog  --clear --radiolist "Escolha idioma do sistema:" 15 30 4 $(cat /etc/locale.gen | grep -v "#  " | sed 's/#//g' | sed 's/ UTF-8//g' | grep .UTF-8 | sort | awk '{ print $0 "\"\"  OFF " }') --stdout)
CLOCK=$(dialog  --clear --radiolist "Configurcao do relojo" 10 30 4 "utc" "" ON "localtime" "" OFF --stdout)

ROOT_PASSWD=$(dialog --clear --inputbox "Digite a senha de root" 10 25 --stdout)
USER=$(dialog  --clear --inputbox "Digite o nome do novo Usuario" 10 25 --stdout)
USER_PASSWD=$(dialog --clear --inputbox "Digite a senha  de $USER" 10 25 --stdout)

KEYBOARD_LAYOUT=br-abnt2

HD=/dev/sda

BOOT_FS=ext2
ROOT_FS=ext4

SWAP_SIZE=1024
GRUB_SIZE=500
ROOT_SIZE=117*1024

dialog --title "INTEFACE GRAFICA" --clear --yesno "Deseja Instalar Windows Manager ?" 10 30

DM=$(dialog  --clear --menu "Selecione o Kernel" 15 30 4  1 "terminal" 2 "gnome" 3 "cinnamon" 4 "plasma" --stdout)

if [[ $DM -ne 1 ]]; then
	APPS=$(dialog --clear --stdout --separate-output --checklist 'Escolha seu App' 0 0 0 "chromium" '' OFF "firefox" '' OFF "vlc" '' OFF "gimp" '' OFF "thunderbird" '' OFF "gedit" '' OFF "leafpad" '' OFF "filezilla" '' OFF "file-roller" '' OFF "xdg-user-dirs-gtk" '' OFF "mousepad" '' OFF --stdout)
fi

EXTRA_PKGS="networkmanager nano"

########## Variaveis Para Particionamento do Disco
BOOT_START=1
BOOT_END=$(($BOOT_START+$GRUB_SIZE))

ROOT_START=$BOOT_END
ROOT_END=$(($ROOT_START+$ROOT_SIZE))

if [[ -d "/sys/firmware/efi/" ]]; then
    SYSTEM="UEFI"
else
    SYSTEM="BIOS"
fi

PROCODE=$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')

################################################
#                 functions                    #
################################################

arch_chroot(){
    arch-chroot /mnt /bin/bash -c "${1}"
}
parted_disco() {
    parted --script $HD "${1}"
}

particionar_discos(){
    parted -s $HD rm 1
    parted -s $HD rm 2
    if [[ $SYSTEM = "UEFI" ]]; then
        parted_disco "mklabel gpt"
        parted_disco "mkpart primary fat32 $BOOT_START $BOOT_END"
        parted_disco "set 1 boot on"
        parted_disco "name 1 boot"
        mkfs.vfat -F32 /dev/sda1
    else
        parted_disco "mklabel msdos"
        parted_disco "mkpart primary $BOOT_START $BOOT_END"
        parted_disco "set 1 bios_grub on"
        parted_disco "name 1 boot"
        mkfs.$BOOT_FS /dev/sda1
    fi
    parted_disco "mkpart primary $ROOT_FS $ROOT_START -0"
    parted_disco "name 2 arch_linux"
    mkfs.$ROOT_FS /dev/sda2
}

monta_particoes(){
    mount /dev/sda2 /mnt
    if [[ $SYSTEM = "UEFI" ]]; then
        mkdir -p /mnt/boot/EFI
        mount /dev/sda1 /mnt/boot/EFI
    else
        mkdir /mnt/boot
        mount /dev/sda1 /mnt/boot
    fi
    touch /mnt/swapfile
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$SWAP_SIZE
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
}

conf_repositorio(){
    echo -e "\n\nServer = http://br.mirror.archlinux-br.org/\$repo/os/\$arch\nServer = http://mirror.ufam.edu.br/archlinux/\$repo/os/\$arch\nServer = http://archlinux.c3sl.ufpr.br/\$repo/os/\$arch\nServer = rsync://archlinux.c3sl.ufpr.br/archlinux/\$repo/os/\$arch\nServer = http://mirror.ufscar.br/archlinux/\$repo/os/\$arch\n" > /etc/pacman.d/mirrorlist
    if [ "$(uname -m)" = "x86_64" ]; then
        cp /etc/pacman.conf /etc/pacman.conf.bkp
        sed '/^#\[multilib\]/{s/^#//;n;s/^#//;n;s/^#//}' /etc/pacman.conf > /tmp/pacman
        mv /tmp/pacman /etc/pacman.conf
    fi
}

instala_base(){
    pacstrap /mnt base base-devel $KERNEL $KERNEL-headers $KERNEL-firmware `echo $EXTRA_PKGS`
    genfstab -U -p /mnt >> /mnt/etc/fstab
}

boot_load(){
    if [[ $PROCODE = "GenuineIntel" ]]; then
        arch_chroot "pacman -S --noconfirm intel-ucode"
    elif [ $PROCODE = "AuthenticAMD" ]; then
        arch_chroot "pacman -S --noconfirm amd-ucode"
    fi
    arch_chroot "pacman -Syy && pacman -S --noconfirm grub"
    if [[ $SYSTEM = "UEFI" ]]; then
        arch_chroot "pacman -S --noconfirm efibootmgr dosfstools mtools"
        arch_chroot "grub-install --target=x86_64-efi --efi-directory=/boot/EFI --bootloader-id=grub_uefi --recheck"
        mkdir /mnt/boot/EFI/EFI/boot && mkdir /mnt/boot/grub/locale
        cp /mnt/boot/EFI/EFI/grub_uefi/grubx64.efi /mnt/boot/EFI/EFI/boot/bootx64.efi
    else
        arch_chroot "grub-install --target=i386-pc --recheck $HD"
    fi
    cp /mnt/usr/share/locale/en@quot/LC_MESSAGES/grub.mo /mnt/boot/grub/locale/en.mo
    arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg"
}

################################################
#                  Script                      #
################################################

loadkeys br-abnt2
timedatectl set-ntp true

#### Particionamento formatacao montage
particionar_discos
monta_particoes

#### Instalcao
conf_repositorio
instala_base
boot_load

#### Configuracao 
arch_chroot "loadkeys br-abnt2"
arch_chroot "timedatectl set-ntp true"

echo "Setting Hostname..."
arch_chroot "echo $HNAME > /etc/hostname"

# Host
echo "HostFile"
arch_chroot "echo '127.0.0.1   localhost.localdomain    localhost' > /etc/hosts"
arch_chroot "echo '::1         localhost.localdomain    localhost' >> /etc/hosts"
arch_chroot "echo '127.0.1.1   $HNAME.localdomain       $HNAME' >> /etc/hosts"

#setting locale pt_BR.UTF-8 UTF-8
echo "Generating Locale..."
arch_chroot "echo '${LOCALE} UTF-8' > /etc/locale.gen"
arch_chroot "echo 'LANG=${LOCALE}' > /etc/locale.conf"
arch_chroot "echo 'LC_MESSAGES=${LOCALE}' >> /etc/locale.conf"
arch_chroot "locale-gen"
arch_chroot "export LANG=${LOCALE}"

#setting keymap
arch_chroot "echo 'KEYMAP=$KEYBOARD_LAYOUT' > /etc/vconsole.conf"
arch_chroot "echo 'FONT=lat0–16' >> /etc/vconsole.conf"
arch_chroot "echo 'FONT_MAP=' >> /etc/vconsole.conf"

# Setting timezone
echo "Setting Timezone..."
arch_chroot "rm /etc/localtime"
arch_chroot "ln -s /usr/share/zoneinfo/${ZONE}/${SUBZONE} /etc/localtime"

# Setting hw CLOCK
echo "Setting System Clock..."
arch_chroot "hwclock --systohc --$CLOCK"

# root password
arch_chroot "echo -e $ROOT_PASSWD'\n'$ROOT_PASSWD | passwd"

# Adding user
echo "Making new user..."
arch_chroot "useradd -m -g users -G power,storage,wheel -s /bin/bash `echo $USER`"
arch_chroot "echo -e $USER_PASSWD'\n'$USER_PASSWD | passwd `echo $USER`"

arch_chroot "echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers"

arch_chroot "systemctl enable NetworkManager"

# Configura ambiente ramdisk inicial
arch_chroot "mkinitcpio -p $KERNEL"

arch_chroot 'echo -e "\n\nServer = http://br.mirror.archlinux-br.org/\$repo/os/\$arch\nServer = http://mirror.ufam.edu.br/archlinux/\$repo/os/\$arch\nServer = http://archlinux.c3sl.ufpr.br/\$repo/os/\$arch\nServer = rsync://archlinux.c3sl.ufpr.br/archlinux/\$repo/os/\$arch\nServer = http://mirror.ufscar.br/archlinux/\$repo/os/\$arch\n" > /etc/pacman.d/mirrorlist'

# starting desktop manager
if [[ $DM -ne 1 ]]; then
    arch_chroot "pacman -S --noconfirm xf86-video-intel xorg xorg-server eog tilix adwaita-icon-theme arc-gtk-theme papirus-icon-theme faenza-icon-theme"
    if [[ $DM -eq 2 ]]; then
        arch_chroot "pacman -S --noconfirm gnome gnome-tweaks gdm xorg-server-xwayland"
        arch_chroot "pacman -R --noconfirm gnome-terminal"
        arch_chroot "systemctl enable gdm.service"
    elif [[ $DM -eq 3 ]]; then
        arch_chroot "pacman -S --noconfirm cinnamon nemo-fileroller gdm"
        arch_chroot "systemctl enable gdm.service"
    elif [[ $DM -eq 4 ]]; then
        arch_chroot "pacman -S --noconfirm plasma sddm"
        arch_chroot "echo -e '[Theme]\nCurrent=breeze' >> /usr/lib/sddm/sddm.conf.d/default.conf"
        arch_chroot "systemctl enable sddm.service"
    fi
    arch_chroot "pacman -S --noconfirm $APPS"
fi

arch_chroot "pacman -S --noconfirm git docker docker-compose nodejs npm"
arch_chroot "systemctl enable docker"
arch_chroot "usermod -aG docker `echo $USER`"

umount -R /mnt

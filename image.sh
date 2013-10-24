#!/bin/bash

# (fr)
# Crée une image disque de Debian { wheezy | jessie } incluant le paquet "cloud-init" pour OpenStack
# (en)
# Create a Debian { wheezy | jessie } disk image including "cloud-init" for OpenStack

# Copyright 2013 GON Jérôme 
# (jerome.gon@gmx.fr)
#
# Licence GNU GPLv3 
#
# This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.


# Set following variables
# Use absolute links
IMAGE_PATH="/home/jgon/wheezy.img"
DISTRIBUTION="wheezy"
WORKING_DIR="/mnt/wheezy"
IMAGE_SIZE="1G"
ARCH="amd64"
PAQUETS="ssh"
MIRROIR="ftp://ftp.fr.debian.org/debian/"
SOURCES_APT="deb http://ftp.fr.debian.org/debian/ $DISTRIBUTION main non-free contrib\ndeb http://security.debian.org/ $DISTRIBUTION/updates main contrib non-free\ndeb http://ftp.fr.debian.org/debian/ $DISTRIBUTION-proposed-updates main contrib non-free"
HOSTNAME="wheezy-openstack"
INTERFACES="auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet dhcp"

# set dependencies according to the release
case $DISTRIBUTION in
    "wheezy")
        DEPENDENCES_CLOUD="python,python-paramiko,python-argparse,python-cheetah,python-configobj,python-oauth,python-software-properties,python-yaml,python-boto,python-prettytable,initramfs-tools,python-requests"
    ;;
    "jessie")
        DEPENDENCES_CLOUD="cloud-init,cloud-utils,cloud-initramfs-growroot"
    ;;
esac

if [ -f $IMAGE_PATH ]
    then
	echo -e "\nUne image du même nom existe déjà.\n"
	exit 10 
fi

if [ -d $WORKING_DIR ]
    then
        echo -e "\nCette cible de \"montage\" existe déjà.\n"
        exit 20
fi

echo -e "\n\t\t### INITIALISATION ###\n"

apt-get clean
apt-get update 

# install necessary packages
apt-get install -y debootstrap qemu-kvm debian-archive-keyring extlinux syslinux-common mbr

mkdir $WORKING_DIR

echo -e "\n\t\t### CREATION IMAGE ###\n"

# Create, format and mount empty image
kvm-img create -f raw $IMAGE_PATH $IMAGE_SIZE
mkfs.ext4 $IMAGE_PATH
mount -t ext4 -o loop,defaults,noatime $IMAGE_PATH $WORKING_DIR

echo -e "\n\t\t### CREATION SYSTEME ###\n"

# install Debian with "debootstrap"
debootstrap --arch=$ARCH --include=$PAQUETS,$DEPENDENCES_CLOUD $DISTRIBUTION $WORKING_DIR $MIRROIR

echo -e "\n\t\t### CONFIGURATION SYSTEME ###\n"

# Repositories configuration
echo -e "$SOURCES_APT" > $WORKING_DIR/etc/apt/sources.list
if [ "$DISTRIBUTION" = "wheezy" ]
   then
        echo "deb http://ftp.debian.org/debian wheezy-backports main" >> $WORKING_DIR/etc/apt/sources.list
fi

# creation of cloud-init user
chroot $WORKING_DIR adduser --gecos cloud-init-user --disabled-password --quiet debian
mkdir -p $WORKING_DIR/etc/sudoers.d
echo "debian ALL = NOPASSWD: ALL" > $WORKING_DIR/etc/sudoers.d/debian-cloud-init
chmod 0440 $WORKING_DIR/etc/sudoers.d/debian-cloud-init
echo -e "\n# Required for cinder hotplug\nacpiphp\npci_hotplug" >>$WORKING_DIR/etc/modules

# Network configuration
echo -e "$INTERFACES" > $WORKING_DIR/etc/network/interfaces
echo "$HOSTNAME" > $WORKING_DIR/etc/hostname

if [ $DISTRIBUTION=="wheezy" ] # cloud-init installation for wheezy
    then
	echo -e "\n\t\t### INSTALATION CLOUD-INIT ###\n"
	chroot $WORKING_DIR apt-get update 
        chroot $WORKING_DIR apt-get -t wheezy-backports install cloud-init cloud-utils cloud-initramfs-growroot -y
fi

# We do the disk bootable
echo -e "\n\t\t### FINALISATION ###\n"
extlinux -i $WORKING_DIR/boot
install-mbr $IMAGE_PATH
cp /usr/lib/syslinux/vesamenu.c32  $WORKING_DIR/boot
echo -e "default vesamenu.c32\nprompt 0\ntimeout 1\nlabel persistent\nkernel /casper/vmlinuz\nappend  file=/cdrom/preseed/custom.seed boot=casper initrd=/casper/initrd.gz persistent quiet splash --" >> $WORKING_DIR/boot/extlinux.conf

echo -e "\n\t\t### DEMONTAGE DE L'IMAGE ###\n"

umount $WORKING_DIR

echo -e "\n\t\t### REDIMENCIONNEMENT ###\n"

# Risize disk
e2fsck -f $IMAGE_PATH
resize2fs -M $IMAGE_PATH

echo -e "\n\t\t### FIN ###\n"

exit 0

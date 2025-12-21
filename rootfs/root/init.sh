#!/bin/bash
set -ue

export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export LANGUAGE=C.UTF-8

if ! grep -q '^hi' /etc/passwd; then
	useradd -g sudo -m -s /bin/bash hi
fi
echo hi:hikey970 | chpasswd

passwd -d root

echo "clean the house"
rm -rf /debootstrap
apt clean
apt autoclean

echo "make sure I don't have ssh keys"
rm -f /etc/ssh/ssh_host_*

echo "hikey970" > /etc/hostname
echo "127.0.0.1 hikey970" >> /etc/hosts

echo "configure systemd"
systemctl enable wpa_supplicant@wlan0.service
systemctl enable dhcpcd.service

echo "set timezone"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

echo "self destroy, bye bye"
rm /root/init.sh


#!/bin/bash

set -ue

DISTRO=${DISTRO:-"bionic"}
#GIT_VERSION=`git describe --tags`
VERSION=${VERSION:-v1.0}
echo "Version:" $VERSION

REQUIRED="debootstrap img2simg mkfs.ext2"
MIRRORS=${MIRRORS:-}
SOFTWARE="ssh \
,zsh \
,firmware-linux-nonfree \
,vim-nox \
,net-tools \
,wpasupplicant \
,systemd \
,iw \
,dhcpcd5 \
,wireless-tools \
,dbus \
,iproute2 \
,network-manager \
"

SYSTEM_SIZE=${SYSTEM_SIZE:-'2048'} # 1G

echo "Fetch from... " $MIRRORS
echo "Install... " $SOFTWARE

echo "Dependency check"
for i in $REQUIRED; do
	command -v $i >/dev/null 2>&1 || { echo >&2 "require $i but it's not installed.  Aborting."; exit 1; }
	echo "[$i ... OK]"
done

echo "Clean tmp"
rm -rf build
mkdir build

 	#--exclude=policykit-1,polkitd,network-manager,crda \
debootstrap --arch arm64 --include=${SOFTWARE// /} \
	--components=main,contrib,non-free,non-free-firmware $DISTRO build/rootfs $MIRRORS

cp -r rootfs/boot/* build/rootfs/boot
cp -r rootfs/etc/netplan build/rootfs/etc
cp -r rootfs/etc/rc.local build/rootfs/etc
cp -r rootfs/etc/update-motd.d build/rootfs/etc
cp -r rootfs/lib/* build/rootfs/lib
cp -r rootfs/root/* build/rootfs/root

echo "Initial system"
chroot build/rootfs /root/init.sh

echo "Building image" $SYSTEM_SIZE
dd if=/dev/zero of=build/rootfs.img bs=1M count=$SYSTEM_SIZE conv=sparse
mkfs.ext2 -L rootfs -F build/rootfs.img
if test $? -eq 0; then echo "mkfs.ext2 OK..."; fi

mkdir build/loop
mount -o loop build/rootfs.img build/loop

echo "Copying root"
(cd build/rootfs;tar -cf - *) | tar -xf - -C build/loop

echo "Umount"
umount build/loop

echo "Building sparse"
export SPARSE_IMG="ubuntu_$DISTRO.hikey970.$VERSION.sparse.img"
img2simg build/rootfs.img build/$SPARSE_IMG

echo "Compressing"
tar -C build -czvf build/$SPARSE_IMG.tar.gz $SPARSE_IMG

echo "ALL COMPLETE"
ls -lha build/$SPARSE_IMG
sha1sum build/$SPARSE_IMG
exit 0

#!/bin/bash

set -ue

DISTRO=${DISTRO:-"bionic"}
VERSION=${VERSION:-v1.0}
echo "Version:" $VERSION

REQUIRED="debootstrap img2simg mkfs.ext2"
MIRRORS=${MIRRORS:-}
SOFTWARE="ssh \
,ntpdate \
,firmware-linux-nonfree \
,firmware-ti-connectivity \
,grep \
,vim-nox \
,net-tools \
,wpasupplicant \
,iw \
,systemd \
,dhcpcd5 \
,wireless-tools \
,dbus \
,iproute2 \
"

SYSTEM_SIZE=${SYSTEM_SIZE:-'2048'} # 1G

SKIP_STAGE_1=0

while test $# -gt 0; do
case "$1" in
--debug|-d)
	set -x;
	shift
	;;
--skip-stage1|-s1)
	SKIP_STAGE_1=1
	shift
	;;
*)
	echo "Unrecognized option"
	exit 1
	;;
esac
done

echo "Fetch from... " $MIRRORS
echo "Install... " $SOFTWARE

echo "Dependency check"
for i in $REQUIRED; do
	command -v $i >/dev/null 2>&1 || { echo >&2 "require $i but it's not installed.  Aborting."; exit 1; }
	echo "[$i ... OK]"
done

bootstrap_stage_1() {
	echo "Clean build ..."
	rm -rf build
	mkdir build

	debootstrap --arch arm64 --include=${SOFTWARE// /} \
		--components=main,contrib,non-free,non-free-firmware $DISTRO build/rootfs $MIRRORS
}

bootstrap_stage_2() {
	echo "Copy rootfs to build/rootfs ..."
	echo "It may take a while ..."
	if test ! -d build/rootfs/etc/wpa_supplicant; then
		echo "--- /etc/wpa_supplicant not found"
		mkdir -p build/rootfs/etc/wpa_supplcant
	fi
	if test ! -d build/rootfs/etc/systemd/system; then
		echo "--- /etc/systemd/system not found"
		mkdir -p build/rootfs/etc/systemd/system
	fi
	cp -r rootfs/boot/* build/rootfs/boot
	cp -r rootfs/etc/netplan build/rootfs/etc
	cp -r rootfs/etc/rc.local build/rootfs/etc
	cp -r rootfs/etc/update-motd.d build/rootfs/etc
	cp -r rootfs/etc/wpa_supplicant build/rootfs/etc
	cp -r rootfs/etc/systemd/system build/rootfs/etc/systemd
	cp -r rootfs/lib/* build/rootfs/lib
	cp -r rootfs/root/* build/rootfs/root

	echo "Change / to build/rootfs ..."
	chroot build/rootfs /root/init.sh

	echo "Building image" $SYSTEM_SIZE
	dd if=/dev/zero of=build/rootfs.img bs=1M count=$SYSTEM_SIZE conv=sparse
	mkfs.ext2 -L rootfs -F build/rootfs.img
	if test $? -eq 0; then echo "mkfs.ext2 OK..."; fi

	if test -d build/loop; then rm -rf build/loop; fi
	mkdir build/loop
	mount -o loop build/rootfs.img build/loop

	echo "Copying root"
	(cd build/rootfs;tar -cf - *) | tar -xf - -C build/loop

	echo "Umount"
	umount build/loop
}

if test ${SKIP_STAGE_1} -eq 0; then
	bootstrap_stage_1
fi

bootstrap_stage_2

echo "Building sparse"
export SPARSE_IMG="debian_$DISTRO.hikey970.$VERSION.sparse.img"
img2simg build/rootfs.img build/$SPARSE_IMG

echo "Compressing"
tar -C build -czvf build/$SPARSE_IMG.tar.gz $SPARSE_IMG

echo "ALL COMPLETE"
ls -lha build/$SPARSE_IMG
sha1sum build/$SPARSE_IMG
exit 0

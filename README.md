# Hikey970 Debian Image

This is a Debian system image for Hikey970 SBC ONLY

## Download
[Release Page](https://github.com/mengzhuo/hikey970-ubuntu-image/releases)

## Usage

```
fastboot flash system debian_*.sparse.img
```

Login

```
username: hi
password: hikey970
```

Expend disk (no reboot required)

```
$ resize2fs /dev/sdd12 # max usage of disk
```

## Build from source

Install required

```
apt install android-tools-fsutils qemu-user-static debootstrap
```

```
git clone https://github.com/lucmann/hikey970-ubuntu-image -b hikey970-debian-image hikey970-debian-image
cd hikey970-ubuntu-image
./build.sh

```

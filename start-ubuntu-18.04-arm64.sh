#!/bin/bash

IMAGE_DIR=$(dirname "$0")
EFI_FILE="QEMU_EFI.fd"
ISO_FILE="ubuntu-18.04.6-server-arm64.iso"
DISK_FILE="ubuntu-18.04-arm64.qcow2"
DISK_SIZE=50G

echo "Current directory $IMAGE_DIR ..."
cd "$IMAGE_DIR"

download_efi() {
  wget https://releases.linaro.org/components/kernel/uefi-linaro/latest/release/qemu64/QEMU_EFI.fd
}

download_iso() {
  wget http://cdimage.ubuntu.com/releases/18.04/release/ubuntu-18.04.6-server-arm64.iso
}

install() {
  qemu-system-aarch64 \
    -m 2048 \
    -cpu cortex-a57 \
    -smp 4 \
    -M virt \
    -bios "$EFI_FILE" \
    -nographic \
    -drive if=none,file="$ISO_FILE",id=cdrom,media=cdrom \
    -device virtio-scsi-device -device scsi-cd,drive=cdrom \
    -drive if=none,file="$DISK_FILE",id=hd0 -device virtio-blk-device,drive=hd0 \
    -serial mon:stdio
}

# accelerated w/ KVM if you have an ARM64 host
# -enable-kvm \
start() {
  qemu-system-aarch64 \
    -m 2048 \
    -cpu cortex-a57 \
    -smp 4 \
    -M virt \
    -bios "$EFI_FILE" \
    -nographic \
    -drive if=none,file="$DISK_FILE",id=hd0 -device virtio-blk-device,drive=hd0 \
    -monitor none \
    -serial stdio
}

prepare() {
  local file="$1"
  local func="$2"
  if [ ! -f "$file" ]; then
    echo "Error: No such file or directory $file"
    echo "Now trying to download $file to $IMAGE_DIR. It may take a while"
    $func
    if [[ $? -ne 0 ]]; then
      echo "Failed to download $file. Terminated"
      exit 1
    fi
  fi
}

prepare $EFI_FILE download_efi

if [ ! -f "$DISK_FILE" ]; then
  echo "Create vdisk ..."
  qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"
fi

while [[ $# -gt 0 ]]; do
  case $1 in
  -i | -install)
    # iso required only when install
    prepare $ISO_FILE download_iso
    install
    shift
    ;;
  *)
    exit
    ;;
  esac
done

start
############################################################################
# Deepseek, are you serious?
############################################################################
# qemu-system-aarch64 \
#   -M virt \
#   -cpu cortex-a57 \
#   -smp 4 \
#   -m 4G \
#   -drive file="$DISK_FILE",if=none,id=drive0,cache=writeback \
#   -device virtio-blk-device,drive=drive0 \
#   -cdrom "$ISO_FILE" \
#   -netdev user,id=net0,hostfwd=tcp::2222-:22 \
#   -device virtio-net-device,netdev=net0 \
#   -bios $IMAGE_DIR/QEMU_EFI.fd \
#   -nographic \
#   -serial mon:stdio

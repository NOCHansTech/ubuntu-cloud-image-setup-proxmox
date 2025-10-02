#!/bin/bash

set -e

# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Branding
print_branding() {
    echo -e "${MAGENTA}"
    echo "╔══════════════════════════════════════════╗"
    echo "║          Ubuntu Cloud Setup              ║"
    echo "║              for Proxmox                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo "==========================================="
    echo "=========   Powered by HANS TECH   ========"
    echo "==========================================="
    echo -e "${NC}"
    echo -e "${YELLOW}Ubuntu Cloud Image Setup for Proxmox - HANS TECH${NC}"
    echo
}

print_branding

# Check and install libguestfs-tools if not installed
if ! command -v virt-customize &> /dev/null; then
    echo -e "${YELLOW}[INFO] libguestfs-tools belum terpasang. Menginstall...${NC}"
    apt-get update && apt-get install -y libguestfs-tools
fi

# Pilih versi Ubuntu
echo -e "${YELLOW}Pilih versi Ubuntu yang akan digunakan:${NC}"
echo "1) Ubuntu 18.04 LTS (bionic)"
echo "2) Ubuntu 20.04 LTS (focal)"
echo "3) Ubuntu 22.04 LTS (jammy)"
echo "4) Ubuntu 24.04 LTS (noble)"
read -p "$(echo -e ${YELLOW}Masukkan pilihan (1-4): ${NC})" UBUNTU_VER

case $UBUNTU_VER in
    1) UBUNTU_CODE="bionic";;
    2) UBUNTU_CODE="focal";;
    3) UBUNTU_CODE="jammy";;
    4) UBUNTU_CODE="noble";;
    *) echo -e "${RED}[ERROR] Pilihan tidak valid!${NC}"; exit 1;;
esac

IMAGE_URL="https://cloud-images.ubuntu.com/${UBUNTU_CODE}/current/${UBUNTU_CODE}-server-cloudimg-amd64.img"
IMAGE_NAME="${UBUNTU_CODE}-server-cloudimg-amd64.img"
WORKING_IMAGE="${UBUNTU_CODE}.img"

# Input user
read -p "$(echo -e ${YELLOW}Masukkan VM ID: ${NC})" VM_ID
read -p "$(echo -e ${YELLOW}Masukkan nama VM: ${NC})" VM_NAME
read -p "$(echo -e ${YELLOW}Masukkan jumlah RAM (MB): ${NC})" RAM
read -p "$(echo -e ${YELLOW}Masukkan jumlah CPU cores: ${NC})" CPU
read -p "$(echo -e ${YELLOW}Masukkan nama storage untuk disk & cloudinit (contoh: local-lvm): ${NC})" STORAGE
read -p "$(echo -e ${YELLOW}Masukkan ukuran resize disk (contoh: 50G): ${NC})" RESIZE_SIZE
read -p "$(echo -e ${YELLOW}Masukkan nama bridge network (contoh: vmbr0): ${NC})" BRIDGE
read -p "$(echo -e ${YELLOW}Masukkan VLAN ID (kosongkan jika tidak ada): ${NC})" VLAN_ID
read -p "$(echo -e ${YELLOW}Masukkan ci user (contoh: ubuntu): ${NC})" CIUSER
read -p "$(echo -e ${YELLOW}Masukkan ci password: ${NC})" CIPASSWORD

# Validasi wajib isi
if [[ -z "$VM_ID" || -z "$VM_NAME" || -z "$RAM" || -z "$CPU" || -z "$STORAGE" || -z "$RESIZE_SIZE" || -z "$BRIDGE" || -z "$CIUSER" || -z "$CIPASSWORD" ]]; then
    echo -e "${RED}[ERROR] Semua input wajib diisi kecuali VLAN ID!${NC}"
    exit 1
fi

# Download image jika belum ada
if [ ! -f "$IMAGE_NAME" ]; then
    echo -e "${GREEN}[INFO] Mengunduh image Ubuntu Cloud versi ${UBUNTU_CODE}...${NC}"
    wget "$IMAGE_URL" -O "$IMAGE_NAME"
else
    echo -e "${GREEN}[INFO] Image sudah tersedia, melewati download.${NC}"
fi

# Copy image ke working image
cp "$IMAGE_NAME" "$WORKING_IMAGE"

# Modifikasi image (install qemu-guest-agent dan kosongkan machine-id)
echo -e "${GREEN}[INFO] Menginstall qemu-guest-agent dan mengosongkan machine-id...${NC}"
virt-customize -a "$WORKING_IMAGE" --install qemu-guest-agent --truncate /etc/machine-id

# Resize disk image
echo -e "${GREEN}[INFO] Resize image menjadi $RESIZE_SIZE...${NC}"
qemu-img resize "$WORKING_IMAGE" "$RESIZE_SIZE"

# Konfigurasi network
if [[ -n "$VLAN_ID" ]]; then
    NET_CONFIG="virtio,bridge=${BRIDGE},tag=${VLAN_ID}"
else
    NET_CONFIG="virtio,bridge=${BRIDGE}"
fi

# Buat VM
echo -e "${GREEN}[INFO] Membuat VM dengan ID $VM_ID...${NC}"
qm create "$VM_ID" \
    --name "$VM_NAME" \
    --memory "$RAM" \
    --cores "$CPU" \
    --cpu host \
    --net0 "$NET_CONFIG" \
    --ostype l26 \
    --scsihw virtio-scsi-pci \
    --agent 1 \
    --boot order=scsi0 \
    --ciuser "$CIUSER" \
    --cipassword "$CIPASSWORD" \
    --ipconfig0 ip=dhcp \
    --ide0 "${STORAGE}:cloudinit" \
    --ide2 none \
    --onboot 1

# Import disk image ke VM
echo -e "${GREEN}[INFO] Mengimport disk ke VM $VM_ID di storage $STORAGE...${NC}"
qm disk import "$VM_ID" "$WORKING_IMAGE" "$STORAGE"

# Cleanup
rm -f "$WORKING_IMAGE"

echo -e "${GREEN}[SELESAI] VM $VM_ID ($VM_NAME) berhasil dibuat dengan IPv4 DHCP dan cloud-init disk di storage $STORAGE.${NC}"

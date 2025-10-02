#!/bin/bash

set -e

# Warna output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Branding
print_branding() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════╗"
    echo "║          Ubuntu Cloud Setup              ║"
    echo "║              for Proxmox                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo "==========================================="
    echo "=========   Powered by HANS TECH   ========"
    echo "==========================================="
    echo -e "${NC}\n"
    echo -e "${GREEN}Ubuntu Cloud Image Setup for Proxmox - HANS TECH${NC}\n"
}

print_branding

# Check and install libguestfs-tools if not installed
if ! command -v virt-customize &> /dev/null; then
    echo -e "${GREEN}[INFO] libguestfs-tools belum terpasang. Menginstall...${NC}\n"
    apt-get update && apt-get install -y libguestfs-tools
fi

# Pilih versi Ubuntu
echo -e "${BLUE}Pilih versi Ubuntu yang akan digunakan:${NC}"
echo "1) Ubuntu 18.04 LTS - bionic"
echo "2) Ubuntu 20.04 LTS - focal"
echo "3) Ubuntu 22.04 LTS - jammy"
echo -e "4) Ubuntu 24.04 LTS - noble\n"
read -p $'\033[0;34mMasukkan pilihan (1-4): \033[0m' UBUNTU_VER
echo ""

case $UBUNTU_VER in
    1) UBUNTU_CODE="bionic";;
    2) UBUNTU_CODE="focal";;
    3) UBUNTU_CODE="jammy";;
    4) UBUNTU_CODE="noble";;
    *) echo -e "${GREEN}[ERROR] Pilihan tidak valid!${NC}"; exit 1;;
esac

IMAGE_URL="https://cloud-images.ubuntu.com/${UBUNTU_CODE}/current/${UBUNTU_CODE}-server-cloudimg-amd64.img"
IMAGE_NAME="${UBUNTU_CODE}-server-cloudimg-amd64.img"
WORKING_IMAGE="${UBUNTU_CODE}.img"

# Input user
read -p $'\033[0;34mMasukkan VM ID: \033[0m' VM_ID
read -p $'\033[0;34mMasukkan nama VM: \033[0m' VM_NAME
read -p $'\033[0;34mMasukkan jumlah RAM (MB): \033[0m' RAM
read -p $'\033[0;34mMasukkan jumlah CPU cores: \033[0m' CPU
read -p $'\033[0;34mMasukkan nama storage untuk disk & cloudinit (contoh: local-lvm): \033[0m' STORAGE
read -p $'\033[0;34mMasukkan ukuran resize disk (contoh: 50G): \033[0m' RESIZE_SIZE
read -p $'\033[0;34mMasukkan nama bridge network (contoh: vmbr0): \033[0m' BRIDGE
read -p $'\033[0;34mMasukkan VLAN ID (kosongkan jika tidak ada): \033[0m' VLAN_ID
read -p $'\033[0;34mMasukkan ci user (contoh: ubuntu): \033[0m' CIUSER
read -p $'\033[0;34mMasukkan ci password: \033[0m' CIPASSWORD
echo ""

# Validasi wajib isi
if [[ -z "$VM_ID" || -z "$VM_NAME" || -z "$RAM" || -z "$CPU" || -z "$STORAGE" || -z "$RESIZE_SIZE" || -z "$BRIDGE" || -z "$CIUSER" || -z "$CIPASSWORD" ]]; then
    echo -e "${GREEN}[ERROR] Semua input wajib diisi kecuali VLAN ID!${NC}\n"
    exit 1
fi

# Download image jika belum ada
if [ ! -f "$IMAGE_NAME" ]; then
    echo -e "${GREEN}[INFO] Mengunduh image Ubuntu Cloud versi ${UBUNTU_CODE}...${NC}\n"
    wget "$IMAGE_URL" -O "$IMAGE_NAME"
else
    echo -e "${GREEN}[INFO] Image sudah tersedia, melewati download.${NC}\n"
fi

# Copy image ke working image
cp "$IMAGE_NAME" "$WORKING_IMAGE"

# Modifikasi image
echo -e "${GREEN}[INFO] Menginstall qemu-guest-agent dan mengosongkan machine-id...${NC}\n"
virt-customize -a "$WORKING_IMAGE" --install qemu-guest-agent --truncate /etc/machine-id

# Resize disk image
echo -e "${GREEN}[INFO] Resize image menjadi $RESIZE_SIZE...${NC}\n"
qemu-img resize "$WORKING_IMAGE" "$RESIZE_SIZE"

# Konfigurasi network
if [[ -n "$VLAN_ID" ]]; then
    NET_CONFIG="virtio,bridge=${BRIDGE},tag=${VLAN_ID}"
else
    NET_CONFIG="virtio,bridge=${BRIDGE}"
fi

# Buat VM
echo -e "${GREEN}[INFO] Membuat VM dengan ID $VM_ID...${NC}\n"
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
echo -e "${GREEN}[INFO] Mengimport disk ke VM $VM_ID di storage $STORAGE...${NC}\n"
qm disk import "$VM_ID" "$WORKING_IMAGE" "$STORAGE"
qm set "$VM_ID" --scsi0 "${STORAGE}:${VM_ID}/vm-${VM_ID}-disk-0.raw"

# Cleanup
rm -f "$WORKING_IMAGE"

echo -e "\n${GREEN}[SELESAI] VM $VM_ID ($VM_NAME) berhasil dibuat dengan IPv4 DHCP dan cloud-init disk di storage $STORAGE.${NC}\n"
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}Login ke VM menggunakan:${NC}"
echo -e "   ${BLUE}Username:${NC} $CIUSER"
echo -e "   ${BLUE}Password:${NC} $CIPASSWORD"
echo -e "${BLUE}============================================${NC}\n"

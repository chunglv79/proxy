#!/bin/bash
# ======================================
# Script tạo & cài SOCKS5 trên GCP (Tokyo / Osaka / Seoul)
# ======================================

# ==== THÔNG SỐ CƠ BẢN ====
BASE_NAME="mrmeoproxy"
MACHINE_TYPE="e2-micro"
IMAGE_PROJECT="debian-cloud"
IMAGE_FAMILY="debian-11"
PORTS=()
USERS=()
PASSES=()

# ==== NHẬP SỐ VPS ====
read -p "Số VPS Tokyo: " TOKYO
read -p "Số VPS Osaka: " OSAKA
read -p "Số VPS Seoul: " SEOUL

TOTAL=$((TOKYO + OSAKA + SEOUL))

# ==== RANDOM PORT/USER/PASS ====
for ((i=1; i<=TOTAL; i++)); do
  PORTS+=($((10000 + RANDOM % 50000)))
  USERS+=("mrmeo${RANDOM:0:5}")
  PASSES+=("pw${RANDOM:0:8}")
done

# ====== HÀM TẠO VPS ======
create_vps_group() {
  local COUNT=$1
  local ZONE=$2
  local PREFIX=$3

  for ((i=1; i<=COUNT; i++)); do
    name="${BASE_NAME}-${PREFIX}-${i}"
    echo "🚀 Tạo VPS $name ($ZONE)"
    gcloud compute instances create "$name" \
      --zone="$ZONE" \
      --machine-type="$MACHINE_TYPE" \
      --image-family="$IMAGE_FAMILY" \
      --image-project="$IMAGE_PROJECT" \
      --boot-disk-size=10GB \
      --tags=socks5-proxy \
      --quiet &
  done
}

# ====== HÀM CÀI SOCKS5 ======
install_socks5_group() {
  local COUNT=$1
  local ZONE=$2
  local PREFIX=$3
  local DNS_OPTION=$4
  local start_index=$5

  for ((i=1; i<=COUNT; i++)); do
    idx=$((start_index + i))
    name="${BASE_NAME}-${PREFIX}-${i}"
    port="${PORTS[$((idx-1))]}"
    user="${USERS[$((idx-1))]}"
    pass="${PASSES[$((idx-1))]}"

    echo "📦 Cài SOCKS5 trên $name ($ZONE, port: $port, user: $user)"
    gcloud compute ssh "$name" --zone="$ZONE" --command "
      wget -O install-socks5.sh https://raw.githubusercontent.com/chunglv79/proxy/main/install-socks5-random-ggc.sh &&
      chmod +x install-socks5.sh &&
      echo -e \"$DNS_OPTION\n$port\n$user\n$pass\" | sudo ./install-socks5.sh
    " &
  done
}

# ====== BẮT ĐẦU TẠO VPS ======
echo "🚀 Đang tạo VPS..."
[ $TOKYO -gt 0 ] && create_vps_group $TOKYO "asia-northeast1-c" "tokyo"
[ $OSAKA -gt 0 ] && create_vps_group $OSAKA "asia-northeast2-a" "osaka"
[ $SEOUL -gt 0 ] && create_vps_group $SEOUL "asia-northeast3-a" "seoul"

wait
echo "✅ Tạo VPS xong!"

# ====== CÀI SOCKS5 TRÊN VPS ======
echo "🚀 Bắt đầu cài SOCKS5..."

start=0
[ $TOKYO -gt 0 ] && install_socks5_group $TOKYO "asia-northeast1-c" "tokyo" 1 $start && start=$((start+TOKYO))
[ $OSAKA -gt 0 ] && install_socks5_group $OSAKA "asia-northeast2-a" "osaka" 1 $start && start=$((start+OSAKA))
[ $SEOUL -gt 0 ] && install_socks5_group $SEOUL "asia-northeast3-a" "seoul" 2 $start && start=$((start+SEOUL))

wait
echo "✅ Cài SOCKS5 hoàn tất!"

# ====== IN DANH SÁCH SOCKS5 ======
echo "================ SOCKS5 PROXY LIST ================"
start=0
for zone in "tokyo:$TOKYO:asia-northeast1-c" "osaka:$OSAKA:asia-northeast2-a" "seoul:$SEOUL:asia-northeast3-a"; do
  IFS=":" read -r PREFIX COUNT ZONE <<< "$zone"
  for ((i=1; i<=COUNT; i++)); do
    idx=$((start + i))
    name="${BASE_NAME}-${PREFIX}-${i}"
    ip=$(gcloud compute instances describe "$name" --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    echo "$ip:${PORTS[$((idx-1))]}:${USERS[$((idx-1))]}:${PASSES[$((idx-1))]}"
  done
  start=$((start+COUNT))
done
echo "==================================================="

#!/bin/bash
# ======================================
# Script tạo & cài SOCKS5 trên GCP (Tokyo / Osaka / Seoul)
# Sequential version (không chạy song song)
# ======================================

read -p "👉 Nhập BASE_NAME cho VPS (mặc định: mrmeoproxy): " BASE_NAME
BASE_NAME=${BASE_NAME:-mrmeoproxy}
MACHINE_TYPE="e2-micro"
IMAGE_PROJECT="ubuntu-os-cloud"
IMAGE_FAMILY="ubuntu-minimal-2204-lts"

declare -a PORTS USERS PASSES

# ==== NHẬP SỐ VPS ====
read -p "Số VPS Tokyo [0]: " TOKYO
TOKYO=${TOKYO:-0}

read -p "Số VPS Osaka [0]: " OSAKA
OSAKA=${OSAKA:-0}

read -p "Số VPS Seoul [0]: " SEOUL
SEOUL=${SEOUL:-0}

TOTAL=$((TOKYO + OSAKA + SEOUL))

# ==== CHỌN MODE AUTO/MANUAL ====
echo "Chọn chế độ cấu hình proxy:"
echo "1) Auto (random port + user + pass)"
echo "2) Manual (tự nhập port + user + pass)"
read -p "Lựa chọn [1/2]: " CONFIG_MODE
CONFIG_MODE=${CONFIG_MODE:-1}

if [ "$CONFIG_MODE" == "2" ]; then
  read -p "Nhập PORT cho SOCKS5 proxy [0-65535]: " SOCKS5_PORT
  SOCKS5_PORT=${SOCKS5_PORT:-1099}
  read -p "Nhập USERNAME cho proxy [mrmeo2025]: " SOCKS5_USER
  SOCKS5_USER=${SOCKS5_USER:-mrmeo2025}
  read -p "Nhập PASSWORD cho proxy [pmbhgq844js78678bfjhfg]: " SOCKS5_PASS
  SOCKS5_PASS=${SOCKS5_PASS:-pmbhgq844js78678bfjhfg}

  for ((i=1; i<=TOTAL; i++)); do
    PORTS+=("$SOCKS5_PORT")
    USERS+=("$SOCKS5_USER")
    PASSES+=("$SOCKS5_PASS")
  done
else
  for ((i=1; i<=TOTAL; i++)); do
    PORTS+=("$((RANDOM % 10000 + 20000))")
    USERS+=("user$((RANDOM % 9000 + 1000))")
    PASSES+=("pass$((RANDOM % 9000 + 1000))")
  done
fi

# ==== NETWORK + FIREWALL ====
NET_NAME="${BASE_NAME}-network"
FIREWALL_NAME="${BASE_NAME}-allow-all"

# Tạo network riêng nếu chưa có
if ! gcloud compute networks describe "$NET_NAME" >/dev/null 2>&1; then
  echo "🌐 Network $NET_NAME chưa có, đang tạo..."
  gcloud compute networks create "$NET_NAME" --subnet-mode=auto --quiet
else
  echo "⚠️ Network $NET_NAME đã tồn tại, bỏ qua."
fi

# Tạo firewall rule nếu chưa có
if ! gcloud compute firewall-rules describe "$FIREWALL_NAME" >/dev/null 2>&1; then
  echo "🛡️ Firewall rule $FIREWALL_NAME chưa có, đang tạo..."
  gcloud compute firewall-rules create "$FIREWALL_NAME" \
    --network="$NET_NAME" \
    --allow=tcp,udp,icmp \
    --direction=INGRESS \
    --priority=1000 \
    --source-ranges=0.0.0.0/0 \
    --quiet
else
  echo "⚠️ Firewall rule $FIREWALL_NAME đã tồn tại, bỏ qua."
fi

while ! gcloud compute networks describe "$NET_NAME" --format="value(selfLink)" >/dev/null 2>&1; do
  echo "⏳ Network $NET_NAME chưa ready, chờ 5s..."
  sleep 5
done

# ==== SSH KEY ====
if [ ! -f ~/.ssh/google_compute_engine ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/google_compute_engine -N ""
fi

if ! gcloud compute os-login ssh-keys list --format="value(key)" | grep -q "$(cat ~/.ssh/google_compute_engine.pub)"; then
    gcloud compute os-login ssh-keys add --key-file ~/.ssh/google_compute_engine.pub
fi

# ====== HÀM TẠO VPS ======
create_vps_group() {
  local COUNT=$1
  local ZONE=$2
  local PREFIX=$3
  local start_index=$4

  for ((i=1; i<=COUNT; i++)); do
    idx=$((start_index + i))
    name="${BASE_NAME}-${PREFIX}-${i}"

    echo "🚀 Tạo VPS $name ($ZONE)"
    gcloud compute instances create "$name" \
      --zone="$ZONE" \
      --machine-type="$MACHINE_TYPE" \
      --image-family="$IMAGE_FAMILY" \
      --image-project="$IMAGE_PROJECT" \
      --boot-disk-size=10GB \
      --network="$NET_NAME" \
      --tags=socks5-proxy \
      --quiet
  done
}

# ====== HÀM CHECK SSH + CÀI SOCKS5 ======
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

    echo "⏳ Kiểm tra SSH cho $name..."
    IP=$(gcloud compute instances describe "$name" \
          --zone "$ZONE" \
          --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

    # Check SSH tối đa 1 phút
    for ((j=1; j<=30; j++)); do
      if nc -z "$IP" 22 &>/dev/null; then
        echo "✅ SSH OK trên $name ($IP)"
        break
      fi
      sleep 2
    done

    echo "📦 Cài SOCKS5 trên $name (port: $port, user: $user)"
    gcloud compute ssh "$name" --zone="$ZONE" --command "
      wget -O install-socks5.sh https://raw.githubusercontent.com/chunglv79/proxy/main/install-socks5-random-ggc.sh &&
      chmod +x install-socks5.sh &&
      echo -e \"$DNS_OPTION\n$port\n$user\n$pass\" | sudo ./install-socks5.sh
    "
  done
}
# ====== BẮT ĐẦU TẠO VPS ======
echo "🚀 Bắt đầu tạo VPS..."
start=0
[ $TOKYO -gt 0 ] && create_vps_group $TOKYO "asia-northeast1-c" "tokyo" $start && start=$((start+TOKYO))
[ $OSAKA -gt 0 ] && create_vps_group $OSAKA "asia-northeast2-a" "osaka" $start && start=$((start+OSAKA))
[ $SEOUL -gt 0 ] && create_vps_group $SEOUL "asia-northeast3-a" "seoul" $start && start=$((start+SEOUL))

echo "⏳ Đợi 30s cho toàn bộ VPS boot..."
sleep 30

# ====== CHECK SSH + CÀI SOCKS5 ======
echo "📦 Bắt đầu cài SOCKS5 trên các VPS..."
start=0
[ $TOKYO -gt 0 ] && install_socks5_group $TOKYO "asia-northeast1-c" "tokyo" 1 $start && start=$((start+TOKYO))
[ $OSAKA -gt 0 ] && install_socks5_group $OSAKA "asia-northeast2-a" "osaka" 1 $start && start=$((start+OSAKA))
[ $SEOUL -gt 0 ] && install_socks5_group $SEOUL "asia-northeast3-a" "seoul" 2 $start && start=$((start+SEOUL))


echo "✅ Hoàn tất cài SOCKS5!"

# ====== IN DANH SÁCH ======
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

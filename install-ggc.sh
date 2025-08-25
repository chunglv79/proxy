#!/bin/bash

# ====== PHẦN SCRIPT CHÍNH BẮT ĐẦU ======

# Nhập tên định danh VPS
read -p "Nhập tên cho VPS [NAME]: " BASE_NAME
BASE_NAME=${BASE_NAME:-proxy}

# Chọn chế độ cấu hình
echo "Chọn chế độ cấu hình proxy:"
echo "1) Auto (tự random VPS + user + pass ngẫu nhiên)"
echo "2) Manual (tự nhập port + user + pass)"
read -p "Lựa chọn [1/2]: " CONFIG_MODE
CONFIG_MODE=${CONFIG_MODE:-1}

# Nhập số VPS muốn tạo
read -p "Nhập số VPS muốn tạo [1-50]: " VPS_COUNT
VPS_COUNT=${VPS_COUNT:-4}

# Chọn zone
echo "Chọn Zone:"
echo "1) Nhật - Tokyo - asia-northeast1-a"
echo "2) Nhật - Tokyo - asia-northeast1-b"
echo "3) Nhật - Tokyo - asia-northeast1-c"
echo "4) Nhật - Osaka - asia-northeast2-a"
echo "5) Nhật - Osaka - asia-northeast2-b"
echo "6) Nhật - Osaka - asia-northeast2-c"
echo "7) Hàn - Seoul - asia-northeast3-a"
echo "8) Hàn - Seoul - asia-northeast3-b"
echo "9) Hàn - Seoul - asia-northeast3-c"
read -p "Chọn số [1-9]: " ZONE_CHOICE

case $ZONE_CHOICE in
  1) ZONE="asia-northeast1-a" ;;
  2) ZONE="asia-northeast1-b" ;;
  3) ZONE="asia-northeast1-c" ;;
  4) ZONE="asia-northeast2-a" ;;
  5) ZONE="asia-northeast2-b" ;;
  6) ZONE="asia-northeast2-c" ;;
  7) ZONE="asia-northeast3-a" ;;
  8) ZONE="asia-northeast3-b" ;;
  9) ZONE="asia-northeast3-c" ;;
  *) echo "Sai lựa chọn, mặc định: asia-northeast1-a"; ZONE="asia-northeast1-a" ;;
esac

# Tạo biến PORT, USER, PASS
declare -a PORTS USERS PASSES

if [ "$CONFIG_MODE" == "2" ]; then
  read -p "Nhập PORT cho SOCKS5 proxy [0-65535]: " SOCKS5_PORT
  SOCKS5_PORT=${SOCKS5_PORT:-25432}
  read -p "Nhập USERNAME cho proxy [user123]: " SOCKS5_USER
  SOCKS5_USER=${SOCKS5_USER:-user123}
  read -p "Nhập PASSWORD cho proxy [Dian@123]: " SOCKS5_PASS
  echo
  SOCKS5_PASS=${SOCKS5_PASS:-Dian@123}

  for ((i=1; i<=VPS_COUNT; i++)); do
    PORTS+=("$SOCKS5_PORT")
    USERS+=("$SOCKS5_USER")
    PASSES+=("$SOCKS5_PASS")
  done
else
  for ((i=1; i<=VPS_COUNT; i++)); do
    PORTS+=("$((RANDOM % 10000 + 20000))")
    USERS+=("user$((RANDOM % 9000 + 1000))")
    PASSES+=("pass$((RANDOM % 9000 + 1000))")
  done
fi

# ====== BƯỚC 1: MỞ FIREWALL ======
PORT_LIST=$(printf "tcp:%s," "${PORTS[@]}")
PORT_LIST=${PORT_LIST%,}

gcloud compute firewall-rules create "${BASE_NAME}-open-port-proxy" \
  --allow="$PORT_LIST" \
  --description="Allow SOCKS5 proxy ports" \
  --direction=INGRESS \
  --priority=1000 \
  --source-ranges=0.0.0.0/0 \
  --quiet || echo "⚠️ Firewall rule đã tồn tại"

# ====== BƯỚC 2: TẠO VPS ======
for ((i=1; i<=VPS_COUNT; i++)); do
  echo "===> Tạo VPS ${BASE_NAME}-${i} tại $ZONE"
  gcloud compute instances create "${BASE_NAME}-${i}" \
    --zone="$ZONE" \
    --machine-type=e2-micro \
    --image-project=ubuntu-os-cloud \
    --image-family=ubuntu-minimal-2204-lts \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-ssd \
    --quiet
done
echo "⏳ Chờ 30s cho VPS boot xong SSH..."
  sleep 30
# ====== BƯỚC 3: CÀI FILE VÀ CẤU HÌNH SOCKS5 ======
for ((i=1; i<=VPS_COUNT; i++)); do
  name="${BASE_NAME}-${i}"
  port="${PORTS[$((i-1))]}"
  user="${USERS[$((i-1))]}"
  pass="${PASSES[$((i-1))]}"

  echo "📦 Cài SOCKS5 trên $name (zone: $ZONE, port: $port, user: $user) ..."

  gcloud compute ssh "$name" --zone="$ZONE" --command "
    wget -O install-socks5.sh https://raw.githubusercontent.com/chunglv79/proxy/main/install-socks5-random-ggc.sh &&
    chmod +x install-socks5.sh &&
    echo -e \"1\n$port\n$user\n$pass\" | sudo ./install-socks5.sh
  "
done

# ====== IN DANH SÁCH PROXY ======
echo ""
echo "================ SOCKS5 PROXY LIST ================"
for ((i=1; i<=VPS_COUNT; i++)); do
  ip=$(gcloud compute instances describe "${BASE_NAME}-${i}" \
    --zone="$ZONE" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
  echo "${ip}:${PORTS[$((i-1))]}:${USERS[$((i-1))]}:${PASSES[$((i-1))]}"
done

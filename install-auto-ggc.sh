#!/bin/bash

# ====== SCRIPT TẠO NHIỀU VPS PROXY NHANH ======

read -p "Nhập tên cho VPS [NAME]: " BASE_NAME
BASE_NAME=${BASE_NAME:-proxy}

echo "Chọn chế độ cấu hình proxy:"
echo "1) Auto (random port + user + pass)"
echo "2) Manual (tự nhập port + user + pass)"
read -p "Lựa chọn [1/2]: " CONFIG_MODE
CONFIG_MODE=${CONFIG_MODE:-1}

echo "📦 Chọn mục thường tạo:"
echo "1) 4 Tokyo , 4 Osaka , 0 Seoul"
echo "2) 8 Tokyo , 8 Osaka , 0 Seoul"
echo "3) 0 Tokyo , 0 Osaka , 4 Seoul"
echo "4) 0 Tokyo , 0 Osaka , 8 Seoul"
echo "5) 4 Tokyo , 4 Osaka , 4 Seoul"
echo "6) 8 Tokyo , 8 Osaka , 8 Seoul"
read -p "Chọn số [1-6]: " PRESET

case $PRESET in
  1) TOKYO=4; OSAKA=4; SEOUL=0 ;;
  2) TOKYO=8; OSAKA=8; SEOUL=0 ;;
  3) TOKYO=0; OSAKA=0; SEOUL=4 ;;
  4) TOKYO=0; OSAKA=0; SEOUL=8 ;;
  5) TOKYO=4; OSAKA=4; SEOUL=4 ;;
  6) TOKYO=8; OSAKA=8; SEOUL=8 ;;
  *) TOKYO=4; OSAKA=4; SEOUL=0 ;;
esac

TOTAL=$((TOKYO + OSAKA + SEOUL))
echo "➡️ Sẽ tạo: $TOKYO Tokyo, $OSAKA Osaka, $SEOUL Seoul (Tổng: $TOTAL VPS)"

# ====== TẠO DANH SÁCH PORT/USER/PASS ======
declare -a PORTS USERS PASSES

if [ "$CONFIG_MODE" == "2" ]; then
  read -p "Nhập PORT cho SOCKS5 proxy [0-65535]: " SOCKS5_PORT
  SOCKS5_PORT=${SOCKS5_PORT:-25432}
  read -p "Nhập USERNAME cho proxy [user123]: " SOCKS5_USER
  SOCKS5_USER=${SOCKS5_USER:-user123}
  read -p "Nhập PASSWORD cho proxy [Dian@123]: " SOCKS5_PASS
  SOCKS5_PASS=${SOCKS5_PASS:-Dian@123}

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

# ====== MỞ FIREWALL ======
PORT_LIST=$(printf "tcp:%s," "${PORTS[@]}")
PORT_LIST=${PORT_LIST%,}

gcloud compute firewall-rules create "${BASE_NAME}-open-port-proxy" \
  --allow="$PORT_LIST" \
  --description="Allow SOCKS5 proxy ports" \
  --direction=INGRESS \
  --priority=1000 \
  --source-ranges=0.0.0.0/0 \
  --quiet || echo "⚠️ Firewall rule đã tồn tại"

# ====== TẠO VPS ======
index=0
create_vps_group() {
  local COUNT=$1
  local ZONE=$2
  local LOC_NAME=$3

  for ((i=1; i<=COUNT; i++)); do
    index=$((index+1))
    echo "===> Tạo VPS ${BASE_NAME}-${index} tại $ZONE ($LOC_NAME)"
    gcloud compute instances create "${BASE_NAME}-${index}" \
      --zone="$ZONE" \
      --machine-type=e2-micro \
      --image-project=ubuntu-os-cloud \
      --image-family=ubuntu-minimal-2204-lts \
      --boot-disk-size=10GB \
      --boot-disk-type=pd-ssd \
      --quiet
  done
}

[ $TOKYO -gt 0 ] && create_vps_group $TOKYO "asia-northeast1-c" "Tokyo"
[ $OSAKA -gt 0 ] && create_vps_group $OSAKA "asia-northeast2-a" "Osaka"
[ $SEOUL -gt 0 ] && create_vps_group $SEOUL "asia-northeast3-a" "Seoul"

echo "⏳ Chờ 30s cho VPS boot..."
sleep 30

# Tạo SSH key nếu chưa có
if [ ! -f ~/.ssh/google_compute_engine ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/google_compute_engine -N ""
fi

# Add key vào Google Cloud OS Login nếu chưa tồn tại
if ! gcloud compute os-login ssh-keys list --format="value(key)" | grep -q "$(cat ~/.ssh/google_compute_engine.pub)"; then
    gcloud compute os-login ssh-keys add --key-file ~/.ssh/google_compute_engine.pub
fi

# ====== CÀI SOCKS5 ======
index=0
install_socks5_group() {
  local COUNT=$1
  local ZONE=$2
  local DNS_OPTION=$3

  for ((i=1; i<=COUNT; i++)); do
    index=$((index+1))
    name="${BASE_NAME}-${index}"
    port="${PORTS[$((index-1))]}"
    user="${USERS[$((index-1))]}"
    pass="${PASSES[$((index-1))]}"

    echo "📦 Cài SOCKS5 trên $name ($ZONE, port: $port, user: $user)"
    gcloud compute ssh "$name" --zone="$ZONE" --command "
      wget -O install-socks5.sh https://raw.githubusercontent.com/chunglv79/proxy/main/install-socks5-random-ggc.sh &&
      chmod +x install-socks5.sh &&
      echo -e \"$DNS_OPTION\n$port\n$user\n$pass\" | sudo ./install-socks5.sh
    "
  done
}

[ $TOKYO -gt 0 ] && install_socks5_group $TOKYO "asia-northeast1-c" 1
[ $OSAKA -gt 0 ] && install_socks5_group $OSAKA "asia-northeast2-a" 1
[ $SEOUL -gt 0 ] && install_socks5_group $SEOUL "asia-northeast3-a" 2

# ====== IN DANH SÁCH PROXY ======
echo ""
echo "================ SOCKS5 PROXY LIST ================"

index=0
for ((i=1; i<=TOTAL; i++)); do
    index=$((index+1))

    if [ $index -le $TOKYO ]; then
        zone="asia-northeast1-c"
    elif [ $index -le $((TOKYO+OSAKA)) ]; then
        zone="asia-northeast2-a"
    else
        zone="asia-northeast3-a"
    fi

    ip=$(gcloud compute instances describe "${BASE_NAME}-${index}" \
        --zone="$zone" \
        --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

    echo "${ip}:${PORTS[$((index-1))]}:${USERS[$((index-1))]}:${PASSES[$((index-1))]}"
done

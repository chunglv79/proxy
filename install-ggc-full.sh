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

# ====== BƯỚC 3: CÀI FILE VÀ CẤU HÌNH SOCKS5 ======
for ((i=1; i<=VPS_COUNT; i++)); do
  name="${BASE_NAME}-${i}"
  port="${PORTS[$((i-1))]}"
  user="${USERS[$((i-1))]}"
  pass="${PASSES[$((i-1))]}"

  cat > install_socks5.sh <<EOF
#!/usr/bin/env bash
set -e
SOCKS5_PORT=$port
SOCKS5_USER=$user
SOCKS5_PASS=$pass
EXT_IF=\$(ip route | awk '/default/ {print \$5; exit}')
EXT_IP=\$(curl -4 -s https://api.ipify.org)

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y dante-server curl iptables iptables-persistent >/dev/null 2>&1

useradd -M -N -s /usr/sbin/nologin "\$SOCKS5_USER" || true
echo "\$SOCKS5_USER:\$SOCKS5_PASS" | chpasswd >/dev/null 2>&1

cat > /etc/danted.conf <<EOL
logoutput: syslog /var/log/danted.log
internal: 0.0.0.0 port = \$SOCKS5_PORT
external: \$EXT_IF
method: pam
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: connect disconnect error
}
EOL

chmod 644 /etc/danted.conf
systemctl restart danted
systemctl enable danted

iptables -I INPUT -p tcp --dport \$SOCKS5_PORT -j ACCEPT
iptables-save > /etc/iptables/rules.v4 || true

echo "✓ SOCKS5 proxy running on: socks5://\$EXT_IP:\$SOCKS5_PORT:\$SOCKS5_USER:\$SOCKS5_PASS"
rm -f \$0
EOF

  chmod +x install_socks5.sh
  gcloud compute scp install_socks5.sh "$name":~/install_socks5.sh --zone="$ZONE" --quiet
  gcloud compute ssh "$name" --zone="$ZONE" --command="sudo bash ~/install_socks5.sh" < /dev/null
  rm -f install_socks5.sh
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

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

# Tạo biến PORT, USER, PASS
declare -a PORTS USERS PASSES

if [ "$CONFIG_MODE" == "2" ]; then
  read -p "Nhập PORT cho SOCKS5 proxy [0-65535]: " SOCKS5_PORT
  SOCKS5_PORT=${SOCKS5_PORT:-25432}
  read -p "Nhập USERNAME cho proxy [user123]: " SOCKS5_USER
  SOCKS5_USER=${SOCKS5_USER:-user123}
  read -s -p "Nhập PASSWORD cho proxy [Dian@123]: " SOCKS5_PASS
  echo
  SOCKS5_PASS=${SOCKS5_PASS:-Dian@123}

  for i in {1..8}; do
    PORTS+=("$SOCKS5_PORT")
    USERS+=("$SOCKS5_USER")
    PASSES+=("$SOCKS5_PASS")
  done
else
  for i in {1..8}; do
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

# ====== BƯỚC 2: TẠO 8 VPS ======
zones=(asia-northeast1-c asia-northeast2-c)
index=1
for z in "${zones[@]}"; do
  for i in {1..4}; do
    gcloud compute instances create "${BASE_NAME}-${index}" \
      --zone="$z" \
      --machine-type=e2-micro \
      --image-project=ubuntu-os-cloud \
      --image-family=ubuntu-minimal-2204-lts \
      --boot-disk-size=10GB \
      --boot-disk-type=pd-ssd \
      --quiet
    ((index++))
  done
done

# ====== BƯỚC 3: MAP ZONE ======
declare -A vm_zones
for i in {1..4}; do vm_zones["${BASE_NAME}-${i}"]="asia-northeast1-c"; done
for i in {5..8}; do vm_zones["${BASE_NAME}-${i}"]="asia-northeast2-c"; done

# ====== BƯỚC 4: CÀI FILE VÀ CẤU HÌNH SOCKS5 ======
for i in {1..8}; do
  name="${BASE_NAME}-${i}"
  zone="${vm_zones[$name]}"
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

echo ""
echo "✓ SOCKS5 proxy running on: socks5://\$EXT_IP:\$SOCKS5_PORT:\$SOCKS5_USER:\$SOCKS5_PASS"
rm -f \$0
EOF

  chmod +x install_socks5.sh
  echo "===> Cài SOCKS5 trên $name ($zone)"
  gcloud compute scp install_socks5.sh "$name":~/install_socks5.sh --zone="$zone" --quiet
  gcloud compute ssh "$name" --zone="$zone" --command="sudo bash ~/install_socks5.sh" < /dev/null
  rm -f install_socks5.sh
done

# ====== IN DANH SÁCH PROXY ======
echo ""
echo "================ SOCKS5 PROXY LIST ================"
for i in {1..8}; do
  ip=$(gcloud compute instances describe "${BASE_NAME}-${i}" \
    --zone="${vm_zones[${BASE_NAME}-${i}]}" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
  echo "${ip}:${PORTS[$((i-1))]}:${USERS[$((i-1))]}:${PASSES[$((i-1))]}"
done

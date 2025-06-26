#!/bin/bash
set -e

# ✅ Đảm bảo hostname có trong /etc/hosts
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "127.0.0.1 $HOSTNAME" | sudo tee -a /etc/hosts
fi

echo "📦 Đang cập nhật hệ thống..."
sudo apt update && sudo apt upgrade -y

# Cài Squid & Apache utils
echo "📦 Cài đặt Squid..."
sudo apt install -y squid apache2-utils curl wget ufw resolvconf dnsutils net-tools

# Tạo user proxy
echo "🔐 Tạo user proxy: mrmeo / pmbhgq844js78678bfjhfg"
htpasswd -b -c /etc/squid/passwd mrmeo pmbhgq844js78678bfjhfg

# Cấu hình Squid cơ bản
echo "🛠️ Ghi cấu hình Squid..."
cat > /etc/squid/squid.conf <<EOF
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
http_port 3128
EOF

# Đặt DNS public
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf

# Khởi động lại Squid
echo "🔁 Khởi động lại Squid..."
sudo systemctl restart squid
sudo systemctl enable squid

# Cấu hình firewall
echo "🔥 Cấu hình UFW và bảo mật..."
sudo ufw allow ssh
sudo ufw allow 3128/tcp
sudo ufw --force enable

# Chặn IPv6
echo "🧱 Chặn IPv6..."
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Chặn DNS leak nếu cần (có thể bỏ nếu không dùng DNS nội bộ)
sudo iptables -A OUTPUT -p udp --dport 53 ! -d 8.8.8.8 -j REJECT
sudo iptables -A OUTPUT -p tcp --dport 53 ! -d 8.8.8.8 -j REJECT

# Tắt ICMP
sudo iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

# Chặn WebRTC (multicast)
sudo iptables -A OUTPUT -d 224.0.0.0/4 -j DROP
sudo iptables -A OUTPUT -d 239.0.0.0/8 -j DROP

# Chặn IPv6 toàn bộ
sudo ip6tables -P INPUT DROP
sudo ip6tables -P FORWARD DROP
sudo ip6tables -P OUTPUT DROP

# Tăng ulimit
echo 'fs.file-max = 100000' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
echo '* soft nofile 100000' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 100000' | sudo tee -a /etc/security/limits.conf
sudo sed -i '/pam_limits.so/s/^# //' /etc/pam.d/common-session
sudo sed -i '/pam_limits.so/s/^# //' /etc/pam.d/common-session-noninteractive

echo ""
echo "✅ Hoàn tất cài đặt HTTP Proxy Squid!"
echo "────────────────────────────────────────────"
echo "📌 Proxy HTTP: 3128"
echo "👤 User: mrmeo / pmbhgq844js78678bfjhfg"
echo "🌐 DNS: 8.8.8.8"
echo "🧱 IPv6, DNS leak, ICMP, multicast đã được chặn"
echo "────────────────────────────────────────────"

echo "__SCRIPT_DONE__"

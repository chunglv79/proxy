#!/bin/bash
set -e
# ✅ Nhập thông tin từ người dùng
echo "🌐 Chọn DNS:"
echo "1) Google (8.8.8.8)"
echo "2) Cloudflare (1.1.1.1)"
read -p "👉 Nhập lựa chọn (1 hoặc 2): " DNS_CHOICE

case $DNS_CHOICE in
    1)
        DNS_SERVER="8.8.8.8"
        ;;
    2)
        DNS_SERVER="1.1.1.1"
        ;;
    *)
        echo "⚠️ Lựa chọn không hợp lệ. Mặc định dùng DNS Google."
        DNS_SERVER="8.8.8.8"
        ;;
esac
echo ""
read -p "🔢 Nhập port HTTP proxy muốn sử dụng (ví dụ: 3128): " PROXY_PORT
read -p "👤 Nhập username: " PROXY_USER
read -s -p "🔒 Nhập password: " PROXY_PASS




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
echo "🔐 Tạo user proxy:  $PROXY_USER / $PROXY_PASS"
htpasswd -b -c /etc/squid/passwd $PROXY_USER $PROXY_PASS

# Cấu hình Squid cơ bản
echo "🛠️ Ghi cấu hình Squid..."
cat > /etc/squid/squid.conf <<EOF
auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/passwd
auth_param basic realm Proxy
acl authenticated proxy_auth REQUIRED
http_access allow authenticated
http_access deny all
http_port $PROXY_PORT
EOF

# Đặt DNS public
echo "nameserver $DNS_SERVER" | sudo tee /etc/resolv.conf

# Khởi động lại Squid
echo "🔁 Khởi động lại Squid..."
sudo systemctl restart squid
sudo systemctl enable squid

# Cấu hình firewall
echo "🔥 Cấu hình UFW và bảo mật..."
sudo ufw allow ssh
sudo ufw allow $PROXY_PORT/tcp
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
echo "📌 Proxy HTTP: $PROXY_PORT"
echo "👤 User: $PROXY_USER / $PROXY_PASS"
echo "🌐 DNS: $DNS_SERVER"
echo "🧱 IPv6, DNS leak, ICMP, multicast đã được chặn"
echo "────────────────────────────────────────────"

echo "__SCRIPT_DONE__"

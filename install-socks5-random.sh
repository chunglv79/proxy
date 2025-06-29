#!/bin/bash
set -e

# 🌐 Đổi DNS tại đây: ví dụ
# - Nhật Bản: jp.tiar.app-doh
# - Hàn Quốc: kr.tiar.app-doh
# - Brazil: br.tiar.app-doh
echo "🌐 Chọn DNS:"
echo "1) Nhật Bản (jp.tiar.app-doh)"
echo "2) Hàn Quốc (kr.tiar.app-doh)"
read -p "👉 Nhập lựa chọn (1 hoặc 2): " DNS_CHOICE

case $DNS_CHOICE in
    1)
        DNSCRYPT_SERVER_NAME="jp.tiar.app-doh"
        ;;
    2)
        DNSCRYPT_SERVER_NAME="kr.tiar.app-doh"
        ;;
    *)
        echo "⚠️ Lựa chọn không hợp lệ. Mặc định dùng DNS Nhật Bản."
        DNSCRYPT_SERVER_NAME="jp.tiar.app-doh"
        ;;
esac

read -p "🔢 Nhập port SOCKS5 muốn sử dụng (ví dụ: 1080): " SOCKS5_PORT
read -p "👤 Nhập username: " PROXY_USER
read -s -p "🔒 Nhập password: " PROXY_PASS
echo ""
sudo apt remove --purge -y dante-server
sudo rm -f /etc/danted.conf
sudo rm -f /var/log/danted.log
sudo userdel mrmeo2025
# ✅ Đảm bảo hostname có trong /etc/hosts
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "127.0.0.1 $HOSTNAME" | sudo tee -a /etc/hosts
fi

echo "📦 Đang cập nhật hệ thống..."
sudo apt update && sudo apt upgrade -y

echo "📥 Cài UFW, dnscrypt-proxy và tiện ích cần thiết..."
sudo apt install -y curl wget ufw resolvconf dnsutils net-tools dnscrypt-proxy

echo "🧱 Chặn IPv6 để tránh rò rỉ..."
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "🔥 Bật UFW và mở port cần thiết..."
sudo ufw allow ssh
sudo ufw allow $SOCKS5_PORT/tcp       # SOCKS5
sudo ufw --force enable



apt update && apt install -y dante-server

cat > /etc/danted.conf <<EOF
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $SOCKS5_PORT
external: enX0
method: username
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: connect
    log: connect disconnect error
}
EOF

useradd -M -s /usr/sbin/nologin "$PROXY_USER"
echo "$PROXY_USER:$PROXY_PASS" | chpasswd

sudo touch /var/log/danted.log
sudo chmod 666 /var/log/danted.log
systemctl restart danted
systemctl enable danted

echo "🌐 Cấu hình dnscrypt-proxy sử dụng DNS $DNSCRYPT_SERVER_NAME trên cổng 5353..."
DNSCONF="/etc/dnscrypt-proxy/dnscrypt-proxy.toml"
sudo sed -i "s|^#\? *server_names *=.*|server_names = ['$DNSCRYPT_SERVER_NAME']|" "$DNSCONF"
sudo sed -i "s|^listen_addresses *=.*|listen_addresses = ['127.0.0.1:5353']|" "$DNSCONF"
sudo systemctl restart dnscrypt-proxy
sudo systemctl enable dnscrypt-proxy

echo "🔧 Cấu hình systemd-resolved để dùng DNS nội bộ (127.0.0.1)..."
sudo mkdir -p /etc/systemd/resolved.conf.d
echo -e "[Resolve]\nDNS=127.0.0.1\nDNSStubListener=no\nFallbackDNS=" | sudo tee /etc/systemd/resolved.conf.d/dnscrypt.conf

# Sửa lại /etc/resolv.conf đúng cách
sudo rm -f /etc/resolv.conf
sudo ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved

echo "🛡️ Chặn toàn bộ DNS leak không qua 127.0.0.1..."
sudo iptables -A OUTPUT -p udp --dport 53 ! -d 127.0.0.1 -j REJECT
sudo iptables -A OUTPUT -p tcp --dport 53 ! -d 127.0.0.1 -j REJECT

if command -v netfilter-persistent &> /dev/null; then
    sudo netfilter-persistent save
else
    echo "⚠️ netfilter-persistent chưa được cài — bỏ qua lưu iptables."
fi

echo "🧱 (Khuyến nghị) Tắt multicast & WebRTC leak..."
sudo iptables -A OUTPUT -d 224.0.0.0/4 -j DROP
sudo iptables -A OUTPUT -d 239.0.0.0/8 -j DROP

echo "🚫 Tắt ICMP (ẩn server khỏi ping)..."
sudo iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

echo "🔐 Bật chặn rò rỉ qua IPv6 và DNS..."
sudo ip6tables -P INPUT DROP
sudo ip6tables -P FORWARD DROP
sudo ip6tables -P OUTPUT DROP

echo "✅ Tăng ulimit cho kết nối lớn..."
echo 'fs.file-max = 100000' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
echo '* soft nofile 100000' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 100000' | sudo tee -a /etc/security/limits.conf
sudo sed -i '/pam_limits.so/s/^# //' /etc/pam.d/common-session
sudo sed -i '/pam_limits.so/s/^# //' /etc/pam.d/common-session-noninteractive

echo ""
echo "✅ Hoàn tất cài đặt."
echo "────────────────────────────────────────────"
echo "🔑 Truy cập: http://<VPS_IP>:12345/"
echo "📌 Port SOCKS5: $SOCKS5_PORT - User : $PROXY_USER - passwork : $PROXY_PASS"
echo "🌍 DNS sử dụng: $DNSCRYPT_SERVER_NAME (127.0.0.1:5353)"
echo "🧱 IPv6, DNS leak, ICMP, WebRTC đã bị chặn"
echo "────────────────────────────────────────────"

echo "🧪 Kiểm tra DNS từ cổng 5353..."
dig whoami.akamai.net @127.0.0.1 -p 5353 +short || echo "⚠️ DNS test failed!"

echo "🔥 Trạng thái tường lửa:"
sudo ufw status verbose
echo "__SCRIPT_DONE__"

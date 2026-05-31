#!/bin/bash
# 360V6 IPQ60XX 512M 全功能优化脚本
# 特性：无独立files目录 | 固定IP | 全局中文 | 性能优化 | WiFi AU满功率 | EasyTier
set -e

# ====================== 1. 修改默认管理IP + 主机名 ======================
sed -i 's/192.168.1.1/192.168.50.1/g' package/base-files/files/bin/config_generate
sed -i 's/OpenWrt/360V6-NSS/g' package/base-files/files/bin/config_generate

# ====================== 2. 拉取 EasyTier 插件 ======================
git clone --depth 1 https://github.com/EasyTier/luci-app-easytier.git package/luci-app-easytier 2>/dev/null || true

# ====================== 2.1 拉取网络向导插件 ======================
git clone --depth 1 https://github.com/sirpdboy/luci-app-netwizard.git package/luci-app-netwizard 2>/dev/null || true

# ====================== 3. 无线驱动参数优化 ======================
mkdir -p package/base-files/files/etc/modprobe.d
cat > package/base-files/files/etc/modprobe.d/ath11k.conf <<EOF
options ath11k irq_mode=0x1
options ath11k disable_160mhz=1
options ath11k reset_on_err=1
EOF

# ====================== 4. 系统全局性能调优 ======================
cat > package/base-files/files/etc/sysctl.conf <<EOF
vm.swappiness=5
vm.vfs_cache_pressure=30
vm.min_free_kbytes=8192

net.core.netdev_max_backlog=8192
net.core.somaxconn=4096
net.core.rmem_max=16777216
net.core.wmem_max=16777216

net.ipv4.tcp_syncookies=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=20
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_congestion_control=cubic

net.ipv4.ip_forward=1
net.ipv4.tcp_no_metrics_save=1
EOF

# ====================== 5. 基础默认配置：中文、时区、日志、DNS转发 ======================
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-base-setting <<EOF
#!/bin/sh
# 全局中文 + 时区
uci set luci.main.lang=zh-cn
uci commit luci
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'
uci set system.@system[0].log_size='32'
uci set system.@system[0].conloglevel='1'
uci set system.@system[0].cronloglevel='1'
uci commit system

# dnsmasq 缓存设置
uci set dhcp.@dnsmasq[0].cache-size='4096'
uci commit dhcp

# 关闭冗余日志服务
/etc/init.d/logd stop
/etc/init.d/logd disable
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-base-setting

# ====================== 6. WiFi 配置：名称2025 + 澳大利亚AU大功率 ======================
cat > package/base-files/files/etc/uci-defaults/99-wifi-setting <<EOF
#!/bin/sh
# 2.4G WiFi
uci set wireless.radio0.country='AU'
uci set wireless.radio0.txpower='23'
uci set wireless.radio0.htmode='HT40'
uci set wireless.default_radio0.ssid='2025'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key='12345678'
uci set wireless.default_radio0.disabled='0'

# 5G WiFi
uci set wireless.radio1.country='AU'
uci set wireless.radio1.txpower='25'
uci set wireless.radio1.htmode='VHT80'
uci set wireless.default_radio1.ssid='2025'
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.default_radio1.key='12345678'
uci set wireless.default_radio1.disabled='0'

uci commit wireless
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-wifi-setting

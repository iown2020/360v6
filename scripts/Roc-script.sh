#!/bin/bash
# 360V6 IPQ60XX 512M 全功能优化脚本
# 特性：无独立files目录 | 固定IP | 全局中文 | 性能优化 | NSS网络重载修复 | EasyTier
set -e

# ====================== 1. 修改默认管理IP + 主机名 ======================
sed -i 's/OpenWrt/360V6-NSS/g' package/base-files/files/bin/config_generate

# ====================== 2. 拉取 EasyTier 插件 ======================
git clone --depth 1 https://github.com/EasyTier/luci-app-easytier.git package/luci-app-easytier 2>/dev/null || true

# ====================== 2.1 拉取网络向导插件 ======================
git clone --depth 1 https://github.com/sirpdboy/luci-app-netwizard.git package/luci-app-netwizard 2>/dev/null || true

# ====================== 2.2 netwizard 完成后 NSS 恢复钩子 ======================
# 网络向导会一次性修改多个网络配置，可能导致 NSS 驱动无法正确恢复
# 在 netwizard 完成后自动重启 NSS 服务
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/95-netwizard-nss-fix <<'EOF'
#!/bin/sh
# 等待 netwizard 完成所有网络配置
sleep 5

# 重启 NSS 服务恢复接口绑定
if [ -x /etc/init.d/qca-nss-ecm ]; then
    /etc/init.d/qca-nss-ecm restart 2>/dev/null
fi
if [ -x /etc/init.d/qca-nss-drv-wifi ]; then
    /etc/init.d/qca-nss-drv-wifi restart 2>/dev/null
fi
if [ -x /etc/init.d/firewall ]; then
    /etc/init.d/firewall reload 2>/dev/null
fi

# 重启网络服务确保所有接口正常
/etc/init.d/network restart 2>/dev/null

rm -f /etc/uci-defaults/95-netwizard-nss-fix
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/95-netwizard-nss-fix

# ====================== 3. NSS 网络重载修复（解决修改LuCI设置后WAN/WAN6消失） ======================
# IPQ60XX + NSS 固件在 uci commit 触发 netifd 重载时，
# NSS ECM/DP 驱动可能无法正确恢复接口绑定，导致 WAN/WAN6 消失、下级设备断线。
# 通过创建 network reload 钩子，在网络重载完成后自动重启 NSS 相关服务来恢复。
mkdir -p package/base-files/files/etc/hotplug.d/iface
cat > package/base-files/files/etc/hotplug.d/iface/99-nss-reload <<'EOF'
#!/bin/sh
# 仅在网络配置重载完成时触发（ACTION=reload, INTERFACE=lan）
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "lan" ] && {
    # 等待 netifd 完成所有接口配置
    sleep 3
    # 重启 NSS ECM 以恢复 WAN 数据路径绑定
    if [ -x /etc/init.d/qca-nss-ecm ]; then
        /etc/init.d/qca-nss-ecm restart 2>/dev/null
    fi
    # 重启 NSS WiFi 卸载/重载以恢复无线数据路径
    if [ -x /etc/init.d/qca-nss-drv-wifi ]; then
        /etc/init.d/qca-nss-drv-wifi restart 2>/dev/null
    fi
    # 刷新防火墙规则
    if [ -x /etc/init.d/firewall ]; then
        /etc/init.d/firewall reload 2>/dev/null
    fi
}
EOF
chmod +x package/base-files/files/etc/hotplug.d/iface/99-nss-reload

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

# ====================== 5. 基础默认配置：中文、时区、日志 ======================
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-base-setting <<EOF
#!/bin/sh
# 修改默认管理 IP
uci set network.lan.ipaddr='192.168.50.1'
uci set network.lan.netmask='255.255.255.0'
uci commit network

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

# 防火墙：启用全锥型NAT（Full Cone NAT）
uci set firewall.@defaults[0].fullcone='1'
uci commit firewall

# 关闭冗余日志服务
/etc/init.d/logd stop
/etc/init.d/logd disable
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-base-setting

# ====================== 6. AdGuardHome 预配置 ======================
cat > package/base-files/files/etc/uci-defaults/99-adguardhome-setting <<'EOF'
#!/bin/sh
# 先启用 AdGuardHome 服务
uci set adguardhome.adguardhome.enabled='1'
uci set adguardhome.adguardhome.redirect='1'
uci set adguardhome.adguardhome.httpport='3000'
uci commit adguardhome

# 启动 AdGuardHome 服务（首次启动会生成默认配置）
/etc/init.d/adguardhome enable 2>/dev/null
/etc/init.d/adguardhome start 2>/dev/null

# 等待配置文件生成（最多等待30秒）
AGH_CONF=""
for i in $(seq 1 30); do
    AGH_CONF="$(uci -q get adguardhome.adguardhome.configdir)/AdGuardHome.yaml"
    [ -f "$AGH_CONF" ] && break
    sleep 1
done

# 如果配置文件存在则修改
if [ -f "$AGH_CONF" ]; then
    # 备份原始配置
    cp "$AGH_CONF" "${AGH_CONF}.bak"

    # 设置中文界面（先删除再添加，确保生效）
    sed -i '/^language:/d' "$AGH_CONF"
    sed -i '1i\language: zh-cn' "$AGH_CONF"
    
    # 设置上游 DNS（阿里 + 腾讯 + Cloudflare）
    sed -i '/^  upstream_dns:/,/^[^ ]/ {
        /^  upstream_dns:/!{
            /^  - /d
        }
    }' "$AGH_CONF"
    sed -i '/^  upstream_dns:/a\  - https://dns.alidns.com/dns-query\n  - https://doh.pub/dns-query\n  - https://1.1.1.1/dns-query' "$AGH_CONF"

    # 重启 AdGuardHome 使配置生效
    /etc/init.d/adguardhome restart 2>/dev/null
fi

rm -f /etc/uci-defaults/99-adguardhome-setting
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-adguardhome-setting

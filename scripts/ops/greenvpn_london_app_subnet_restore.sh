#!/usr/bin/env sh
set -eu

WG_IFACE="${GREENVPN_WG_IFACE:-wg0}"
APP_ADDR="${GREENVPN_APP_ADDR:-10.10.0.1/24}"
APP_NET="${GREENVPN_APP_NET:-10.10.0.0/24}"
WAN_IFACE="${GREENVPN_WAN_IFACE:-eth0}"

/sbin/ip link show "$WG_IFACE" >/dev/null

if ! /sbin/ip -4 addr show dev "$WG_IFACE" | grep -q " ${APP_ADDR%/*}/"; then
  /sbin/ip addr add "$APP_ADDR" dev "$WG_IFACE" 2>/dev/null || true
fi

/sbin/ip route replace "$APP_NET" dev "$WG_IFACE" src "${APP_ADDR%/*}"

/sbin/iptables -t nat -C POSTROUTING -s "$APP_NET" -o "$WAN_IFACE" -j MASQUERADE 2>/dev/null \
  || /sbin/iptables -t nat -A POSTROUTING -s "$APP_NET" -o "$WAN_IFACE" -j MASQUERADE

/sbin/iptables -C FORWARD -i "$WG_IFACE" -o "$WAN_IFACE" -j ACCEPT 2>/dev/null \
  || /sbin/iptables -A FORWARD -i "$WG_IFACE" -o "$WAN_IFACE" -j ACCEPT

/sbin/iptables -C FORWARD -i "$WAN_IFACE" -o "$WG_IFACE" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || /sbin/iptables -A FORWARD -i "$WAN_IFACE" -o "$WG_IFACE" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

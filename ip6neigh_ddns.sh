#!/bin/sh

# Auxiliary script for feeding public IPv6 addresses with dynamic prefix
# to update with OpenWrt DDNS Scripts. Usage example:
# ip6neigh_ddns.sh Server1.PUB.lan 

name="$1"
[ -n "$name" ] || exit 1

line=$(grep -m 1 " ${name}$" /tmp/hosts/ip6neigh 2>/dev/null)
[ "$?" = 0 ] || exit 2

echo "$line" | cut -d ' ' -f1
return 0

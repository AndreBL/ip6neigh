#!/bin/sh
. /lib/functions.sh

readonly LAN_DEV="br-lan"

readonly LL_LABEL=".LL"
readonly ULA_LABEL=""
readonly PUB_LABEL=".PUB"
readonly SLAAC_LABEL=".SLAAC"
readonly TMP_LABEL=".TMP"

readonly DOMAIN=$(uci get dhcp.@dnsmasq[0].domain)

add() {
	local name="$1"
	local addr="$2"
	echo "$addr $name" >> /tmp/hosts/ip6neigh
	killall -1 dnsmasq

	logger -t DEBUG "Added $addr $name"
}

remove() {
	local addr="$1"
	grep -q "^$addr " /tmp/hosts/ip6neigh || return 0

	grep -v "^$addr " /tmp/hosts/ip6neigh > /tmp/ip6neigh
	mv /tmp/ip6neigh /tmp/hosts/ip6neigh

	logger -t DEBUG "Removed $addr"
}

name_exists() {
	local match="$1"
	if [ -n "$2" ]; then
		match="${match}.$2.${DOMAIN}"
	fi
	grep ".*:.* ${match}$" /tmp/hosts/* | grep -q -v '^/tmp/hosts/ip6neigh:'
	return "$?"
}

is_slaac() {
	echo "$1" | grep -q -E ':[^:]{0,2}ff:fe[^:]{2}:[^:]{1,4}$'
	return "$?"	
}

process() {
	local addr="$1"
	local mac="$3"
	local status

	for status; do true; done
	[ "$status" != "STALE" ] || return 0

	case "$status" in
		"FAILED") remove $addr ;;

		"REACHABLE")
			grep -q "^$addr " /tmp/hosts/* && return 0

			local match=$(echo "$mac" | tr -d ':')
			local name=$(grep -E "^# ${LAN_DEV} .{16}${match} " /tmp/hosts/odhcpd | cut -d ' ' -f5)

			if [ -z "$name" ]; then
				name=$(grep $mac /tmp/dhcp.leases | cut -d " " -f4)
			fi
	
			[ -n "$name" ] || return 0
			local suffix=""

			if [ ${addr:0:4} = "fe80" ]; then
				suffix="${LL_LABEL}"
			elif [ ${addr:0:2} = "fd" ]; then
				suffix="${ULA_LABEL}"
				if is_slaac "$addr" ; then
					if name_exists "$name" "$suffix" ; then
						suffix="${SLAAC_LABEL}${suffix}"
					fi
				else
					suffix="${TMP_LABEL}${suffix}"
				fi
			else
				suffix="${PUB_LABEL}"
				if is_slaac "$addr" ; then
					if name_exists "$name" "$suffix" ; then
						suffix="${SLAAC_LABEL}${suffix}"
					fi
				else
					suffix="${TMP_LABEL}${suffix}"
				fi 
			fi

			name="${name}${suffix}.${DOMAIN}"

			add $name $addr
		;;
	esac
}

config_host() {
	local name
	local mac
	local slaac

	config_get name $1 name
	config_get mac $1 mac
	config_get slaac $1 slaac

	if [ -z "$name" ] || [ -z "$mac" ] || [ -z "$slaac" ]; then
		return 0
	fi

	local host

	if [ "$slaac" = "1" ]; then
		mac=$(echo "$mac" | tr -d ':')
		local host1="${mac:0:4}"
		local host2="${mac:4:2}ff:fe${mac:6:2}:${mac:8:4}"
		host1=$(printf %x $((0x${host1} ^ 0x0200)))
		host="${host1}:${host2}"
	elif [ "$slaac" != "0" ]; then
		host="$slaac"
	fi

	echo "fe80::${host} ${name}${LL_LABEL}.${DOMAIN}" >> /tmp/hosts/ip6neigh
	[ -n "$ula_prefix" ] && echo "${ula_prefix}:${host} ${name}${ULA_LABEL}.${DOMAIN}" >> /tmp/hosts/ip6neigh
	[ -n "$pub_prefix" ] && echo "${pub_prefix}:${host} ${name}${PUB_LABEL}.${DOMAIN}" >> /tmp/hosts/ip6neigh
}

ula_cidr=$(ip -6 addr show $LAN_DEV scope global 2>/dev/null | grep "inet6" | grep -v "dynamic" | awk '{print $2}')
pub_cidr=$(ip -6 addr show $LAN_DEV scope global dynamic 2>/dev/null | grep inet6 | awk '{print $2}')
ula_prefix=$(echo $ula_cidr | cut -d ":" -f1-4)
pub_prefix=$(echo $pub_cidr | cut -d ":" -f1-4)

echo "#Predefined SLAAC addresses" > /tmp/hosts/ip6neigh
config_load dhcp
config_foreach config_host host
echo -e "\n#Detected IPv6 neighbors" >> /tmp/hosts/ip6neigh

killall -1 dnsmasq

ip -6 monitor neigh dev br-lan |
	while IFS= read -r line
	do
		process $line
	done

#!/bin/sh

##################################################################################
#
#  Copyright (C) 2016 André Lange
#
#  See the file "LICENSE" for information on usage and redistribution
#  of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#  Distributed under GPLv2 License
#
##################################################################################


#	Script to automatically generate and update a hosts file giving local DNS
#	names to IPv6 addresses that IPv6 enabled devices took via SLAAC mechanism.
#
#	by André Lange		Dec 2016

. /lib/functions.sh

#LAN interface name
readonly LAN_DEV="br-lan"

#PRIMARY LABELS

#Label for link-local addresses
readonly LL_LABEL=".LL"

#Label for unique local addresses
readonly ULA_LABEL=""

#Label for globally unique addresses
readonly GUA_LABEL=".PUB"

#SECONDARY LABELS

#Label for addresses with EUI-64 interface identifier when the same name already exists in another hosts file
readonly EUI64_LABEL=".SLAAC"

#Label for temporary addresses and other addresses not known to have a predictable interface identifier
readonly TMP_LABEL=".TMP"


#DNS suffix to append
readonly DOMAIN=$(uci get dhcp.@dnsmasq[0].domain)

#Adds entry to hosts file
add() {
	local name="$1"
	local addr="$2"
	echo "$addr $name" >> /tmp/hosts/ip6neigh
	killall -1 dnsmasq

	logger -t DEBUG "Added $addr $name"
}

#Removes entry from hosts file
remove() {
	local addr="$1"
	grep -q "^$addr " /tmp/hosts/ip6neigh || return 0
	#Must save changes to another temp file and then move it over the main file.
	grep -v "^$addr " /tmp/hosts/ip6neigh > /tmp/ip6neigh
	mv /tmp/ip6neigh /tmp/hosts/ip6neigh

	logger -t DEBUG "Removed $addr"
}

#Returns 0 if the supplied name already exists in another hosts file
name_exists() {
	local match="$1"
	if [ -n "$2" ]; then
		match="${match}.$2.${DOMAIN}"
	fi
	grep ".*:.* ${match}$" /tmp/hosts/* | grep -q -v '^/tmp/hosts/ip6neigh:'
	return "$?"
}

#Returns 0 if the supplied IPv6 address has an EUI-64 interface identifier
is_eui64() {
	echo "$1" | grep -q -E ':[^:]{0,2}ff:fe[^:]{2}:[^:]{1,4}$'
	return "$?"	
}

#Process updates to neighbors table
process() {
	local addr="$1"
	local mac="$3"
	local status

	#Ignore STALE events
	for status; do true; done
	[ "$status" != "STALE" ] || return 0

	case "$status" in
		#Neighbor is unreachable. Remove it from hosts file.
		"FAILED") remove "$addr" ;;

		#Neighbor is reachable. Must be added to hosts file if it is not there yet.
		"REACHABLE")
			#Ignore if this IPv6 address already exists in any hosts file.
			grep -q "^$addr " /tmp/hosts/* && return 0

			#Look for a DHCPv6 lease with DUID-LL or DUID-LLT matching the neighbor's MAC address.
			local match
			local name
			match=$(echo "$mac" | tr -d ':')
			name=$(grep -m 1 -E "^# ${LAN_DEV} (00010001.{8}|00030001)${match} " /tmp/hosts/odhcpd | cut -d ' ' -f5)

			#If couldn't find a match in DHCPv6 leases then look into the DHCPv4 leases file.
			if [ -z "$name" ]; then
				name=$(grep -m 1 " $mac [^ ]{7,15} ([^*])" /tmp/dhcp.leases | cut -d ' ' -f4)
			fi

			#If it can't get a name for the address, do nothing.
			[ -n "$name" ] || return 0
			local suffix=""

			#Check address type
			if [ "${addr:0:4}" = "fe80" ]; then
				#Is link-local. Append corresponding label.
				suffix="${LL_LABEL}"
			elif [ "${addr:0:2}" = "fd" ]; then
				#Is ULA. Append corresponding label.
				suffix="${ULA_LABEL}"
				
				#Check if interface identifier is EUI-64.
				if is_eui64 "$addr" ; then
					#If it is and the same name already exists in another hosts file, append EUI-64 label.
					if name_exists "$name" "$suffix" ; then
						suffix="${EUI64_LABEL}${suffix}"
					fi
				else
					#Interface identifier is not EUI-64. Treat it as temporary address and append the corresponding label.
					suffix="${TMP_LABEL}${suffix}"
				fi
			else
				#The address is globally unique. Append corresponding label.
				suffix="${GUA_LABEL}"

				#Check if interface identifier is EUI-64.
				if is_eui64 "$addr" ; then
					#If it is and the same name already exists in another hosts file, append EUI-64 label.
					if name_exists "$name" "$suffix" ; then
						suffix="${EUI64_LABEL}${suffix}"
					fi
				else
					#Interface identifier is not EUI-64. Treat it as temporary address and append the corresponding label.
					suffix="${TMP_LABEL}${suffix}"
				fi 
			fi

			#Cat strings to get FQDN
			name="${name}${suffix}.${DOMAIN}"

			#Adds entry to hosts file
			add "$name" "$addr"
		;;
	esac
}

#Process entry in /etc/config/dhcp
config_host() {
	local name
	local mac
	local slaac

	config_get name "$1" name
	config_get mac "$1" mac
	config_get slaac "$1" slaac

	#Ignore entry if required options are absent.
	if [ -z "$name" ] || [ -z "$mac" ] || [ -z "$slaac" ]; then
		return 0
	fi

	local host

	#Check if slaac flag is set
	if [ "$slaac" = "1" ]; then
		#Generates EUI-64 interface identifier based on MAC entry
		mac=$(echo "$mac" | tr -d ':')
		local host1="${mac:0:4}"
		local host2="${mac:4:2}ff:fe${mac:6:2}:${mac:8:4}"
		host1=$(printf %x $((0x${host1} ^ 0x0200)))
		host="${host1}:${host2}"
	elif [ "$slaac" != "0" ]; then
		#slaac option carries a custom interface identifier. Just copy it.
		host="$slaac"
	fi

	#Creates hosts file entries with link-local, ULA and GUA prefixes with the same interface identifier.
	echo "fe80::${host} ${name}${LL_LABEL}.${DOMAIN}" >> /tmp/hosts/ip6neigh
	[ -n "$ula_prefix" ] && echo "${ula_prefix}:${host} ${name}${ULA_LABEL}.${DOMAIN}" >> /tmp/hosts/ip6neigh
	[ -n "$pub_prefix" ] && echo "${pub_prefix}:${host} ${name}${GUA_LABEL}.${DOMAIN}" >> /tmp/hosts/ip6neigh
}

#Finds ULA and global prefixes on LAN interface.
ula_cidr=$(ip -6 addr show $LAN_DEV scope global 2>/dev/null | grep "inet6" | grep -m 1 -v "dynamic" | awk '{print $2}')
pub_cidr=$(ip -6 addr show $LAN_DEV scope global dynamic 2>/dev/null | grep -m 1 inet6 | awk '{print $2}')
ula_prefix=$(echo "$ula_cidr" | cut -d ":" -f1-4)
pub_prefix=$(echo "$pub_cidr" | cut -d ":" -f1-4)

#Process /etc/config/dhcp an look for hosts with 'slaac' options set
echo "#Predefined SLAAC addresses" > /tmp/hosts/ip6neigh
config_load dhcp
config_foreach config_host host
echo -e "\n#Detected IPv6 neighbors" >> /tmp/hosts/ip6neigh

#Send signal to dnsmasq to reload hosts files.
killall -1 dnsmasq

#Infinite loop. Keeps monitoring changes in IPv6 neighbor's reachability status and call process() routine.
ip -6 monitor neigh dev $LAN_DEV |
	while IFS= read -r line
	do
		process $line
	done

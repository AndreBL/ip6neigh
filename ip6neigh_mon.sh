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

#Dependencies
. /lib/functions.sh
. /lib/functions/network.sh

#Loads UCI configuration file
reset_cb
config_load ip6neigh
config_get LAN_IFACE config interface lan
config_get LL_LABEL config ll_label LL
config_get ULA_label config ula_label
config_get gua_label config gua_label
config_get EUI64_LABEL config eui64_label SLAAC
config_get TMP_LABEL config tmp_label TMP
config_get PROBE_EUI64 config probe_eui64 1
config_get_bool PROBE_IID config probe_iid 1
config_get UNKNOWN config unknown "Unknown-"
config_get_bool LOAD_STATIC config load_static 1
config_get_bool LOG config log 0

#Gets the physical device
network_get_physdev LAN_DEV "$LAN_IFACE"

#DNS suffix to append
config_load dhcp
config_get DOMAIN dhcp domain lan

[ "$LOG" -gt 0 ] && logger -t ip6neigh "Starting ip6neigh script for physdev $LAN_DEV with domain $DOMAIN"

#Adds entry to hosts file
add() {
	local name="$1"
	local addr="$2"
	echo "$addr $name" >> /tmp/hosts/ip6neigh
	killall -1 dnsmasq

	[ "$LOG" -gt 0 ] && logger -t ip6neigh "Added: $name $addr"
	
	return 0
}

#Removes entry from hosts file
remove() {
	local addr="$1"
	grep -q "^$addr " /tmp/hosts/ip6neigh || return 0
	#Must save changes to another temp file and then move it over the main file.
	grep -v "^$addr " /tmp/hosts/ip6neigh > /tmp/ip6neigh
	mv /tmp/ip6neigh /tmp/hosts/ip6neigh

	[ "$LOG" -gt 0 ] && logger -t ip6neigh "Removed: $addr"
	return 0
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

#Generates EUI-64 interface identifier based on MAC address
gen_eui64() {
	local mac=$(echo "$2" | tr -d ':')
	local iid1="${mac:0:4}"
	local iid2="${mac:4:2}ff:fe${mac:6:2}:${mac:8:4}"

	#Flip U/L bit
	iid1=$(printf %x $((0x${iid1} ^ 0x0200)))
		
	eval "$1=${iid1}:${iid2}"
	return 0
}

#Probe addresses related to the supplied base address and MAC.
probe_addresses() {
	local baseaddr="$1"
	local mac="$2"
	local scope="$3"

	#Select addresses for probing
	local list=""

	#Check if is configured for probing addresses with the same IID
	local base_iid=""
	if [ "$PROBE_IID" -gt 0 ]; then
		#Gets the interface identifier from the base address
		base_iid=$(echo "$baseaddr" | grep -o -m 1 -E "[^:]{1,4}:[^:]{1,4}:[^:]{1,4}:[^:]{1,4}$")
		
		#Proceed if successful in getting the IID from the address
		if [ -n "$base_iid" ]; then
			#Probe same IID for different scopes than this one.
			if [ "$scope" != 0 ]; then list="${list}fe80::${base_iid} "; fi
			if [ "$scope" != 1 ] && [ -n "$ula_prefix" ]; then list="${list}${ula_prefix}:${base_iid} "; fi
			if [ "$scope" != 2 ] && [ -n "$gua_prefix" ]; then list="${list}${gua_prefix}:${base_iid} "; fi
		fi
	fi

	#Check if is configured for probing MAC-based addresses
	if [ "$PROBE_EUI64" -gt 0 ]; then
		#Generates EUI-64 interface identifier
		local eui64_iid
		gen_eui64 eui64_iid "$mac"

		#Only add to list if EUI-64 IID is different from the one that has been just added.
		if [ "$eui64_iid" != "$base_iid" ]; then
			if [ "$PROBE_EUI64" = "1" ] && [ "$scope" != 0 ]; then list="${list}fe80::${eui64_iid} "; fi
			if [ "$PROBE_EUI64" = "1" ] || [ "$scope" = 1 ]; then
				if [ -n "$ula_prefix" ]; then list="${list}${ula_prefix}:${eui64_iid} "; fi
			fi
			if [ "$PROBE_EUI64" = "1" ] || [ "$scope" = 2 ]; then
				if [ -n "$gua_prefix" ]; then list="${list}${gua_prefix}:${eui64_iid}"; fi
			fi
		fi
	fi
	
	#Exit if there is nothing to probe.
	[ -n "$list" ] || return 0
	
	[ "$LOG" -gt 0 ] && logger -t ip6neigh "Probing addresses: ${list}"
	
	#Ping each address once
	local addr
	IFS=' '
	for addr in $list; do
		if [ -n "$addr" ]; then
			#Skip addresses that already exist in some hosts file.
			if ! grep -q "^$addr " /tmp/hosts/* ; then
		 		ping6 -q -W 1 -c 1 -s 0 -I "$LAN_DEV" "$addr" >/dev/null 2>/dev/null
			fi
		fi
	done

	return 0
}

#Main routine: Process the changes in reachability status.
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
				name=$(grep -m 1 -E " $mac [^ ]{7,15} ([^*])" /tmp/dhcp.leases | cut -d ' ' -f4)

			fi

			#If it can't get a name for the address, create one based on MAC address.
			if [ -z "$name" ]; then
				[ "${UNKNOWN}" != 0 ] || return 0;
				local nic
				nic=$(echo "$match" | tail -c 7)
				name="${UNKNOWN}${nic}"
			fi

			#Check address type and assign proper labels.
			local suffix=""
			if [ "${addr:0:4}" = "fe80" ]; then
				#Is link-local. Append corresponding label.
				suffix="${LL_LABEL}"
				
				#Probe addresses related to this one.
				probe_addresses "$addr" "$mac" 0
			elif [ "${addr:0:2}" = "fd" ]; then
				#Is ULA. Append corresponding label.
				suffix="${ULA_LABEL}"
				
				#Check if interface identifier is EUI-64.
				if is_eui64 "$addr" ; then
					#If it is and the same name already exists in another hosts file, append EUI-64 label.
					if name_exists "$name" "$suffix" ; then
						suffix="${EUI64_LABEL}${suffix}"
						[ "$LOG" -gt 0 ] && logger -t ip6neigh "Name $name already exists in another hosts file with IPv6 address. Appending label: ${EUI64_LABEL}"
					fi
				else
					#Interface identifier is not EUI-64. #Adds temporary address label.
					suffix="${TMP_LABEL}${suffix}"
				fi

				#Probe addresses related to this one.
				probe_addresses "$addr" "$mac" 1
			else
				#The address is globally unique. Append corresponding label.
				suffix="${GUA_LABEL}"

				#Check if interface identifier is EUI-64.
				if is_eui64 "$addr" ; then
					#If it is and the same name already exists in another hosts file, append EUI-64 label.
					if name_exists "$name" "$suffix" ; then
						suffix="${EUI64_LABEL}${suffix}"
						[ "$LOG" -gt 0 ] && logger -t ip6neigh "Name $name already exists in another hosts file with IPv6 address. Appending label: ${EUI64_LABEL}"
					fi
				else
					#Interface identifier is not EUI-64. #Adds temporary address label.
					suffix="${TMP_LABEL}${suffix}"					
				fi 

				#Probe addresses related to this one.
				probe_addresses "$addr" "$mac" 2
			fi

			#Cat strings to get FQDN
			local fqdn="${name}${suffix}.${DOMAIN}"

			#Adds entry to hosts file
			add "$fqdn" "$addr"
		;;
	esac
	return 0
}

#Process entry in /etc/config/dhcp
config_host() {
	local name
	local mac
	local slaac

	config_get name "$1" name
	config_get mac "$1" mac
	config_get slaac "$1" slaac "0"

	#Ignore entry if required options are absent.
	if [ -z "$name" ] || [ -z "$mac" ] || [ -z "$slaac" ]; then
		return 0
	fi

	#Do nothing if slaac option is disabled
	[ "$slaac" != "0" ] || return 0
	
	#slaac option is enabled. Check if it contains a custom IID.
	local iid
	if [ "$slaac" != "1" ]; then
		#Use custom IID
		iid="$slaac"
	else
		#Generates EUI-64 interface identifier based on MAC
		gen_eui64 iid "$mac"
	fi

	#Load custom interface identifiers for each scope of address.
	#Uses EUI-64 when not specified.
	local ll_iid
	local ula_iid
	local gua_iid
	config_get ll_iid "$1" ll_iid "$iid"
	config_get ula_iid "$1" ula_iid "$iid"
	config_get gua_iid "$1" gua_iid "$iid"
	
	[ "$LOG" -gt 0 ] && logger -t ip6neigh "Generating predefined SLAAC addresses for $name"

	#Creates hosts file entries with link-local, ULA and GUA prefixes with corresponding IIDs.
	if [ "$ll_iid" != "0" ]; then
		echo "fe80::${ll_iid} ${name}${LL_LABEL}.${DOMAIN}" >> /tmp/hosts/ip6neigh
	fi
	if [ -n "$ula_prefix" ] && [ "$ula_iid" != "0" ]; then
		echo "${ula_prefix}:${ula_iid} ${name}${ULA_LABEL}.${DOMAIN}" >> /tmp/hosts/ip6neigh
	fi
	if [ -n "$gua_prefix" ] && [ "$gua_iid" != "0" ]; then
		echo "${gua_prefix}:${gua_iid} ${name}${GUA_LABEL}.${DOMAIN}" >> /tmp/hosts/ip6neigh
	fi
}

#Finds ULA and global addresses on LAN interface.
ula_cidr=$(ip -6 addr show "$LAN_DEV" scope global 2>/dev/null | grep "inet6 fd" | grep -m 1 -v "dynamic" | awk '{print $2}')
gua_cidr=$(ip -6 addr show "$LAN_DEV" scope global dynamic 2>/dev/null | grep -m 1 -E "inet6 ([^fd])" | awk '{print $2}')
ula_address=$(echo "$ula_cidr" | cut -d "/" -f1)
gua_address=$(echo "$gua_cidr" | cut -d "/" -f1)
ula_prefix=$(echo "$ula_address" | cut -d ":" -f1-4)
gua_prefix=$(echo "$gua_address" | cut -d ":" -f1-4)

#Decides if the GUAs should get a label based in config file and the presence of ULAs
if [ -n "$gua_label" ]; then
	#Use label specified in config file.
	GUA_LABEL="$gua_label"
	[ "$LOG" -gt 0 ] && logger -t ip6neigh "Using custom label for GUAs: ${GUA_LABEL}"
else
	#No label has been specified for GUAs. Check if the network setup has ULAs.
	if [ -n "$ula_prefix" ]; then
		#Yes. Use default label for GUAs.
		GUA_LABEL="PUB"
		[ "$LOG" -gt 0 ] && logger -t ip6neigh "Network has ULA prefix ${ula_prefix}::/64. Using default label for GUAs: ${GUA_LABEL}"
	else
		#No ULAs. So do not use label for GUAs.
		GUA_LABEL=""
		[ "$LOG" -gt 0 ] && logger -t ip6neigh "Network does not have ULA prefix. Clearing label for GUAs."
	fi
fi

#Adds a dot before each label
if [ -n "$LL_LABEL" ]; then LL_LABEL=".${LL_LABEL}" ; fi
if [ -n "$ULA_LABEL" ]; then ULA_LABEL=".${ULA_LABEL}" ; fi
if [ -n "$GUA_LABEL" ]; then GUA_LABEL=".${GUA_LABEL}" ; fi
if [ -n "$EUI64_LABEL" ]; then EUI64_LABEL=".${EUI64_LABEL}" ; fi
if [ -n "$TMP_LABEL" ]; then TMP_LABEL=".${TMP_LABEL}" ; fi

#Clears the output file
> /tmp/hosts/ip6neigh

#Process /etc/config/dhcp an look for hosts with 'slaac' options set
if [ "$LOAD_STATIC" -gt 0 ]; then
	echo "#Predefined SLAAC addresses" >> /tmp/hosts/ip6neigh
	config_load dhcp
	config_foreach config_host host
	echo -e >> /tmp/hosts/ip6neigh
fi
	
echo "#Discovered IPv6 neighbors" >> /tmp/hosts/ip6neigh

#Send signal to dnsmasq to reload hosts files.
killall -1 dnsmasq

#Flushes the neighbors cache and pings "all nodes" multicast address with various source addresses to speedup discovery.
ip -6 neigh flush dev "$LAN_DEV"

ping6 -q -W 1 -c 3 -s 0 -I "$LAN_DEV" ff02::1 >/dev/null 2>/dev/null
[ -n "$ula_address" ] && ping6 -q -W 1 -c 3 -s 0 -I "$ula_address" ff02::1 >/dev/null 2>/dev/null
[ -n "$gua_address" ] && ping6 -q -W 1 -c 3 -s 0 -I "$gua_address" ff02::1 >/dev/null 2>/dev/null

#Infinite loop. Keeps monitoring changes in IPv6 neighbor's reachability status and call process() routine.
ip -6 monitor neigh dev "$LAN_DEV" |
	while IFS= read -r line
	do
		process $line
	done

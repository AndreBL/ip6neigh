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

#Program definitions
readonly VERSION="1.3.1"
readonly CONFIG_FILE="/etc/config/ip6neigh"
readonly HOSTS_FILE="/tmp/hosts/ip6neigh"
readonly CACHE_FILE="/tmp/ip6neigh.cache"
readonly OUI_FILE="/usr/share/ip6neigh/oui.gz"
readonly TEMP_FILE="/tmp/ip6neigh.tmp"

#Check if the user is trying to run this script on its own
case "$1" in
	'-s'|'-n');;
	*)
		echo "ip6neigh Service Script v${VERSION}"
		echo -e
		echo "This script is intended to be run only by its init script."
		echo "If you want to start ip6neigh, type:"
		echo -e
		echo "ip6neigh start"
		echo -e
		
		exit 1
	;;
esac

#Writes error message and terminates the program.
errormsg() {
	local msg="Error: $1"
	>&2 echo "$msg"
	logger -t ip6neigh "$msg"
	exit 2
}

#Loads UCI configuration file
[ -f "$CONFIG_FILE" ] || errormsg "The UCI config file $CONFIG_FILE is missing. A template is avaliable at https://github.com/AndreBL/ip6neigh ."
[ -f "/etc/config/dhcp" ] || errormsg "The UCI config file /etc/config/dhcp is missing."
reset_cb
config_load ip6neigh
config_get LAN_IFACE config lan_iface lan
config_get WAN_IFACE config wan_iface wan6
config_get DOMAIN config domain
config_get ROUTER_NAME config router_name Router
config_get LL_LABEL config ll_label
config_get ULA_LABEL config ula_label
config_get WULA_LABEL config wula_label
config_get GUA_LABEL config gua_label
config_get TMP_LABEL config tmp_label
config_get URT_LABEL config unrouted_label
config_get_bool DHCPV6_NAMES config dhcpv6_names 1
config_get_bool DHCPV4_NAMES config dhcpv4_names 1
config_get_bool MANUF_NAMES config manuf_names 1
config_get PROBE_EUI64 config probe_eui64 1
config_get_bool PROBE_IID config probe_iid 1
config_get_bool LOAD_STATIC config load_static 1
config_get FLUSH config flush 1
config_get FW_SCRIPT config fw_script
config_get LOG config log 0

#Gets the physical devices
network_get_physdev LAN_DEV "$LAN_IFACE"
[ -n "$LAN_DEV" ] || errormsg "Could not get the name of the physical device for network interface ${LAN_IFACE}."
network_get_physdev WAN_DEV "$WAN_IFACE"

#Gets DNS domain from /etc/config/dhcp if not defined in ip6neigh config. Defaults to 'lan'.
if [ -z "$DOMAIN" ]; then
	DOMAIN=$(uci get dhcp.@dnsmasq[0].domain 2>/dev/null)
fi
if [ -z "$DOMAIN" ]; then DOMAIN="lan"; fi

#Adds entry to hosts file
add() {
	local name="$1"
	local addr="$2"
	echo "$addr $name" >> "$HOSTS_FILE"
	killall -1 dnsmasq

	logmsg "Added host: $name $addr"
	return 0
}

#Removes entry from hosts file
remove() {
	local addr="$1"
	grep -q "^$addr " "$HOSTS_FILE" || return 0
	#Must save changes to another temp file and then move it over the main file.
	grep -v "^$addr " "$HOSTS_FILE" > "$TEMP_FILE"
	mv "$TEMP_FILE" "$HOSTS_FILE"

	logmsg "Removed host: $addr"
	return 0
}

#Adds entry to cache file
add_cache() {
	local mac="$1"
	local name="$2"
	local type="$3"
	
	#Write the name to the cache file.
	logmsg "Creating type $type cache entry for $mac: ${name}"
	echo "${mac} ${type} ${name}" >> "$CACHE_FILE"

	return 0
}

#Removes entry from the cache file if it has a dynamic type.
remove_cache() {
	local name="$1"
	grep -q "0. ${name}$" "$CACHE_FILE" || return 0
	#Must save changes to another temp file and then move it over the main file.
	grep -v "0. ${name}$" "$CACHE_FILE" > "$TEMP_FILE"
	mv "$TEMP_FILE" "$CACHE_FILE"

	logmsg "Removed cached entry: $name"
	return 0
}

#Renames a previously added entry
rename() {
	local oldname="$1"
	local newname="$2"

	#Must save changes to another temp file and then move it over the main file.
	sed "s/ ${oldname}/ ${newname}/g" "$HOSTS_FILE" > "$TEMP_FILE"
	mv "$TEMP_FILE" "$HOSTS_FILE"
	
	#Deletes the old cached entry if dynamic.
	grep -v "0. ${oldname}$" "$CACHE_FILE" > "$TEMP_FILE"
	mv "$TEMP_FILE" "$CACHE_FILE"

	logmsg "Renamed host: $oldname to $newname"
	return 0
}

#Writes message to log
logmsg() {
	#Check if logging is disabled
	[ "$LOG" = "0" ] && return 0
	
	if [ "$LOG" = "1" ]; then
		#Log to syslog
		logger -t ip6neigh "$1"
	else
		#Log to file
		echo "$(date) $1" >> "$LOG"
	fi
	return 0
}

#Returns 0 if the supplied IPv6 address has an EUI-64 interface identifier.
is_eui64() {
	echo "$1" | grep -q -E ':[^:]{0,2}ff:fe[^:]{2}:[^:]{1,4}$'
	return "$?"	
}

#Returns 0 if the supplied non-LL IPv6 address has the same IID as the LL address for that same host.
is_other_static() {
	local addr="$1"
	
	#Gets the interface identifier from the address
	iid=$(echo "$addr" | grep -o -m 1 -E "[^:]{1,4}:[^:]{1,4}:[^:]{1,4}:[^:]{1,4}$")
	
	#Aborts with false if could not get IID.
	[ -n "$iid" ] || return 1
	
	#Builds match string
	local match
	if [ -n "$ll_label" ]; then
		match="^fe80::${iid} [^ ]*${ll_label}.${DOMAIN}$"
	else
		match="^fe80::${iid} [^ ]*$"
	fi

	#Looks for match and returns true if it finds one.
	grep -q "$match" "$HOSTS_FILE"
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

#Adds an address to the probe list
add_probe() {
	local addr="$1"
	
	#Do not add if the address already exist in some hosts file.
	grep -q "^$addr[ ,"$'\t'"]" /tmp/hosts/* && return 0
	
	#Adds to the list
	probe_list="${probe_list} ${addr}"
	
	return 0
}

#Probe addresses related to the supplied base address and MAC.
probe_addresses() {
	local name="$1"
	local baseaddr="$2"
	local mac="$3"
	local scope="$4"

	#Initializes probe list
	probe_list=""

	#Check if is configured for probing addresses with the same IID
	local base_iid=""
	if [ "$PROBE_IID" -gt 0 ]; then
		#Gets the interface identifier from the base address
		base_iid=$(echo "$baseaddr" | grep -o -m 1 -E "[^:]{1,4}:[^:]{1,4}:[^:]{1,4}:[^:]{1,4}$")
		
		#Proceed if successful in getting the IID from the address
		if [ -n "$base_iid" ]; then
			#Probe same IID for different scopes than this one.
			if [ "$scope" != 0 ]; then add_probe "fe80::${base_iid}"; fi
			if [ "$scope" != 1 ] && [ -n "$ula_prefix" ]; then add_probe "${ula_prefix}:${base_iid}"; fi
			if [ "$scope" != 2 ] && [ -n "$wula_prefix" ]; then add_probe "${wula_prefix}:${base_iid}"; fi
			if [ "$scope" != 3 ] && [ -n "$gua_prefix" ]; then add_probe "${gua_prefix}:${base_iid}"; fi
		fi
	fi

	#Check if is configured for probing MAC-based addresses
	if [ "$PROBE_EUI64" -gt 0 ]; then
		#Generates EUI-64 interface identifier
		local eui64_iid
		gen_eui64 eui64_iid "$mac"

		#Only add to list if EUI-64 IID is different from the one that has been just added.
		if [ "$eui64_iid" != "$base_iid" ]; then
			if [ "$PROBE_EUI64" = "1" ] && [ "$scope" != 0 ]; then add_probe "fe80::${eui64_iid}"; fi
			if [ "$PROBE_EUI64" = "1" ] || [ "$scope" = 1 ]; then
				if [ -n "$ula_prefix" ]; then add_probe "${ula_prefix}:${eui64_iid}"; fi
			fi
			if [ "$PROBE_EUI64" = "1" ] || [ "$scope" = 2 ]; then
				if [ -n "$wula_prefix" ]; then add_probe "${wula_prefix}:${eui64_iid}"; fi
			fi
			if [ "$PROBE_EUI64" = "1" ] || [ "$scope" = 3 ]; then
				if [ -n "$gua_prefix" ]; then add_probe "${gua_prefix}:${eui64_iid}"; fi
			fi
		fi
	fi
	
	#Exit if there is nothing to probe.
	[ -n "$probe_list" ] || return 0
	
	#Removes leading space from the list
	probe_list="${probe_list:1}"
	
	logmsg "Probing other possible addresses for ${name}: ${probe_list}"
	
	#Ping each address once.
	local addr
	IFS=' '
	for addr in $probe_list; do
		if [ -n "$addr" ]; then
		 	ping6 -q -W 1 -c 1 -s 0 -I "$LAN_DEV" "$addr" >/dev/null 2>/dev/null
		fi
	done
	
	#Clears the probe list.
	probe_list=""

	return 0
}

#Try to get a name from DHCPv6/v4 leases based on MAC.
dhcp_name() {
	local mac="$2"
	local match
	local dname=""

	#Look for a DHCPv6 lease with DUID-LL or DUID-LLT matching the neighbor's MAC address.
	if [ "$DHCPV6_NAMES" -gt 0 ]; then
		match=$(echo "$mac" | tr -d ':')
		dname=$(grep -m 1 -E "^# ${LAN_DEV} (00010001.{8}|00030001)${match} [^ ]* [^-]" /tmp/hosts/odhcpd | cut -d ' ' -f5)
		
		#Success getting name from DHCPv6.
		if [ -n "$dname" ]; then
			add_cache "$mac" "$dname" '06'
			eval "$1='$dname'"
			return 0
		fi
	fi

	#If couldn't find a match in DHCPv6 leases then look into the DHCPv4 leases file.
	if [ "$DHCPV4_NAMES" -gt 0 ]; then
		dname=$(grep -m 1 -E " $mac [^ ]{7,15} ([^*])" /tmp/dhcp.leases | cut -d ' ' -f4)
		
		#Success getting name from DHCPv4.
		if [ -n "$dname" ]; then
			add_cache "$mac" "$dname" '04'
			eval "$1='$dname'"
			return 0
		fi
	fi
	
	#Failed. Return error.
	return 1
}

#Searches for the OUI of the MAC in a manufacturer list.
oui_name() {
	#Fails if OUI file does not exist.
	[ -f "$OUI_FILE" ] || return 1
	
	#Get MAC and separates OUI part.
	local mac="$2"
	local oui="${mac:0:6}"
	
	#Check if the MAC is locally administered.
	if [ "$((0x${oui:0:2} & 0x02))" != 0 ]; then
		#Returns LocAdmin as name and success.
		eval "$1='LocAdmin'"
		return 0
	fi

	#Searches for the OUI in the database.
	local reg=$(gunzip -c "$OUI_FILE" | grep -m 1 "^$oui")
	local oname="${reg:6}"
	
	#Check if found.
	if [ -n "$oname" ]; then
		#Returns the manufacturer name and success code.
		eval "$1='$oname'"
		return 0
	fi

	#Manufacturer not found. Returns fail code.
	return 2
}

#Creates a name based on the manufacturer's name of the device.
manuf_name() {
	local mac="$2"
	local mname
	
	#Get info from the MAC.
	local upmac=$(echo "$mac" | tr -d ':' | awk '{print toupper($0)}')
	local nicid="${upmac:9}"

	#Tries to get a name based on the OUI part of the MAC. Otherwise use Unknown.
	local manuf="Unknown"
	oui_name manuf "$upmac"

	#Keeps trying to create unique name.
	mname="${manuf}-${nicid}"
	local count=0
	local code
	while grep -q " ${mname}$" "$CACHE_FILE" ; do
		#Prevents infinite loop.
		if [ "$code" -ge 10 ]; then
			logmsg "Too many name conflicts for ${mname}. Giving up."
			return 2
		fi
		
		#Generate new name.
		code=$(printf %x $count)
		code=$(echo "${mac}${code}" | tr -d ':' | md5sum)
		mname="${manuf}-${code:29:3}"
		true $(( code++ ))
		logmsg "Name conflict for ${mac}. Trying ${mname}"
	done
	
	#Writes entry to the cache with type 01.
	add_cache "$mac" "$mname" '01'
 	
	#Returns the newly created name.
	eval "$1='$mname'"
	return 0
}

#Creates a name for the host.
create_name() {
	local mac="$2"
	local acceptmanuf="$3"
	local cname
	
	#Look for a name in the cache file.
	local lease
	lease=$(grep -m 1 "^${mac} " "$CACHE_FILE")
	if [ "$?" = 0 ]; then
		#Get type.
		local type=$(echo "$lease" | cut -d ' ' -f2)
		
		#Check if the cached entry can be used in this call.
		if [ "$acceptmanuf" -gt 0 ] || [ "$type" != '01' ]; then
			#Get name and use it.
			cname=$(echo "$lease" | cut -d ' ' -f3)
			logmsg "Using cached name for ${mac}: ${cname}"
			eval "$1='$cname'"
			return 0
		fi
	fi

	#Try to get a name from DHCPv6/v4 leases.
	if dhcp_name cname "$mac"; then
		eval "$1='$cname'"
		return 0
	fi

	#Generates name from manufacturer if allowed in this call.
	if [ "$MANUF_NAMES" -gt 0 ] && [ "$acceptmanuf" -gt 0 ]; then
		#Get manufacturer name.
		if manuf_name cname "$mac"; then
			eval "$1='$cname'"
			return 0
		fi
	fi
	
	#Returns fail
	return 1
}

#Gets the current name for an IPv6 address
get_name() {
	local addr="$2"
	local matched
	
	#Check if the address already exists
	matched=$(grep -m 1 "^$addr[ ,"$'\t'"]" /tmp/hosts/*)
	
	#Address is new? (not found)
	[ "$?" != 0 ] && return 3
	
	#Check what kind of name it has
	local gname=$(echo "$matched" | tr $'\t' ' ' | cut -d ' ' -f2)
	local fname=$(echo "$gname" | cut -d '.' -f1)
	eval "$1='$fname'"
	
	#Manufacturer name?
	grep -q "01 ${fname}$" "$CACHE_FILE" && return 2

	#Temporary name?
	if [ -n "$tmp_label" ]; then
		echo "$gname" | grep -q "^[^\.]*${tmp_label}\."
		[ "$?" = 0 ] && return 1
	fi
	
	#Existent non-temporary name
	return 0
}

#Main routine: Process the changes in reachability status.
process() {
	local addr
	local mac="$3"
	local status
	
	#Get the address and translate delete events to FAILED.
	if [ "$1" = 'delete' ]; then
		addr="$2"
		status="FAILED"
	else 
		addr="$1"
		for status; do true; done
	fi

	#Ignore STALE events if not allowed to process them.
	[ "$status" != "STALE" ] || [ "$LOAD_STALE" -gt 0 ] || return 0

	#Get current host entry info.
	local name
	local currname
	local type
	get_name currname "$addr"
	type="$?"

	case "$status" in
		#Neighbor is unreachable. Must be removed if it is not a predefined host from /etc/config/dhcp.
		"FAILED")
			#If this is a predefined host, do nothing.
			[ "$type" = 0 ] && grep -q "[^0]. ${currname}$" "$CACHE_FILE" && return 0
			
			#Remove the host entry.
			remove "$addr"
					
			#Check if it was the last entry with that name.
			if ! grep -q -E " ${currname}(\.|$)" "$HOSTS_FILE" ; then
				#Remove from cache.
				remove_cache "${currname}"
			fi
		
			return 0
		;;
		
		#Neighbor is reachable os stale. Must be processed.
		"REACHABLE"|"STALE"|"PERMANENT")
			#Decide what to do based on type.
			case "$type" in
				#Address already has a stable name. Nothing to be done.
				0) return 0;;
				
				#Address named as temporary. Check if it is possible to classify it as non-temporary now.
				1)
					if is_other_static "$addr"; then
						#Removes the temporary address entry to be re-added as non-temp.
						logmsg "Address $addr was believed to be temporary but a LL address with same IID is now found. Replacing entry."
						remove "$addr"
						
						#Create name for address, allowing to generate unknown.
						if ! create_name name "$mac" 1; then
							#Nothing to be done if could not get a name.
							return 0
						fi
					else
						#Still temporary. Nothing to be done.
						return 0
					fi
				;;
				
				#Address is using manufacturer name.
				2)
					#Create name for address, not allowing to generate from manufacturer again.
					if create_name name "$mac" 0; then
						#Success creating name. Replaces the unknown name.
						logmsg "Unknown host $currname now has got a proper name. Replacing all entries."
						rename "$currname" "$name"
					fi

					return 0
				;;
				
				#Address is new.
				3)
					#Create name for address, allowing to generate from manufacturer.
					if ! create_name name "$mac" 1; then
						#Nothing to be done if could not get a name.
						return 0
					fi
				;;
			esac
			
			#Get the /64 prefix
			local prefix=$(echo "$addr" | cut -d ':' -f1-4)

			#Check address scope and assign proper labels.
			local suffix=""
			local scope
			if [ "${addr:0:4}" = "fe80" ]; then
				#Is link-local. Append corresponding label.
				suffix="${ll_label}"
				
				#Sets scope ID to LL
				scope=0
			elif [ "$prefix" = "$ula_prefix" ] || [ -z "$urt_label" -a "${addr:0:2}" = "fd" ] ; then
				#Is ULA. Append corresponding label.
				suffix="${ula_label}"
				
				#Sets scope ID to ULA
				scope=1
			elif [ "$prefix" = "$wula_prefix" ]; then
				#Is WAN side ULA. Append corresponding label.
				suffix="${wula_label}"
				
				#Sets scope ID to WULA
				scope=2
			elif [ "$prefix" = "$gua_prefix" ] || [ -z "$urt_label" ]; then
				#The address is globally unique. Append corresponding label.
				suffix="${gua_label}"

				#Sets scope ID to GUA
				scope=3
			else
				#The address uses a prefix that is not routed to this LAN.
				suffix="$urt_label"
				
				#Sets scope ID to unrouted.
				scope=4
			fi
			
			#Check if it could be a temporary address
			if [ "$scope" -ge 1 ] && [ "$scope" -le 3 ]; then
				#Check if interface identifier is static
				if ! is_eui64 "$addr" && ! is_other_static "$addr"; then
					#Interface identifier does not appear to be static. Adds temporary address label.
					suffix="${tmp_label}${suffix}"
				fi
			fi

			#Cat strings to generate output name
			local hostsname
			if [ -n "$suffix" ]; then
				#Names with labels get FQDN
				hostsname="${name}${suffix}.${DOMAIN}"
			else
				#Names without labels 
				hostsname="${name}"
			fi
			
			#Adds entry to hosts file
			add "$hostsname" "$addr"
			
			#Checks if this host must have nud perm for all addresses.
			if grep -q "30 ${name}$" "$CACHE_FILE"; then
				ip -6 neigh replace "$addr" lladdr "$mac" dev "$LAN_DEV" nud perm
				logmsg "Changed NUD state to permanent for ${hostsname}."
			fi
			
			#Probe other addresses related to this one if not unrouted and the global switch is enabled.
			if [ "$AUTO_PROBE" = 1 ] && [ "$scope" != 4 ]; then
				probe_addresses "$name" "$addr" "$mac" "$scope"
			fi
		;;
	esac
	
	return 0
}

#Adds static entry to hosts file
add_static() {
	local name="$1"
	local addr="$2"
	local scope="$3"
	local mac="$4"
	local perm="$5"
	local suffix=""

	#Decides which suffix should be added to the name.
	case "$scope" in
		#Link-local
		0) if [ -n "${ll_label}" ]; then suffix="${ll_label}.${DOMAIN}"; fi;;

		#ULA
		1) if [ -n "${ula_label}" ]; then suffix="${ula_label}.${DOMAIN}"; fi;;
		
		#WULA
		2) if [ -n "${wula_label}" ]; then suffix="${wula_label}.${DOMAIN}"; fi;;
		
		#GUA
		3) if [ -n "${gua_label}" ]; then suffix="${gua_label}.${DOMAIN}"; fi;;
	esac
	
	#Writes the entry to the file
	echo "${addr} ${name}${suffix}" >> "$HOSTS_FILE"
	
	#Adds a permanent entry in the neighbors table if requested to do so.
	[ "$perm" -gt 0 ] && ip -6 neigh replace "$addr" lladdr "$mac" dev "$LAN_DEV" nud perm
	
	return 0
}

#Process entry in /etc/config/dhcp
config_host() {
	#Load basic options
	local name
	local mac
	config_get name "$1" name
	config_get mac "$1" mac
	
	#Ignore entry if the minimum required options are missing.
	if [ -z "$name" ] || [ -z "$mac" ]; then
		return 0;
	fi
	
	#Load more options
	local ip
	local duid
	local slaac
	local perm
	config_get ip "$1" ip
	config_get duid "$1" duid
	config_get slaac "$1" slaac "0"
	config_get perm "$1" perm 0
	
	#Converts user typed MAC to lowercase
	mac=$(echo "$mac" | awk '{print tolower($0)}')
	
	#Populate cache with name, depending on supplied options.
	if [ "$LOAD_STATIC" -gt 0 ] && [ "$slaac" != "0" ]; then
		#Decides the first digit of type value.
		local type
		case "$perm" in
			0) type='1';;
			1) type='2';;
			2) type='3';;
		esac
		add_cache "$mac" "$name" "${type}0"
	elif [ "$DHCPV6_NAMES" -gt 0 ] && [ -n "$duid" ]; then
		add_cache "$mac" "$name" '16'
	elif [ "$DHCPV4_NAMES" -gt 0 ]; then
		add_cache "$mac" "$name" '14'
	fi

	#Nothing else to be done if not configured for loading static leases
	#or slaac option is not enabled for this host.
	[ "$LOAD_STATIC" -gt 0 ] || return 0
	if [ -z "$slaac" ] || [ "$slaac" = "0" ]; then
		return 0
	fi
	
	#Checks if requested to permanent entries to neighbors table
	if [ "$perm" -gt 0 ]; then
		#Adds permanent entry to IPv4 neighbors table if and IPv4 address was specified.
		[ -n "$ip" ] && ip -4 neigh replace "$ip" lladdr "$mac" dev "$LAN_DEV" nud perm
		logmsg "Generating predefined SLAAC addresses with NUD state permanent for $name"
	else
		logmsg "Generating predefined SLAAC addresses for $name"
	fi

	#slaac option is enabled. Check if it contains a custom IID.
	local iid=""
	if [ "$slaac" != "1" ]; then
		#Use custom IID
		iid=$(echo "$slaac" | awk '{print tolower($0)}')
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
	config_get wula_iid "$1" wula_iid "$iid"
	config_get gua_iid "$1" gua_iid "$iid"

	#Creates hosts file entries with link-local, ULA and GUA prefixes with corresponding IIDs.
	local addr
	if [ -n "$ll_iid" ] && [ "$ll_iid" != "0" ]; then
		add_static "$name" "fe80::${ll_iid}" 0 "$mac" "$perm"
	fi
	if [ -n "$ula_prefix" ] && [ -n "$ula_iid" ] && [ "$ula_iid" != "0" ]; then
		add_static "$name" "${ula_prefix}:${ula_iid}" 1 "$mac" "$perm"
	fi
	if [ -n "$wula_prefix" ] && [ -n "$wula_iid" ] && [ "$wula_iid" != "0" ]; then
		add_static "$name" "${wula_prefix}:${wula_iid}" 2 "$mac" "$perm"
	fi
	if [ -n "$gua_prefix" ] && [ -n "$gua_iid" ] && [ "$gua_iid" != "0" ]; then
		add_static "$name" "${gua_prefix}:${gua_iid}" 3 "$mac" "$perm"
	fi
}

#Sync with the current neighbors table.
load_neigh() {
	#Iterate through entries in the neighbors table.
	#Select only reachable, stale and permanent neighbors.
	ip -6 neigh show dev "$LAN_DEV" |
		grep -E 'REACHABLE$|[0-9,a-f] STALE$|PERMANENT$' | sort -r |
		while IFS= read -r line
		do
			process $line
		done
}

#Trap service stop
#terminate() {
#	logmsg "Terminating ip6neigh"
#	exit 0
#}
#trap terminate HUP INT TERM

#Main service routine
main_service() {
	#Clears the log file if one is set
	if [ "$LOG" != "0" ] && [ "$LOG" != "1" ]; then
		> "$LOG"
	fi

	#Startup message
	logmsg "Starting ip6neigh main service v${VERSION} for physdev $LAN_DEV with domain $DOMAIN"

	#Gets the IPv6 addresses from the LAN device.
	ll_cidr=$(ip -6 addr show "$LAN_DEV" scope link 2>/dev/null | grep -m 1 'inet6' | awk '{print $2}')
	ula_cidr=$(ip -6 addr show "$LAN_DEV" scope global 2>/dev/null | grep 'inet6 fd' | grep -m 1 -v 'dynamic' | awk '{print $2}')
	wula_cidr=$(ip -6 addr show "$LAN_DEV" scope global noprefixroute dynamic 2>/dev/null | grep 'inet6 fd' | awk '{print $2}')
	gua_cidr=$(ip -6 addr show "$LAN_DEV" scope global noprefixroute 2>/dev/null | grep -m 1 'inet6 [^fd]' | awk '{print $2}')
	ll_address=$(echo "$ll_cidr" | cut -d "/" -f1)
	ula_address=$(echo "$ula_cidr" | cut -d "/" -f1)
	wula_address=$(echo "$wula_cidr" | cut -d "/" -f1)
	gua_address=$(echo "$gua_cidr" | cut -d "/" -f1)

	#Gets the network prefixes assuming /64 subnets.
	ula_prefix=$(echo "$ula_address" | cut -d ':' -f1-4)
	wula_prefix=$(echo "$wula_address" | cut -d ':' -f1-4)
	gua_prefix=$(echo "$gua_address" | cut -d ':' -f1-4)


	#Choose default the labels based on the available prefixes
	if [ -n "$ula_prefix" ]; then
		#ULA prefix is available. No label for ULA. WAN side ULA becomes 'ULA'
		wula_label="ULA"
		gua_label="PUB"
	elif [ -n "$wula_prefix" ]; then
		#No ULA prefix. WULA is available. No label for ULA and WULA. Default for PUB.
		gua_label="PUB"
	fi

	#Prefix-independent default labels
	ll_label="LL"
	tmp_label="TMP"
	urt_label="UNROUTED"

	#Override the default labels based with user supplied options.
	if [ -n "$LL_LABEL" ]; then
		if [ "$LL_LABEL" = '0' ]; then ll_label=""
		else ll_label="$LL_LABEL"; fi
	fi
	if [ -n "$ULA_LABEL" ]; then
		if [ "$ULA_LABEL" = '0' ]; then ula_label=""
		else ula_label="$ULA_LABEL"; fi
	fi
	if [ -n "$WULA_LABEL" ]; then
		if [ "$WULA_LABEL" = '0' ]; then wula_label=""
		else wula_label="$WULA_LABEL"; fi
	fi
	if [ -n "$GUA_LABEL" ]; then
		if [ "$GUA_LABEL" = '0' ]; then gua_label=""
		else gua_label="$GUA_LABEL"; fi
	fi
	if [ -n "$TMP_LABEL" ]; then
		if [ "$TMP_LABEL" = '0' ]; then tmp_label=""
		else tmp_label="$TMP_LABEL"; fi
	fi
	if [ -n "$URT_LABEL" ]; then
		if [ "$URT_LABEL" = '0' ]; then urt_label=""
		else urt_label="$URT_LABEL"; fi
	fi

	#Adds a dot before each label
	if [ -n "$ll_label" ]; then ll_label=".${ll_label}" ; fi
	if [ -n "$ula_label" ]; then ula_label=".${ula_label}" ; fi
	if [ -n "$wula_label" ]; then wula_label=".${wula_label}" ; fi
	if [ -n "$gua_label" ]; then gua_label=".${gua_label}" ; fi
	if [ -n "$tmp_label" ]; then tmp_label=".${tmp_label}" ; fi
	if [ -n "$urt_label" ]; then urt_label=".${urt_label}" ; fi
		
	#Clears the cache file
	> "$CACHE_FILE"

	#Clears the output hosts file
	> "$HOSTS_FILE"

	#Flushes the neighbors table
	if [ "$FLUSH" -gt 0 ]; then
		#Decode flags
		FLUSH_PERM=0; FLUSH_REACH=0; FLUSH_STALE=0
		[ "$(($FLUSH & 1))" -gt 0 ] && FLUSH_PERM=1
		[ "$(($FLUSH & 2))" -gt 0 ] && FLUSH_STALE=1
		[ "$(($FLUSH & 4))" -gt 0 ] && FLUSH_REACH=1
		logmsg "Flushing the neighbors table. Flags: PERM=$FLUSH_PERM STALE=$FLUSH_STALE REACH=$FLUSH_REACH"
		
		#Flushes the corresponding neighbors
		[ "$FLUSH_PERM" = 1 ] && ip -6 neigh flush dev "$LAN_DEV" nud perm
		[ "$FLUSH_STALE" = 1 ] && ip -6 neigh flush dev "$LAN_DEV" nud stale
		[ "$FLUSH_REACH" = 1 ] && ip -6 neigh flush dev "$LAN_DEV" nud reach
	fi

	#Header for static hosts
	echo "#Predefined SLAAC addresses" >> "$HOSTS_FILE"

	#Adds the router names
	if [ -n "$ROUTER_NAME" ] && [ "$ROUTER_NAME" != "0" ]; then
		logmsg "Generating names for the router's addresses"
		[ -n "$ll_address" ] && add_static "$ROUTER_NAME" "$ll_address" 0
		[ -n "$ula_address" ] && add_static "$ROUTER_NAME" "$ula_address" 1
		[ -n "$wula_address" ] && add_static "$ROUTER_NAME" "$wula_address" 2
		[ -n "$gua_address" ] && add_static "$ROUTER_NAME" "$gua_address" 3
	fi

	#Process /etc/config/dhcp and adds static hosts.
	config_load dhcp
	config_foreach config_host host
	echo -e >> "$HOSTS_FILE"

	#Header for dynamic hosts
	echo "#Discovered IPv6 neighbors" >> "$HOSTS_FILE"

	#Send signal to dnsmasq to reload hosts files.
	killall -1 dnsmasq

	#Pings "all nodes" multicast address with source addresses from various scopes to speedup discovery.
	ping6 -q -W 1 -c 3 -s 0 -I "$LAN_DEV" ff02::1 >/dev/null 2>/dev/null
	[ -n "$ula_address" ] && ping6 -q -W 1 -c 3 -s 0 -I "$ula_address" ff02::1 >/dev/null 2>/dev/null
	[ -n "$wula_address" ] && ping6 -q -W 1 -c 3 -s 0 -I "$wula_address" ff02::1 >/dev/null 2>/dev/null
	[ -n "$gua_address" ] && ping6 -q -W 1 -c 3 -s 0 -I "$gua_address" ff02::1 >/dev/null 2>/dev/null

	#Get current IPv6 neighbors and call process() routine.
	#Run first round with auto-probe global switch enabled.
	logmsg "Syncing the hosts file with the neighbors table... Round #1"
	LOAD_STALE=1
	AUTO_PROBE=1
	load_neigh

	#If some auto-probe is enable, run one more round for detecting the new neighbors after ping6.
	if [ "$PROBE_EUI64" -gt 0 ] || [ "$PROBE_IID" -gt 0 ]; then
		logmsg "Syncing the hosts file with the neighbors table... Round #2"
		#This time it doesn't have to probe addresses again.
		AUTO_PROBE=0
		load_neigh
	fi
		
	#Check if there are custom scripts to be runned.
	if [ -n "$FW_SCRIPT" ]; then
		for script in $FW_SCRIPT; do
			if [ -f "$script" ]; then
				logmsg "Running user firewall script: $script"
				DOMAIN="$DOMAIN" LAN_DEV="$LAN_DEV" WAN_DEV="$WAN_DEV" \
					ULA_ADDR="$ula_address" ULA_PREFIX="$ula_prefix" \
					GUA_ADDR="$gua_address" GUA_PREFIX="$gua_prefix" \
					/bin/sh "$script"
			fi
		done
	fi
	 
	#Infinite main loop. Keeps monitoring changes in IPv6 neighbor's reachability status and call process() routine.
	logmsg "Monitoring changes in the neighbor's table..."
	LOAD_STALE=0
	AUTO_PROBE=1
	local line
	ip -6 monitor neigh dev "$LAN_DEV" |
		while IFS= read -r line
		do
			process $line
		done
	
	logmsg "Terminating the main service"
	return 0
}

#DAD NS packet snooping service
snooping_service() {
	#Check if tcpdump is installed
	if ! which tcpdump >/dev/null; then
		errormsg "DAD snooping is not available because tcpdump is not installed on this system."
	fi

	#Startup message
	logmsg "Starting ip6neigh snooping service v${VERSION} for physdev $LAN_DEV"

	local line
	local addr
	
	#Infinite loop. Keeps listening to DAD NS packets and pings the captured addresses.
	tcpdump -q -l -n -p -i "$LAN_DEV" 'src :: && ip6[40] == 135' 2>/dev/null |
		while IFS= read -r line
		do
			#Get the address from the line
			addr=$(echo $line | awk '{print substr($11,1,length($11)-1);}')
			
			#Ignore blank address
			[ -n "$addr" ] || continue
			
			#Check if the address already exists in any hosts file
			if grep -q "^$addr[ ,"$'\t'"]" /tmp/hosts/* ; then continue; fi
				
			#Ping the address to trigger a NS message from the router
			sleep 1
			logmsg "Probing $addr after snooping a DAD NS packet from it"
			ping6 -q -W 1 -c 1 -s 0 -I "$LAN_DEV" "$addr" >/dev/null 2>/dev/null
		done
	
	logmsg "Terminating the snooping service"
	return 0
}

#Check which service should run
case "$1" in
	'-s') main_service;;
	'-n') snooping_service;;
esac

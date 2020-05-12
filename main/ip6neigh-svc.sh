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

#Program definitions
readonly SVC_VERSION='2.0.0'
readonly CONFIG_FILE='/etc/config/ip6neigh'
readonly OUI_FILE='/usr/share/ip6neigh/oui.gz'

LEASE_FILE=`uci get dhcp.@dnsmasq[0].leasefile`
LAN_IFACE=''
VERSION=0
SNOOP=0
ECHO=0

#Parse command line arguments
for i in "$@" ; do
	case $i in
		--interface=*)
			LAN_IFACE="${i#*=}"
			shift
			;;
		--snoop)
			SNOOP=1
			shift
			;;
		--echo)
			ECHO=1
			shift
			;;
		--version)
			VERSION=1
			shift
			;;
		*)
	                echo "ip6neigh Service Script v${SVC_VERSION}"
	                echo -e
	                echo "This script is intended to be run only by its init script."
	                echo "If you want to start ip6neigh, type:"
	                echo -e
        	        echo "ip6neigh start"
	                echo -e
	                exit 1
			;;
	esac
done

#Print version info if requested
if [ "$VERSION" -eq '1' ] ; then
	echo "ip6neigh Service Script v${SVC_VERSION}."
	exit 0
fi

#Check if interface exists
if [ -z "$LAN_IFACE" ] ; then
	echo "Please specify a lan interface." >&2
	exit 1
fi

uci get network.$LAN_IFACE >/dev/null

if [ "$?" -ne "0" ] ; then
	echo "Invalid lan interface specified." >&2
	exit 1
fi

#Setup environment
readonly HOSTS_FILE="/tmp/hosts/ip6neigh.$LAN_IFACE"
readonly CACHE_FILE="/tmp/ip6neigh.$LAN_IFACE.cache"
readonly TEMP_FILE="/tmp/ip6neigh.$LAN_IFACE.tmp"
readonly LEASE_FILE=`uci get dhcp.@dnsmasq[0].leasefile`

if [ -z "$LEASE_FILE" ] ; then
	LEASE_FILE='/tmp/dhcp.leases'
fi

#Load dependencies
. /lib/functions.sh
. /lib/functions/network.sh
. /usr/lib/ip6neigh/ip6addr_functions.sh

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
config_get WAN_IFACE config wan_iface wan6
config_get DOMAIN config domain
config_get ROUTER_NAME config router_name Router
config_get LLA_LABEL config lla_label
config_get ULA_LABEL config ula_label
config_get WULA_LABEL config wula_label
config_get GUA_LABEL config gua_label
config_get TMP_LABEL config tmp_label
config_get MAN_LABEL config man_label
config_get URT_LABEL config unrouted_label
config_get_bool DHCPV6_NAMES config dhcpv6_names 1
config_get_bool DHCPV4_NAMES config dhcpv4_names 1
config_get_bool MANUF_NAMES config manuf_names 1
config_get PROBE_EUI64 config probe_eui64 1
config_get_bool PROBE_IID config probe_iid 1
config_get_bool LOAD_STATIC config load_static 1
config_get_bool PROBE_HOST config probe_host 1
config_get FLUSH config flush 1
config_get FW_SCRIPT config fw_script
config_get LOG config log 0
config_get SETUP_RADVD config setup_radvd 0

#Gets the physical devices
network_get_physdev LAN_DEV "$LAN_IFACE"
[ -n "$LAN_DEV" ] || errormsg "Could not get the name of the physical device for network interface ${LAN_IFACE}."
network_get_physdev WAN_DEV "$WAN_IFACE"

#Gets DNS domain from /etc/config/dhcp if not defined in ip6neigh config. Defaults to 'lan'.
if [ -z "$DOMAIN" ]; then
	DOMAIN=$(uci get dhcp.@dnsmasq[0].domain 2>/dev/null)
fi
if [ -z "$DOMAIN" ]; then DOMAIN="lan"; fi

#Asks dnsmasq to reload the hosts file if the pending flag is set
reload_hosts() {
	#Check the pending flag
	[ "$reload_pending" = 1 ] || return 0
	
	local now
	local diff
	
	#Current time
	now=$(date +%s)

	#Difference from the last reload time in seconds
	diff=$(($now - $reload_time))
	
	#Reloads if the difference is more than 5 seconds with reload pending
	if [ "$diff" -ge 5 ]; then
		reload_time="$now"
		reload_pending=0
		killall -1 dnsmasq
	fi
	
	return 0
}

#Adds entry to hosts file
add() {
	local name="$1"
	local addr="$2"
	echo "$addr $name" >> "$HOSTS_FILE"

	logmsg "Added host: $name $addr"
	reload_pending=1
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
	reload_pending=1
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
	reload_pending=1
	return 0
}

#Removes the TMP label from addresses that are now found to be non-temporary
remove_tmp_label() {
	local addr="$1"
	local name="$name"
	
	#Gets the interface identifier from the address
	local iid=$(addr_iid64 "$addr")
	
	#IID match string
	local im=$(gen_iid_match "$iid")
	
	#Get the list of addresses with the same IID from the same host
	local match="^${im} ${name}\\${tmp_label}(\.|$)"
	local list
	list=$(grep -E "$match" "$HOSTS_FILE")
	
	#Return if nothing was found
	[ "$?" = 0 ] || return 0
	
	#Create temp file without the matched lines
	grep -v -E "$match" "$HOSTS_FILE" > "$TEMP_FILE"

	#Remove the label from the matched lines and append to the temp file
	echo "$list" |
		sed -e "s/${tmp_label}.${DOMAIN}//g" \
			-e "s/${tmp_label}//g" \
		>> "$TEMP_FILE"
	
	#Move the temp file over the main file
	mv "$TEMP_FILE" "$HOSTS_FILE"

	logmsg "Removed the ${tmp_label} label from the addresses with IID ${iid} from ${name}"
	reload_pending=1
	return 0
}

#Writes message to log
logmsg() {
	#Check if logging is disabled
	[ "$LOG" = "0" ] && return 0
	
	if [ "$LOG" = "1" ]; then
		#Log to syslog
		logger -t ip6neigh "[$LAN_DEV] $1"
	else
		#Log to file
		echo "$(date) [$LAN_DEV] $1" >> "$LOG"
	fi
	
	#If -e argument was present, echo to stdout.
	[ "$ECHO" = 1 ] && echo "$1"
	
	return 0
}

#Tries to guess if the supplied IPv6 address is non-temporary.
is_other_static() {
	local addr="$1"
	
	#Gets the interface identifier from the address
	local iid=$(addr_iid64 "$addr")
	
	#Looks for a link-local address with the same IID and returns true if it finds one.
	local lladdr=$(compress_addr "fe80:0:0:0:${iid}")
	grep -q "^$lladdr " "$HOSTS_FILE" && return 0
	
	#Otherwise returns false
	return 1
}

#Adds an address to the probe list
add_probe() {
	#Compress the address
	local addr=$(compress_addr "$1")
	
	#Do not add if the address already exist in some hosts file and unique flag was set on call.
	[ "$2" -gt 0 ] && grep -q "^$addr[ ,"$'\t'"]" /tmp/hosts/* && return 0
	
	#Adds to the list
	probe_list="${probe_list} ${addr}"
	
	return 0
}

#Probe addresses that are related to the supplied base address and MAC.
probe_addresses() {
	local name="$1"
	local baseaddr="$2"
	local mac="$3"
	local scope="$4"

	#Initializes probe list
	probe_list=""
	
	#Check if is configured for probing all the addresses from the same host
	if [ "$PROBE_HOST" -gt 0 ]; then
		#Get the address list for this host.
		local hlist
		local haddr
		hlist=$(grep -E " ${name}(\.|$)" "$HOSTS_FILE" | cut -d ' ' -f1)
		local OIFS="$IFS"
		unset IFS
		for haddr in $hlist; do
			[ "$haddr" != "$addr" ] && add_probe "$haddr" 0
		done
		IFS="$OIFS"
	fi
	
	#Check if is configured for probing addresses with the same IID
	local base_iid=""
	if [ "$PROBE_IID" -gt 0 ]; then
		#Gets the interface identifier from the base address
		base_iid=$(addr_iid64 "$baseaddr")

		#Probe same IID for different scopes than this one.
		if [ "$scope" != 0 ]; then add_probe "fe80:0:0:0:${base_iid}" 1; fi
		if [ "$scope" != 1 ] && [ -n "$ula_prefix" ]; then add_probe "${ula_prefix}:${base_iid}" 1; fi
		if [ "$scope" != 2 ] && [ -n "$wula_prefix" ]; then add_probe "${wula_prefix}:${base_iid}" 1; fi
		if [ "$scope" != 3 ] && [ -n "$gua_prefix" ]; then add_probe "${gua_prefix}:${base_iid}" 1; fi
	fi

	#Check if is configured for probing MAC-based addresses
	if [ "$PROBE_EUI64" -gt 0 ]; then
		#Generates EUI-64 interface identifier
		local eui64_iid=$(gen_eui64 "$mac")
		#Only add to list if EUI-64 IID is different from the one that has been just added.
		if [ "$eui64_iid" != "$base_iid" ]; then
			if [ "$PROBE_EUI64" = "1" ] && [ "$scope" != 0 ]; then add_probe "fe80:0:0:0:${eui64_iid}" 1; fi
			if [ "$PROBE_EUI64" = "1" ] || [ "$scope" = 1 ]; then
				if [ -n "$ula_prefix" ]; then add_probe "${ula_prefix}:${eui64_iid}" 1; fi
			fi
			if [ "$PROBE_EUI64" = "1" ] || [ "$scope" = 2 ]; then
				if [ -n "$wula_prefix" ]; then add_probe "${wula_prefix}:${eui64_iid}" 1; fi
			fi
			if [ "$PROBE_EUI64" = "1" ] || [ "$scope" = 3 ]; then
				if [ -n "$gua_prefix" ]; then add_probe "${gua_prefix}:${eui64_iid}" 1; fi
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
	local OIFS="$IFS"
	unset IFS
	for addr in $probe_list; do
		if [ -n "$addr" ]; then
		 	ping6 -q -W 1 -c 1 -s 0 -I "$LAN_DEV" "$addr" >/dev/null 2>/dev/null
		fi
	done
	IFS="$OIFS"
	
	#Clears the probe list.
	probe_list=""

	return 0
}

#Try to get a name from DHCPv6/v4 leases based on MAC.
dhcp_name() {
	local mac="$1"
	local match
	local name

	#Look for a DHCPv6 lease with DUID-LL or DUID-LLT matching the neighbor's MAC address.
	if [ "$DHCPV6_NAMES" -gt 0 ]; then
		match=$(echo "$mac" | tr -d ':')
		name=$(grep -m 1 -E "^# ${LAN_DEV} (00010001.{8}|00030001)${match} [^ ]* [^-]" /tmp/hosts/odhcpd | cut -d ' ' -f5)
		
		#Success getting name from DHCPv6.
		if [ -n "$name" ]; then
			add_cache "$mac" "$name" '06'
			echo "$name"
			return 0
		fi
	fi

	#If couldn't find a match in DHCPv6 leases then look into the DHCPv4 leases file.
	if [ "$DHCPV4_NAMES" -gt 0 ]; then
		name=$(grep -m 1 -E " $mac [^ ]{7,15} ([^*])" $LEASE_FILE | cut -d ' ' -f4)
		
		#Success getting name from DHCPv4.
		if [ -n "$name" ]; then
			add_cache "$mac" "$name" '04'
			echo "$name"
			return 0
		fi
	fi
	
	#Failed. Return error.
	return 1
}

#Returns 0 if the supplied IPv6 address appears to be generated by odhcpd.
#1: ip6addr
is_dhcpv6_addr() {
	#Check if the IID looks like something the DHCPv6 server would create.
	local iid32=$(addr_iid64 "$1" | cut -d ':' -f1-2)
	case "${iid32}:" in
		"$ula_man_hint":*) return 0;;
		"$wula_man_hint":*) return 0;;
		"$gua_man_hint":*) return 0;;
	esac
	
	return 1
}

#Searches for the OUI of the MAC in a manufacturer list.
oui_name() {
	#Get MAC and separates OUI part.
	local mac="$1"
	local oui="${mac:0:6}"
	
	#Check if the MAC is locally administered.
	if [ "$((0x${oui:0:2} & 0x02))" != 0 ]; then
		#Returns LocalAdmin as name and success.
		echo 'LocalAdmin'
		return 0
	fi
	
	#Fails here if OUI file does not exist.
	[ -f "$OUI_FILE" ] || return 1

	#Searches for the OUI in the database.
	local reg=$(gunzip -c "$OUI_FILE" | grep -m 1 "^$oui")
	local name="${reg:6}"
	
	#Check if found.
	if [ -n "$name" ]; then
		#Returns the manufacturer name and success code.
		echo "$name"
		return 0
	fi

	#Manufacturer not found. Returns fail code.
	return 2
}

#Creates a name based on the manufacturer's name of the device.
manuf_name() {
	local mac="$1"
	local name
	
	#Get info from the MAC.
	local upmac=$(echo "$mac" | tr -d ':' | awk '{print toupper($0)}')
	local nicid="${upmac:9}"

	#Tries to get a name based on the OUI part of the MAC. Otherwise use Unknown.
	local manuf
	manuf=$(oui_name "$upmac")
	[ "$?" = 0 ] || manuf="Unknown"

	#Keeps trying to create unique name.
	name="${manuf}-${nicid}"
	local count=0
	local code
	while grep -q " ${name}$" "$CACHE_FILE" ; do
		#Prevents infinite loop.
		if [ "$code" -ge 10 ]; then
			logmsg "Too many name conflicts for ${name}. Giving up."
			return 2
		fi
		
		#Generate new name.
		code=$(printf %x $count)
		code=$(echo "${mac}${code}" | tr -d ':' | md5sum)
		name="${manuf}-${code:29:3}"
		true $(( code++ ))
		logmsg "Name conflict for ${mac}. Trying ${name}"
	done
	
	#Writes entry to the cache with type 01.
	add_cache "$mac" "$name" '01'
 	
	#Returns the newly created name.
	echo "$name"
	return 0
}

#Creates a name for the host.
create_name() {
	local mac="$1"
	local acceptmanuf="$2"
	local name
	
	#Look for a name in the cache file.
	local lease
	lease=$(grep -m 1 "^${mac} " "$CACHE_FILE")
	if [ "$?" = 0 ]; then
		#Get type.
		local type=$(echo "$lease" | cut -d ' ' -f2)
		
		#Check if the cached entry can be used in this call.
		if [ "$acceptmanuf" -gt 0 ] || [ "$type" != '01' ]; then
			#Get name and use it.
			echo "$lease" | cut -d ' ' -f3
			return 0
		fi
	fi

	#Try to get a name from DHCPv6/v4 leases.
	name=$(dhcp_name "$mac")
	if [ "$?" = 0 ]; then
		echo "$name"
		return 0
	fi

	#Generates name from manufacturer if allowed in this call.
	if [ "$MANUF_NAMES" -gt 0 ] && [ "$acceptmanuf" -gt 0 ]; then
		#Get manufacturer name.
		name=$(manuf_name "$mac")
		if [ "$?" = 0 ]; then
			echo "$name"
			return 0
		fi
	fi
	
	#Returns fail
	return 1
}

#Gets the current name for an IPv6 address
get_name() {
	local addr="$1"
	local matched
	
	#Check if the address already exists
	matched=$(grep -m 1 "^$addr[ ,"$'\t'"]" /tmp/hosts/*)
	
	#Address is new? (not found)
	[ "$?" != 0 ] && return 2
	
	#Check what kind of name it has
	local fqdn=$(echo "$matched" | tr $'\t' ' ' | cut -d ' ' -f2)
	local name=$(echo "$fqdn" | cut -d '.' -f1)
	
	#Outputs the name
	echo "$name"
	
	#Manufacturer name?
	grep -q "01 ${name}$" "$CACHE_FILE" && return 1

	#Stable name
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
	currname=$(get_name "$addr")
	type="$?"

	case "$status" in
		#Neighbor is unreachable. Must be removed if it is not a predefined host from /etc/config/dhcp.
		"FAILED")
			#Get the line number that divides the two sections of the hosts file
			local ln=$(grep -n '^#Discovered' "$HOSTS_FILE" | cut -d ':' -f1)
			
			#If this is not an address from the "discovered" section, do nothing.
			awk "NR>${ln}"' {printf "%s\n",$1}' "$HOSTS_FILE" |
				grep -q "^${addr}$"
			[ "$?" = 0 ] || return 0
			
			#Remove the address.
			remove "$addr"
					
			#Check if it was the last entry with that name.
			if ! grep -q -E " ${currname}(\.|$)" "$HOSTS_FILE" ; then
				#Remove from cache.
				remove_cache "${currname}"
			fi
		
			return 0
		;;
		
		#Neighbor is reachable or stale. Must be processed.
		"REACHABLE"|"STALE"|"PERMANENT")
			#Decide what to do based on type.
			case "$type" in
				#Address already has a stable name. Nothing to be done.
				0) return 0;;
				
				#Address is using manufacturer name.
				1)
					#Create name for address, not allowing to generate from manufacturer again.
					name=$(create_name "$mac" 0)
					if [ "$?" = 0 ]; then
						#Success creating name. Replaces the unknown name.
						logmsg "Unknown host $currname now has got a proper name. Replacing all entries."
						rename "$currname" "$name"
					fi

					return 0
				;;
				
				#Address is new.
				2)
					#Create name for address, allowing to generate from manufacturer.
					name=$(create_name "$mac" 1)
					if [ "$?" != 0 ]; then
						#Nothing to be done if could not get a name.
						return 0
					fi
				;;
			esac
			
			#Get the /64 prefix
			local prefix=$(addr_prefix64 "$addr")
	
			#Check address scope and assign proper labels.
			local suffix=""
			local scope
			if [ "$prefix" = 'fe80:0:0:0' ]; then
				#Is link-local. Append corresponding label.
				suffix="${lla_label}"
				
				#Sets scope ID to LLA
				scope=0
				
				#Remove the TMP label from the addresses from the same host that have the same IID
				[ -n "$tmp_label" ] && remove_tmp_label "$addr" "$name"
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
			
			#Check if it needs some secondary label
			if [ "$scope" -ge 1 ] && [ "$scope" -le 3 ]; then
				#Managed address ?
				if is_dhcpv6_addr "$addr"; then
					#Appears to be a managed address. Adds the MAN label.
					suffix="${man_label}${suffix}"
				elif ! addr_is_eui64 "$addr" && ! is_other_static "$addr"; then
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
	local prefix="$2"
	local iid="$3"
	local scope="$4"
	local mac="$5"
	local perm="$6"
	local suffix=""
	
	#Builds the address if needed.
	local addr
	if [ -n "$iid" ]; then
		addr=$(join_prefix64_iid64 "$prefix" "$iid")
	else
		addr="$2"
	fi

	#Decides which suffix should be added to the name.
	case "$scope" in
		#Link-local
		0) if [ -n "${lla_label}" ]; then suffix="${lla_label}.${DOMAIN}"; fi;;

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
	config_get iface "$1" iface
	
	#Ignore entry if the minimum required options are missing.
	if [ -z "$name" ] || [ -z "$mac" ] || [ -z "$iface" ] ; then
		logmsg "Host entry will be ignored because either the name, the mac or the iface option is missing."
		return 0;
	fi

	#Ignore entry if host is not reachable via monitored interface.
	if [ "$iface" != "$LAN_IFACE" ] ; then
		logmsg "Host entry $name will be ignored because it is connected to interface $iface."
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
		iid=$(gen_eui64 "$mac")
	fi

	#Load custom interface identifiers for each scope of address.
	#Uses EUI-64 when not specified.
	local lla_iid
	local ula_iid
	local gua_iid
	config_get lla_iid "$1" lla_iid "$iid"
	config_get ula_iid "$1" ula_iid "$iid"
	config_get wula_iid "$1" wula_iid "$iid"
	config_get gua_iid "$1" gua_iid "$iid"

	#Creates hosts file entries with link-local, ULA and GUA prefixes with corresponding IIDs.
	local addr
	if [ -n "$lla_iid" ] && [ "$lla_iid" != "0" ]; then
		add_static "$name" "fe80:0:0:0" "${lla_iid}" 0 "$mac" "$perm"
	fi
	if [ -n "$ula_prefix" ] && [ -n "$ula_iid" ] && [ "$ula_iid" != "0" ]; then
		add_static "$name" "${ula_prefix}" "${ula_iid}" 1 "$mac" "$perm"
	fi
	if [ -n "$wula_prefix" ] && [ -n "$wula_iid" ] && [ "$wula_iid" != "0" ]; then
		add_static "$name" "${wula_prefix}" "${wula_iid}" 2 "$mac" "$perm"
	fi
	if [ -n "$gua_prefix" ] && [ -n "$gua_iid" ] && [ "$gua_iid" != "0" ]; then
		add_static "$name" "${gua_prefix}" "${gua_iid}" 3 "$mac" "$perm"
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
	#Startup message
	logmsg "Starting ip6neigh main service v${SVC_VERSION} for physdev $LAN_DEV with domain $DOMAIN"
	
	#Var initialization
	reload_time=0
	reload_pending=1

	#Gets the IPv6 addresses from the LAN device.
	lla_cidr=$(ip -6 addr show "$LAN_DEV" scope link 2>/dev/null | grep -m 1 'inet6' | awk '{print $2}')
	ula_cidr=$(ip -6 addr show "$LAN_DEV" scope global 2>/dev/null | grep 'inet6 fd' | grep -m 1 -E -v 'dynamic|/128' | awk '{print $2}')
	wula_cidr=$(ip -6 addr show "$LAN_DEV" scope global dynamic 2>/dev/null | grep 'inet6 fd' | awk '{print $2}')
	gua_cidr=$(ip -6 addr show "$LAN_DEV" scope global 2>/dev/null | grep -m 1 'inet6 [^fd]' | awk '{print $2}')
	lla_address=$(echo "$lla_cidr" | cut -d "/" -f1)
	ula_address=$(echo "$ula_cidr" | cut -d "/" -f1)
	wula_address=$(echo "$wula_cidr" | cut -d "/" -f1)
	gua_address=$(echo "$gua_cidr" | cut -d "/" -f1)

	#Gets the network prefixes assuming /64 subnets.
	ula_prefix=$(addr_prefix64 "$ula_address")
	wula_prefix=$(addr_prefix64 "$wula_address")
	gua_prefix=$(addr_prefix64 "$gua_address")
	
	#Separate the first 32-bit from the IID of the router's addresses do match against managed addresses.
	ula_man_hint=$(addr_iid64 "$ula_address" | cut -d ':' -f1-2)
	wula_man_hint=$(addr_iid64 "$wula_address" | cut -d ':' -f1-2)
	gua_man_hint=$(addr_iid64 "$gua_address" | cut -d ':' -f1-2)

	#Choose default the labels based on the available prefixes
	if [ -n "$ula_prefix" ]; then
		#ULA prefix is available. No label for ULA. WAN side ULA becomes 'ULA'
		wula_label='ULA'
		gua_label='GUA'
	elif [ -n "$wula_prefix" ]; then
		#No ULA prefix. WULA is available. No label for ULA and WULA. GUA use default.
		gua_label='GUA'
	fi

	#Prefix-independent default labels
	lla_label='LL'
	tmp_label='TMP'
	man_label='MAN'
	urt_label='UNROUTED'

	#Override the default labels based with user supplied options.
	if [ -n "$LLA_LABEL" ]; then
		if [ "$LLA_LABEL" = '0' ]; then lla_label=""
		else lla_label="$LLA_LABEL"; fi
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
	if [ -n "$MAN_LABEL" ]; then
		if [ "$MAN_LABEL" = '0' ]; then man_label=""
		else man_label="$MAN_LABEL"; fi
	fi
	if [ -n "$URT_LABEL" ]; then
		if [ "$URT_LABEL" = '0' ]; then urt_label=""
		else urt_label="$URT_LABEL"; fi
	fi

	#Adds a dot before each label
	if [ -n "$lla_label" ]; then lla_label=".${lla_label}" ; fi
	if [ -n "$ula_label" ]; then ula_label=".${ula_label}" ; fi
	if [ -n "$wula_label" ]; then wula_label=".${wula_label}" ; fi
	if [ -n "$gua_label" ]; then gua_label=".${gua_label}" ; fi
	if [ -n "$tmp_label" ]; then tmp_label=".${tmp_label}" ; fi
	if [ -n "$man_label" ]; then man_label=".${man_label}" ; fi
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
		[ -n "$lla_address" ] && add_static "$ROUTER_NAME" "$lla_address" "" 0
		[ -n "$ula_address" ] && add_static "$ROUTER_NAME" "$ula_address" "" 1
		[ -n "$wula_address" ] && add_static "$ROUTER_NAME" "$wula_address" "" 2
		[ -n "$gua_address" ] && add_static "$ROUTER_NAME" "$gua_address" "" 3
	fi

	#Process /etc/config/dhcp and adds static hosts.
	config_load dhcp
	config_foreach config_host host
	echo -e >> "$HOSTS_FILE"

	#Header for dynamic hosts
	echo "#Discovered IPv6 neighbors" >> "$HOSTS_FILE"

	#Send signal to dnsmasq to reload hosts files.
	reload_hosts
	

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
	
	#Check if allowed to setup radvd
	if [ "$SETUP_RADVD" -gt 0 ] && [ -n "$gua_prefix" ] && which radvd >/dev/null; then
		#Store the current prefix in the temp file
		local new_prefix="${gua_prefix}::/64"
		echo "$new_prefix" > "/tmp/etc/prefix.${LAN_DEV}"
				
		#Persistent file for storing the old prefix
		local file='/etc/deprecate.prefix'

		#Read the old prefix from the persistent file
		local old_prefix=$(cat "$file" 2>/dev/null)

		#Store the new prefix to be the next old one
		echo "$new_prefix" > "$file"

		#Check if the prefix has changed
		if [ -n "$old_prefix" ] && [ "$old_prefix" != "$new_prefix" ]; then
			#Go on and configure the old prefix for deprecation
			uci set radvd.deprecate.prefix="$old_prefix"
			uci set radvd.deprecate.ignore=0
			uci commit radvd
		else
			#Disable the deprecate config if no old prefix
			uci set radvd.deprecate.ignore=1
			uci commit radvd
		fi
		
		#Restart radvd
		/etc/init.d/radvd enabled && /etc/init.d/radvd restart
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
			reload_hosts
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
	logmsg "Starting ip6neigh snooping service v${SVC_VERSION} for physdev $LAN_DEV"

	local line
	local addr
	
	#If the LAN iface is bridged, disable IGMP snooping on the bridge.
	local mcsnoop="/sys/class/net/${LAN_DEV}/bridge/multicast_snooping"
	[ -f "$mcsnoop" ] && echo 0 > "$mcsnoop"
	
	#Enables the 'allmulticast' flag on the interface
	ip link set "$LAN_DEV" allmulticast on
	
	#Infinite loop. Keeps listening to DAD NS packets and pings the captured addresses.
	tcpdump -q -l -n -p -i "$LAN_DEV" 'src :: && icmp6 && ip6[40] == 135' 2>/dev/null |
		while IFS= read -r line
		do
			#Get the address from the line
			addr=$(echo $line | awk '{print substr($11,1,length($11)-1);}')
			
			#Ignore blank address
			[ -n "$addr" ] || continue
			
			#Check if the address already exists in any hosts file
			if [ "$PROBE_HOST" != 1 ] && grep -q "^$addr[ ,"$'\t'"]" /tmp/hosts/* ; then
				continue
			fi
				
			#Ping the address to trigger a NS message from the router
			sleep 1
			logmsg "Probing $addr after snooping a DAD NS packet from it"
			ping6 -q -W 1 -c 1 -s 0 -I "$LAN_DEV" "$addr" >/dev/null 2>/dev/null
		done
	
	logmsg "Terminating the snooping service"
	return 0
}

#Check which service should run
[ "$SNOOP" -eq '1' ] && snooping_service || main_service


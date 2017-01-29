#!/bin/sh

##################################################################################
#
#  Copyright (C) 2016 André Lange & Craig Miller
#
#  See the file "LICENSE" for information on usage and redistribution
#  of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#  Distributed under GPLv2 License
#
##################################################################################


#	Script to command and display information gathered by ip6neigh.
#	Script is called by luci-app-command for a web interface, or can be run directly.
#
#	by André Lange & Craig Miller	Jan 2017

#Dependencies
. /lib/functions.sh
. /lib/functions/network.sh

#Program definitions
readonly VERSION="1.4.0"
readonly HOSTS_FILE="/tmp/hosts/ip6neigh"
readonly CACHE_FILE="/tmp/ip6neigh.cache"
readonly SERVICE_NAME="ip6neigh-svc.sh"
readonly SHARE_DIR="/usr/share/ip6neigh/"
readonly OUI_FILE="${SHARE_DIR}oui.gz"

#Display help text
display_help() {
	echo "ip6neigh Command Line Script v${VERSION}"
	echo -e
	echo -e "Usage: $CMD COMMAND ..."
	echo -e
	echo -e "Available commands:"
	echo -e "\t{ start | restart | stop }"
	echo -e "\t{ enable | disable }"
	echo -e "\tlist\t[ all | static | discovered | active | host HOSTNAME ]"
	echo -e "\tname\t{ ADDRESS }"
	echo -e "\taddress\t{ FQDN } [ 1 ]"
	echo -e "\tmac\t{ HOSTNAME | ADDRESS }"
	echo -e "\toui\t{ MAC | download }"
	echo -e "\tresolve\t{ FQDN | ADDRESS }"
	echo -e "\twhois\t{ HOSTNAME | ADDRESS | MAC }"
	echo -e
	echo -e "Typing shortcuts: rst lst sta dis act hst addr downl res who whos"
	exit 1
}

#Returns SUCCESS if the service is running.
is_running() {
	pgrep -f "$SERVICE_NAME" >/dev/null
	return "$?"
}

#Checks if the service is running.
check_running() {
	if ! is_running; then
		>&2 echo "The service is not running."
		exit 2
	fi
	return 0
}

#Checks if hosts and cache files exist.
check_files() {
	[ -f "$HOSTS_FILE" ] && [ -f "$CACHE_FILE" ] && return 0
	exit 2
}

#init.d shortcut commands
start_service() {
	if is_running; then
		>&2 echo "The service is already running."
		exit 2
	fi
	/etc/init.d/ip6neigh start
}
stop_service() {
	check_running && /etc/init.d/ip6neigh stop
}
restart_service() {
	/etc/init.d/ip6neigh restart
}
enable_service() {
	/etc/init.d/ip6neigh enable
}
disable_service() {
	/etc/init.d/ip6neigh disable
}

#Loads UCI configuration.
load_config() {
	reset_cb
	config_load ip6neigh
	config_get LAN_IFACE config lan_iface lan
	config_get DOMAIN config domain

	#Gets the physical devices
	network_get_physdev LAN_DEV "$LAN_IFACE"

	#Gets DNS domain from /etc/config/dhcp if not defined in ip6neigh config. Defaults to 'lan'.
	if [ -z "$DOMAIN" ]; then
		DOMAIN=$(uci get dhcp.@dnsmasq[0].domain 2>/dev/null)
	fi
	if [ -z "$DOMAIN" ]; then DOMAIN="lan"; fi
}

#Prints the hosts file in a user friendly format.
list_hosts() {
	check_running
	check_files
	
	#Get the line number that divides the two sections of the hosts file
	local ln=$(grep -n '^#Discovered' "$HOSTS_FILE" | cut -d ':' -f1)
	
	case "$1" in
		#All hosts without comments or blank lines
		all)
			grep '^[^#]' "$HOSTS_FILE" |
				awk '{printf "%-30s %s\n",$2,$1}' |
				sort
		;;
		#Only static hosts
		sta*)
			awk "NR>1&&NR<(${ln}-1)"' {printf "%-30s %s\n",$2,$1}' "$HOSTS_FILE" |
				sort
		;;
		#Only discovered hosts
		dis*)
			awk "NR>${ln}"' {printf "%-30s %s\n",$2,$1}' "$HOSTS_FILE" |
				sort
		;;
		#REACHABLE and STALE
		act*)
			load_config
			
			#Iterate through entries in the neighbors table and populates a temp file.
			local addr
			local reg
			> /tmp/ip6neigh.lst
			ip -6 neigh show dev "$LAN_DEV" nud reach |
				grep -E 'REACHABLE$|[0-9,a-f] STALE$' |
				cut -d ' ' -f1 |
				while IFS= read -r addr
				do
					reg=$(grep -m 1 "^$addr " "$HOSTS_FILE")
					if [ -n "$reg" ]; then
						echo "$reg" |
							awk '{printf "%-30s %s\n",$2,$1}' \
							>> /tmp/ip6neigh.lst
					fi
				done

				#Prints the temp file.
				sort /tmp/ip6neigh.lst
				rm /tmp/ip6neigh.lst			
		;;
		#Addresses from a specific host
		host|hst)
			local host=$(echo "$2" | cut -d '.' -f1)
			grep -i -E " ${host}(\.|$)" "$HOSTS_FILE" |
				awk '{printf "%-30s %s\n",$2,$1}' |
				sort
		;;
		#All hosts with comments
		'')
			echo "#Predefined hosts"
			awk "NR>1&&NR<(${ln}-1)"' {printf "%-30s %s\n",$2,$1}' "$HOSTS_FILE" |
				sort
			echo -e "\n#Discovered hosts"
			awk "NR>${ln}"' {printf "%-30s %s\n",$2,$1}' "$HOSTS_FILE" |
				sort
		;;
		#Invalid parameter
		*)	display_help;;
	esac
}

#Format FQDN for grep.
format_fqdn() {
	load_config
	
	#Check FQDN
	local ffqdn="$2"
	#Ends with .lan ?
	echo "$2" | grep -q "\.$DOMAIN"
	if [ "$?" = 0 ]; then
		#Yes. Multiple labels ?
		echo "$2" | grep -q ".*\..*\.$DOMAIN"
		if [ "$?" != 0 ]; then
			#No. It only has one and it must be removed.
			ffqdn=$(echo "$2" | sed -r 's/(.*)\..*/\1/')
		fi
	else
		#No. Has any label ?
		echo "$2" | grep -q '\.'
		if [ "$?" = 0 ]; then
			#Yes and is not .lan. Must add .lan in the end.
			ffqdn="${2}.${DOMAIN}"
		fi
	fi
	
	#Escape dots
	ffqdn=$(echo "$ffqdn" | sed 's/\./\\\./g')
	
	#Returns the formatted FQDN.
	eval "$1='$ffqdn'"
}

#Displays the addresses for the supplied name
show_address() {
	check_running
	check_files
	
	#Check FQDN
	local name
	format_fqdn name "$1"
	
	case "$2" in
		#Any number of addresses 
		'')
			grep -i " ${name}$" "$HOSTS_FILE" |
				cut -d ' ' -f1
		;;
		#Limit to one address
		'1')
			grep -m 1 -i " ${name}$" "$HOSTS_FILE" |
				cut -d ' ' -f1
		;;
		#Invalid parameter
		*) display_help;;
	esac
}

#Displays the name for the IPv6 or MAC address
show_name() {
	check_running
	check_files
	
	#Get name from the hosts file.
	grep -m 1 -i "^$1 " "$HOSTS_FILE" | cut -d ' ' -f2
}

#Display the MAC address for a simple name, FQDN or IPv6 address.
show_mac() {
	check_running
	check_files
	local name
	
	#Check if it's address or name.
	echo "$1" | grep -q ':'
	if [ "$?" = 0 ]; then
		#It's an address.
		name=$(
			grep -m 1 -i "^$1 " "$HOSTS_FILE" |
			cut -d ' ' -f2 |
			cut -d '.' -f1
		)
	else
		#It's a simple name or FQDN.
		name=$(echo "$1" | cut -d '.' -f1)
	fi
	
	[ -n "$name" ] || exit 3
	
	#Get the MAC address from the cache file.
	grep -m 1 -i " ${name}$" "$CACHE_FILE" |
		cut -d ' ' -f1
}

#Resolves name to address or address to name.
resolve_cmd() {
	check_running
	check_files
	
	#Check if it's address or name.
	echo "$1" | grep -q ':'
	if [ "$?" = 0 ]; then
		#It's an address.
		grep -m 1 -i "^$1 " "$HOSTS_FILE" |
			awk '{printf "%s is named %s\n",$1,$2}'
	else
		#Prepare name for grep
		local name
		format_fqdn name "$1"

		grep -i " ${name}$" "$HOSTS_FILE" |
			awk '{printf "%s has address %s\n",$2,$1}'
	fi
}

#Displays the simple name (no FQDN) for the address or all addresses for the simple name.
whois_this() {
	check_running
	check_files
	
	local host
	local names
	local mac
	local manuf
	local reg
	
	#Check if it's an address.
	echo "$1" | grep -q ':'
	if [ "$?" = 0 ]; then
		#Check if it's a MAC address.
		echo "$1" | grep -q '..:..:..:..:..:..'
		if [ "$?" = 0 ]; then
			#MAC address. Get name from the cache file.
			reg=$(grep -m 1 -i "^$1 " "$CACHE_FILE")
			mac=$(echo "$reg" | cut -d ' ' -f1)
			host=$(echo "$reg" | cut -d ' ' -f3)
		else
			#IPv6 address. Get name from the hosts file.
			host=$(
				grep -m 1 -i "^$1 " "$HOSTS_FILE" |
				cut -d ' ' -f2 |
				cut -d '.' -f1
			)
			
			mac=$(
				grep -m 1 -i " $host" "$CACHE_FILE" |
				cut -d ' ' -f1
			)
		fi
	else
		#Host
		host=$(echo "$1" | cut -d '.' -f1)
		reg=$(grep -m 1 -i " ${host}$" "$CACHE_FILE")
		mac=$(echo "$reg" | cut -d ' ' -f1)
		host=$(echo "$reg" | cut -d ' ' -f3)
	fi
	
	#Exit if no host was found.
	[ -n "$host" ] || exit 3
	
	#Displays the output message with OUI info if available.
	if oui_name manuf "$mac"; then
		echo -e "Hostname: $host\t\tMAC: $mac\t\tOUI: $manuf"
	else	
		echo -e "Hostname: $host\t\tMAC: $mac"
	fi
	
	#Displays a list of names that belong to this host.
	names=$(
		grep -i -E " ${host}(\.|$)" "$HOSTS_FILE" |
		cut -d ' ' -f2 |
		sort |
		uniq
	)
	echo 'FQDNs:' $names
}

#Download OUI database
oui_download() {
	echo "Downloading Nmap MAC prefixes..."
	wget -O '/tmp/oui-raw.txt' 'http://linuxnet.ca/ieee/oui/nmap-mac-prefixes' || exit 2

	echo -e "\nApplying filters..."

	cat /tmp/oui-raw.txt |
		tr '\t' ' ' |
		cut -d ' ' -f1-2 |
		grep "^[^#]" |
		sort -t' ' -k1 |
		sed 's/[^[0-9,a-z,A-Z]]*//g' \
	> /tmp/oui-filt.txt

	rm /tmp/oui-raw.txt

	echo "Compressing database..."
	mv /tmp/oui-filt.txt /tmp/oui
	gzip -f /tmp/oui || exit 3

	echo "Moving the file..."
	mv /tmp/oui.gz "$SHARE_DIR" || exit 4

	echo -e "\nThe new compressed OUI database file was successfully moved to: ${SHARE_DIR}oui.gz"
}

#Searches for the OUI of the MAC in a manufacturer list.
oui_name() {
	#Fails if OUI file does not exist.
	[ -f "$OUI_FILE" ] || return 1
	
	#Get MAC and separates OUI part.
	local mac=$(echo "$2" | tr -d ':')
	local oui="${mac:0:6}"
	
	#Check if the MAC is locally administered.
	if [ "$((0x${oui:0:2} & 0x02))" != 0 ]; then
		#Returns LocAdmin as name and success.
		eval "$1='LocAdmin'"
		return 0
	fi

	#Searches for the OUI in the database.
	local reg=$(gunzip -c "$OUI_FILE" | grep -i -m 1 "^$oui")
	local oname="${reg:6}"
	
	#Check if found.
	if [ -n "$oname" ]; then
		#Returns the manufacturer name and success code.
		eval "$1='$oname'"
		return 0
	fi

	#Manufacturer not found. Returns Unknown and success code.
	eval "$1='Unknown'"
	return 0
}

#Display manufacturer name
oui_manufacturer() {
	#Perform OUI lookup
	local manuf
	if oui_name manuf "$1"; then
		echo "$manuf"
	else
		>&2 echo "The OUI database is not installed. Please run ip6neigh oui download."
		exit 2
	fi
}

#OUI related commands
oui_cmd() {
	case "$1" in
		#Download OUI database
		downl*) oui_download;;
		
		#Display manufacturer name
		??:??:??:??:??:??) oui_manufacturer "$1";;
		
		#Invalid parameter
		*) display_help;;
	esac
}

#This script file
CMD="$0"

#Checks which command was called.
case "$1" in
	'start')			start_service "$0";;
	'stop')				stop_service;;
	'restart'|'rst')	restart_service;;
	'enable')			enable_service;;
	'disable')			disable_service;;
	'list'|'lst')		list_hosts "$2" "$3";;
	'address'|'addr')	show_address "$2" "$3";;
	'name')				show_name "$2";;
	'mac')				show_mac "$2";;
	'resolve'|'res')	resolve_cmd "$2" "$3";;
	'whois'|'whos'|'who') whois_this "$2";;
	'oui')				oui_cmd "$2";;
	*)					display_help;;
esac

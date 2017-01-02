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


#	Script to display ip6neigh hosts file with columnar formatting (via awk)
#	Script is called by luci-app-command for a web interface, or can be run directly
#
#	by André Lange	& Craig Miller	Dec 2016

readonly HOSTS_FILE="/tmp/hosts/ip6neigh"
readonly SERVICE_NAME="ip6neigh_svc.sh"

#Check if received valid arguments
if [ -n "$1" ]; then
	case "$1" in
		"-p"|"-d");;
		*)
		#Display help text
		echo "ip6neigh Hosts Display Script"
		echo -e
		echo "usage: $0 [option]"
		echo -e
		echo "where option is one of:"
		echo -e
		echo "	-p		Show only predefined SLAAC hosts"
		echo "	-d		Show only discovered hosts"
		echo -e
		exit 1
	esac
fi

#Shows nothing if the hosts file does not exist
[ -f "$HOSTS_FILE" ] || exit 1

#Check if the service is running
if ! pgrep -f "$SERVICE_NAME" >/dev/null; then
	echo "#SERVICE SCRIPT IS NOT RUNNING. THE INFORMATION MAY BE OUTDATED."
fi

#Get the line number that divides the two sections of the hosts file
ln=$(grep -n '^#Discovered' "$HOSTS_FILE" | cut -d ':' -f1)

#Check if allowed to show predefined hosts
if [ "$1" != "-d" ]; then
	echo "#Predefined hosts"
	awk "NR>1&&NR<(${ln}-1)"' {printf "%-30s %s %s\n",$2,$1,$3}' "$HOSTS_FILE" | sort -k1
	[ "$1" = "-p" ] || echo -e
fi

#Check if allowed to show discovered hosts
if [ "$1" != "-p" ]; then
	echo "#Discovered hosts"
	awk "NR>${ln}"' {printf "%-30s %s %s\n",$2,$1,$3}' "$HOSTS_FILE" | sort -k1
fi

exit 0

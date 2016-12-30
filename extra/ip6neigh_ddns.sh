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


#	Script for feeding public IPv6 addresses with dynamic prefix to update with
#	OpenWrt DDNS Scripts. Usage example:
#
#	ip6neigh_ddns.sh Server1.PUB.lan 
#
#	by André Lange	Dec 2016

name="$1"
[ -n "$name" ] || exit 1

line=$(grep -m 1 " ${name}$" /tmp/hosts/ip6neigh 2>/dev/null)
[ "$?" = 0 ] || exit 2

echo "$line" | cut -d ' ' -f1
return 0

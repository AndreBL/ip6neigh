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

#	Script to download and format an OUI database to be used with ip6neigh script.
#
#	by André Lange	Dec 2016

readonly SHARE_DIR="/usr/share/ip6neigh/"

echo "Downloading Nmap MAC prefixes..."
wget -O '/tmp/oui-raw.txt' 'http://linuxnet.ca/ieee/oui/nmap-mac-prefixes' || exit 1

echo -e "\nApplying filters..."
cut -d ' ' -f1-2 /tmp/oui-raw.txt | grep "^[^#]" | sort -t' ' -k1 | sed 's/[^[0-9,a-z,A-Z]]*//g' > /tmp/oui-filt.txt
rm /tmp/oui-raw.txt

echo "Compressing database..."
mv /tmp/oui-filt.txt /tmp/oui
gzip -f /tmp/oui || exit 2

echo "Moving the file..."
mv /tmp/oui.gz "$SHARE_DIR" || exit 3

echo -e "\nThe new compressed OUI database file is at: ${SHARE_DIR}oui.gz"

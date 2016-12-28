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


#	Script to displays ip6neigh host file with columnar formatting (via awk)
#	Script is called by luci-app-command for a web interface, or can be run directly
#
#	by André Lange	& Craig Miller	Dec 2016

HOSTFILE="/tmp/hosts/ip6neigh"
cat $HOSTFILE | awk '{printf "%-40s %s %s\n",$1,$2,$3}'


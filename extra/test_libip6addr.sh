#!/bin/sh
##################################################################################
#
#  Copyright (C) 2017 Craig Miller
#
#  See the file "LICENSE" for information on usage and redistribution
#  of this file, and for a DISCLAIMER OF ALL WARRANTIES.
#  Distributed under GPLv2 License
#
##################################################################################


#	Test of IPv6 address expansion/compression functions (ip6addr_functions.sh)
#
#	by Craig Miller		20 Feb 2017


if [ -e ../lib/ip6addr_functions.sh ]; then
	# used for testing off router
	. ../lib/ip6addr_functions.sh
else
	# testing on the router
	. /usr/lib/ip6neigh/ip6addr_functions.sh
fi

#VERSION 1.1.1

test() {

	if [ "$(compress_addr $(expand_addr $1))" == "$1" ]; then
		echo "$1 -- OK"
	else
		echo "$1 -- FAILED"
	fi

}


case "$1" in
	# self test - call with '-t' parameter
	'-t')

		# add address examples to test
		test fd11::1d70:cf84:18ef:d056
		test 2a01::1
		test fe80::f203:8cff:fe3f:f041
		test 2001:db8:123::5
		test 2001:0db8:0123::05
		test 2001:470:ebbd:0:f203:8cff:fe3f:f041
		# special cases
		test ::1
		test fd32:197d:3022:1101::
	;;
	
	# call a specific function with arguments - Example: -f expand_addr ::1
	'-f')
		shift 1
		eval "$*"
		expand_addr ::2
	;;
esac


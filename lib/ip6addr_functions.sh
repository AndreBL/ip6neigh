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


#	IPv6 address manipulation functions library for ip6neigh script
#
#	by André Lange		Fev 2017

#Program definitions
IP6ADDR_LIB_VERSION='1.3.0'

#Print version info and return if requested
if [ "$1" = '--version' ]; then
	echo "ip6addr Library Script v${IP6ADDR_LIB_VERSION}"
	return 0
fi

#Scans the address from left to right
#1: return var, 2: ip6addr
_left_scan() {
	local j c
	local n=0
	local x=1
	
	#Iterates through each character
	for j in $(seq 0 $((${#1}-1)))
	do
		#Stops when '::' is found
		[ "${1:$j:2}" = '::' ] && return $n
		
		#Current char
		c="${1:$j:1}"
	
		case "$c" in
			#Stop when reached the end
			''|'.') return $n;;
			
			#Quibble advance
			':') x=$(($x+1));;
			
			#Hex digit
			*)
				#Copy character to quibble
				n=$x
				eval "q${n}=\"\${q${n}}${c}\""
			;;
		esac
	done
	
	return $n
}

#Scans the address from right to left
#1: return var, 2: ip6addr
_right_scan() {
	local j c
	local n=8
	local f="$2"
	local ismapped=0
	
	#Iterates through each character in reverse order
	for j in $(seq $((${#1}-1)) -1 0)
	do
		#Stops when '::' is found
		[ "${1:$(($j-1)):2}" = '::' ] && break
		
		#Current char
		c="${1:$j:1}"
		
		case "$c" in
			#Stops when reached the end (start)
			'') return 0;;
			
			#IPv4-mapped IPv6 address: skip one quibble and set flag
			'.')
				[ "$ismapped" = 0 ] && n=$(($n-1))
				ismapped=1
			;;
			
			#Quibble advance (backwards)
			':')
				n=$(($n-1))
			
				#Stop when reached the last quibble that was processed when scannin from left to right
				[ "$n" = "$f" ] && return 0
			;;
			
			#Hex digit
			*)
				#Copy character to quibble
				eval "q${n}=\"${c}\${q${n}}\""
			;;
		esac
	done
	
	#Needs to process IPv4-mapped IPv6 address ?
	[ "$ismapped" = 1 ] || return 0
	local d1 d2 d3 d4
	n=4
	
	#Iterates through each character in reverse order
	for j in $(seq $((${#1}-1)) -1 0)
	do
		#Current char
		c="${1:$j:1}"
		
		case "$c" in
			#Octed advance (backwards)
			'.') n=$(($n-1));;
			
			#End of last (first) octed
			':') break;;
			
			#Decimal digit
			*)
				#Copy character to octet
				eval "d${n}=\"${c}\${d${n}}\""
			;;
		esac
	done
	
	#Convert pairs of octets to 16-bit wide decimal numbers
	eval q7=$((($d1<<8)+$d2))
	eval q8=$((($d3<<8)+$d4))
	
	#Return signaling that q6 and q7 are decimal numbers
	return 1
}

#Converts a compressed address representation to the expanded form
#1: ip6addr
expand_addr() {
	#Do nothing with empty argument
	[ -n "$1" ] || return 0

	#Does it really need to be processed ?
	case "$1" in
		*'::'*|*'.'*);;
		#Does not contain '::'
		*)
			#Print unmodified
			echo "$1"
			return 0
		;;
	esac
		
	#Save and reset the field separator
	local OIFS="$IFS"
	unset IFS
	
	#Process from left to right and then from right to left
	local addr="$1"
	local q1 q2 q3 q4 q5 q6 q7 q8
	_left_scan "$addr"
	_right_scan "$addr" "$?"

	#Check the return code
	if [ "$?" = 0 ]; then
		#Regular IPv6 address. Creates the final string by printing all quibbles as hex numbers.
		printf '%x:%x:%x:%x:%x:%x:%x:%x\n' "0x0$q1" "0x0$q2" "0x0$q3" "0x0$q4" "0x0$q5" "0x0$q6" "0x0$q7" "0x0$q8"
	else
		#IPv4-mapped IPv6 address. The last two quibbles come from decimal numbers.
		printf '%x:%x:%x:%x:%x:%x:%x:%x\n' "0x0$q1" "0x0$q2" "0x0$q3" "0x0$q4" "0x0$q5" "0x0$q6" "$q7" "$q8"
	fi
	
	#Restore the field separator
	IFS="$OIFS"
	
	return 0
}

#Converts an expanded address representation to the compressed form
#1: ip6addr
compress_addr() {
	#Do nothing with empty argument
	[ -n "$1" ] || return 0

	#Does it really need to be processed ?
	local addr=":$1:"
	case "$addr" in
		*':0:0:'*);;
		#Does not contain ate least two consecutive null quibbles.
		*)
			#Print unmodified
			echo "$1"
			return 0
		;;
	esac
	
	#Save and reset the field separator
	local OIFS="$IFS"
	unset IFS

	#Match template
	local z=':0:0:0:0:0:0:0:0:'

	#Searches for sequences of :0, starting from the longest one.
	local m
	local result
	for j in $(seq 17 -2 5)
	do
		#New match string with length j
		m="${z:0:$j}"
		case "$addr" in
			#Contains this sequence of zeros
			*"$m"*)
				#Replace the first sequence found
				result=$(echo "$addr" | sed "s/${m}/::/")
				break
			;;
		esac
	done
	
	#All-zeros result ?
	if [ "$result" = '::' ]; then echo '::';
	else
		#Remove the leading ':' if not '::'
		[ "${result:0:2}" != '::' ] && result="${result:1}"
		
		#Remove the trailing ':' if not '::'
		[ "${result:$((${#result}-2)):2}" != '::' ] && result="${result:0:$((${#result}-1))}"
		
		#Print result
		echo "$result"
	fi
	
	#Restore the field separator
	IFS="$OIFS"
	
	return 0
}

#Returns the /64 prefix of the address
#1: ip6addr
addr_prefix64() {
	#Do nothing with empty argument
	[ -n "$1" ] || return 0
	
	#Expand the address
	local expaddr=$(expand_addr "$1")
	
	#Cut the first four quibbles
	echo "$expaddr" | cut -d ':' -f1-4

	return 0
}

#Returns the 64-bit interface identifier of the address
#1: ip6addr
addr_iid64() {
	#Do nothing with empty argument
	[ -n "$1" ] || return 0
	
	#Expand the address
	local expaddr=$(expand_addr "$1")
	
	#Cut the last four quibbles
	echo "$expaddr" | cut -d ':' -f5-8

	return 0
}

#Joins a /64 prefix with an interface identifier to create an address
#1: /64 prefix, 2: 64-bit IID
join_prefix64_iid64() {
	#Do nothing with empty argument
	[ -n "$1" -a -n "$2" ] || return 0

	local prefix="$1"
	local iid="$2"
	local newaddr
	
	#Gets the prefix
	[ "${prefix:$((${#prefix}-2)):2}" != '::' ] && prefix="${prefix}::" 
	prefix=$(addr_prefix64 "$prefix")
	
	#Gets the IID
	[ "${iid:0:2}" != '::' ] && iid="::${iid}" 
	iid=$(addr_iid64 "$iid")
	
	#Creates the new address by concatenation
	newaddr="${prefix}:${iid}"

	#Converts to compressed form
	compress_addr "$newaddr"
	
	return 0
}

#Generates EUI-64 interface identifier based on MAC address
#1: MAC address xx:xx:xx:xx:xx:xx
gen_eui64() {
	local mac=$(echo "$1" | awk '{print tolower($0)}')
	local q1="0x${mac:0:2}${mac:3:2}"
	local q2="0x${mac:6:2}ff"
	local q3="0xfe${mac:9:2}"
	local q4="0x${mac:12:2}${mac:15:2}"
	
	#Flip U/L bit
	q1=$(($q1 ^ 0x0200))
		
	#Print result
	printf '%x:%x:%x:%x\n' "$q1" "$q2" "$q3" "$q4"
	
	return 0
}

#Returns 0 if the supplied IPv6 address has an EUI-64 interface identifier.
#1: ip6addr
addr_is_eui64() {
	echo "$1" | grep -q -E ':[^:]{0,2}ff:fe[^:]{2}:[^:]{1,4}$'
	return "$?"	
}

#Generates a match string for an address with the same IID
#1: expanded IID like 1:2:3:4
gen_iid_match() {
	local iid="q${1}w"
	local comp
	case "$iid" in
		#4 zeros
		q0:0:0:0w)	comp='q:w';;
		
		#3 zeros
		q0:0:0:*)	comp=$(echo "$iid" | sed "s/q0:0:0:/q:/")	;;
		*:0:0:0w)	comp=$(echo "$iid" | sed "s/:0:0:0w/::w/")	;;

		#2 zeros
		q0:0:*)		comp=$(echo "$iid" | sed "s/q0:0:/q:/")		;;
		*:0:0:*)	comp=$(echo "$iid" | sed "s/:0:0:/::/")		;;
		*:0:0w)		comp=$(echo "$iid" | sed "s/:0:0w/::w/")	;;
		
		#1 zero
		q0:*)		comp=$(echo "$iid" | sed "s/q0:/q:/")		;;
	esac
	
	if [ -n "$comp" ]; then
		#Remove leading 'q' and 'w'
		comp="${comp:1:$((${#comp}-2))}"
		
		#Match string
		echo "[^ ]*(:${1}|:${comp})"
	else
		#Uncompressed only
		echo "[^ ]*:$1"
	fi
	
	return 0
}

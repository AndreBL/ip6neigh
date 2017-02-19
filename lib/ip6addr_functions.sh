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

#Scans the address from left to right
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
		
		#Stops when reached the end
		[ -z "$c" ] && return $n
		
		if [ "$c" = ':' ]; then
			#Quibble advance
			x=$(($x+1))
		else
			#Copy character to quibble
			n=$x
			eval "q${n}=\"\${q${n}}${c}\""
		fi
	done
	
	return $n
}

#Scans the address from right to left
_right_scan() {
	local j c
	local n=8
	local f="$2"
	
	#Iterates through each character in reverse order
	for j in $(seq $((${#1}-1)) -1 0)
	do
		#Stops when '::' is found
		[ "${1:$(($j-1)):2}" = '::' ] && return 0
		
		#Current char
		c="${1:$j:1}"
		
		#Stops when reached the end
		[ -z "$c" ] && return 0
		
		if [ "$c" = ':' ]; then
			#Quibble advance
			n=$(($n-1))
			
			#Stops when reached the last quibble that was processed when scannin from left to right
			[ "$n" = "$f" ] && return 0
		else
			#Copy character to quibble
			eval "q${n}=\"${c}\${q${n}}\""
		fi
	done
	
	return 0
}

#Converts a compressed address representation to the expanded form
#1: return var, 2: ip6addr
expand_addr() {
	#Do nothing with empty argument
	[ -n "$2" ] || return 0

	#Does it really need to be processed ?
	if ! echo "$2" | grep -q '::'; then
		eval "$1='$2'"
		return 0
	fi
		
	local _result
	local q1 q2 q3 q4 q5 q6 q7 q8
	
	#Save and reset the field separator
	local OIFS="$IFS"
	unset IFS
	
	#Process from left to right and then from right to left
	_left_scan "$2"
	_right_scan "$2" "$?"

	#Creates the final address by printing all quibbles as hex numbers
	_result=$(printf '%x:%x:%x:%x:%x:%x:%x:%x\n' "0x0$q1" "0x0$q2" "0x0$q3" "0x0$q4" "0x0$q5" "0x0$q6" "0x0$q7" "0x0$q8")
	eval "$1='$_result'"
	
	#Restore the field separator
	IFS="$OIFS"
	
	return 0
}

#Converts an expanded address representation to the compressed form
#1: return var, 2: ip6addr
compress_addr() {
	#Do nothing with empty argument
	[ -n "$2" ] || return 0

	#Does it really need to be processed ?
	local _addr=":$2:"
	if ! echo "$_addr" | grep -q ':0:0:'; then
		eval "$1='$2'"
		return 0
	fi
	
	#Save and reset the field separator
	local OIFS="$IFS"
	unset IFS

	local z=':0:0:0:0:0:0:0:0:'
	local m
	local _result
	
	#Searches for sequences of :0, starting from the longest one.
	for j in $(seq 17 -2 5)
	do
		m="${z:0:$j}"
		if echo "$_addr" | grep -q "$m"; then
			#Removes the first sequence
			_result=$(echo "$_addr" | sed "s/${m}/::/")
			break
		fi
	done
	
	#All-zeros result ?
	if [ "$_result" = '::' ]; then eval "$1='::'";
	else
		#Remove the leading ':' if not '::'
		[ "${_result:0:2}" != '::' ] && _result="${_result:1}"
		
		#Remove the trailing ':' if not '::'
		[ "${_result:$((${#_result}-2)):2}" != '::' ] && _result="${_result:0:$((${#_result}-1))}"
		
		#Returns the result
		eval "$1='${_result}'";
	fi
	
	#Restore the field separator
	IFS="$OIFS"
	
	return 0
}

#Returns the /64 prefix of the address
#1: return var, 2: ip6addr
addr_prefix64() {
	#Do nothing with empty argument
	[ -n "$2" ] || return 0
	
	local _expaddr
	local __result
	
	#Expand the address
	expand_addr _expaddr "$2"
	
	#Cut the first four quibbles
	__result=$(echo "$_expaddr" | cut -d ':' -f1-4)
	eval "$1='${__result}'";

	return 0
}

#Returns the 64-bit interface identifier of the address
#1: return var, 2: ip6addr
addr_iid64() {
	#Do nothing with empty argument
	[ -n "$2" ] || return 0

	local _expaddr
	local __result
	
	#Expand the address
	expand_addr _expaddr "$2"
	
	#Cut the last four quibbles
	__result=$(echo "$_expaddr" | cut -d ':' -f5-8)
	eval "$1='${__result}'";

	return 0
}

#Joins a /64 prefix with an interface identifier to create an address
#1: return var, 2: /64 prefix, 3: 64-bit IID
join_prefix64_iid64() {
	#Do nothing with empty argument
	[ -n "$2" -a -n "$3" ] || return 0

	local prefix="$2"
	local iid="$3"
	local _newaddr
	local __result
	
	#Gets the prefix
	[ "${prefix:$((${#prefix}-2)):2}" != '::' ] && prefix="${prefix}::" 
	addr_prefix64 prefix "$prefix"
	
	#Gets the IID
	[ "${iid:0:2}" != '::' ] && iid="::${iid}" 
	addr_iid64 iid "$iid"
	
	#Creates the new address by concatenation
	_newaddr="${prefix}:${iid}"

	#Converts to compressed form
	compress_addr __result "$_newaddr"
	eval "$1='${__result}'";
	
	return 0
}

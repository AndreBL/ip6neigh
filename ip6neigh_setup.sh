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

#	Script to download and install ip6neigh script to an OpenWrt router.
#
#	by André Lange	Dec 2016

readonly SETUP_VER=1

readonly BIN_DIR="/usr/bin/"
readonly SHARE_DIR="/usr/share/ip6neigh/"
readonly TEMP_DIR="/tmp/ip6neigh/"

readonly CONFIG_FILE="/etc/config/ip6neigh"
readonly HOSTS_FILE="/tmp/hosts/ip6neigh"
readonly CACHE_FILE="/tmp/ip6neigh.cache"

readonly REPO="https://raw.githubusercontent.com/AndreBL/ip6neigh/master/"

#Installation list
readonly inst_list="
dir ${SHARE_DIR}
file ${BIN_DIR}ip6neigh_mon.sh main/ip6neigh_mon.sh x
file /etc/init.d/ip6neigh etc/init.d/ip6neigh x
file /etc/hotplug.d/iface/30-ip6neigh etc/hotplug.d/iface/30-ip6neigh x
file ${TEMP_DIR}config etc/config/ip6neigh

file ${BIN_DIR}ip6neigh_oui_download.sh extra/ip6neigh_oui_download.sh x
file ${BIN_DIR}ip6neigh_host_show.sh extra/ip6neigh_host_show.sh x
file ${BIN_DIR}ip6neigh_ddns.sh extra/ip6neigh_ddns.sh x
"

#Uninstallation list
readonly uninst_list="
file /etc/hotplug.d/iface/30-ip6neigh etc/hotplug.d/iface/30-ip6neigh
file /etc/init.d/ip6neigh etc/init.d/ip6neigh
file ${BIN_DIR}ip6neigh_*.sh
tree ${SHARE_DIR}
"

#Success message
readonly SUCCESS_MSG="
The installation was successful. Run the following command if you want to download an offline OUI lookup database:

ip6neigh_oui_download.sh

Start ip6neigh by running:

/etc/init.d/ip6neigh start
"

#Writes error message to stderr and exit program.
errormsg() {
	local msg="Error: $1"
	>&2 echo -e "\n$msg\n"
	exit 1
}

#Flags error during uninstall.
flag_error() {
	error=1
	return 0
}

#Use cURL to download a file.
download_file() {
	local dest="$1"
	local source="$2"
	local url="${REPO}${source}"

	if ! curl -s -S -f -k -o "$dest" "$url"; then
		errormsg "Could not download ${url}.\n\nFailed to complete installation."
	fi
}

#Processes each line of the install list
install_line() {
	local command="$1"
	case "$command" in
		#Create directory
		"dir")
			local dirname="$2"
			echo "Creating directory ${dirname}"
			mkdir -p "$dirname"
			[ -d "$dirname" ] || errmsg "Could not create directory ${dirname}"
		;;
		
		#Download file
		"file")
			local destname="$2"
			local sourcename="$3"
			local execflag="$4"
			
			echo "Downloading ${sourcename}"
			download_file "$destname" "$sourcename"
			if [ "$execflag" = "x" ]; then
				chmod +x "$destname" || errormsg "Failed to change permissions for file ${destfile}."
			fi
		;;
	esac
}

#Processes each line of the uninstall list
uninstall_line() {
	local command="$1"
	case "$command" in
		#Remove single directory
		"dir")
			local dirname="$2"
			if [ -d "$dirname" ]; then
				echo "Removing directory ${dirname}"
				rmdir "$dirname" || flag_error
			fi
		;;
		
		#Remove directory tree
		"tree")
			local dirname="$2"
			if [ -d "$dirname" ]; then
				echo "Removing directory tree ${dirname}"
				rm -rf "$dirname" || flag_error
			fi
		;;
		
		#Remove files
		"file")
			shift
			local fname
			for fname in "$@";
			do
				if [ -f "$fname" ]; then
					echo "Removing ${fname}"
					rm "$fname" || flag_error
				fi
			done
		;;
	esac
}

#Installation routine
install() {
	mkdir -p "$TEMP_DIR" || errormsg "Failed to create directory $TEMP_DIR"
	
	#Check if this installer's version match the repository
	echo "Checking installer version..."
	download_file "${TEMP_DIR}VERSION" "setup/VERSION"
	[ "$SETUP_VER" = "$(cat ${TEMP_DIR}VERSION)" ] || errormsg "This installation script is out of date. Please visit https://github.com/AndreBL/ip6neigh and check if a new version of the installer is available for download."
	echo "Installer script is up to date."
	
	#Check if already installed
	[ -d "$SHARE_DIR" ] && echo -e "\n The existing installation of ip6neigh will be overwritten."
	
	#Process install list
	echo -e
	local line
	IFS=$'\n'
	for line in $inst_list;
	do
		IFS=' '
		[ -n "$line" ] && install_line $line
	done
	
	#Check if UCI config file exists.
	if [ -f "$CONFIG_FILE" ]; then
		local confdest="${CONFIG_FILE}.example"
		echo -e "\nNot overwriting existing config file ${CONFIG_FILE}.\nThe downloaded example config file will be moved to ${confdest}."
		mv /tmp/ip6neigh/config "$confdest" || errormsg "Failed to move the configuration file"
	else
		mv /tmp/ip6neigh/config "$CONFIG_FILE" || "Failed to move the configuration file"
	fi
	
	#Remove temporary directory
	uninstall_line tree "$TEMP_DIR"
	
	#Successful installation
	echo -e "$SUCCESS_MSG"
}

#Uninstallation routine
uninstall() {
	[ -d "$SHARE_DIR" ] || errormsg "ip6neigh is not installed on this system."
	
	#Check if ip6neigh is running
	pgrep -f ip6neigh_mon.sh >/dev/null
	if [ "$?" = 0 ]; then
		echo "Stopping ip6neigh..."
		/etc/init.d/ip6neigh stop
		sleep 2
		echo -e
	fi
	
	#Remove hosts and cache files
	uninstall_line file "$HOSTS_FILE"
	uninstall_line file "$CACHE_FILE"
	
	#Process uninstall list
	IFS=$'\n'
	for line in $uninst_list;
	do
		IFS=' '
		[ -n "$line" ] && uninstall_line $line
	done
	
	#Remove temporary directory
	uninstall_line tree "$TEMP_DIR"
	
	[ -f "$CONFIG_FILE" ] && echo -e "\nThe config file $CONFIG_FILE was kept in place for future use. Please remove this file manually if you will not need it anymore."
	
	#Check if any error ocurred while removing files
	if [ -z "$error" ]; then
		echo -e "\nFinished uninstalling ip6neigh."
	else
		errormsg "Some files or directories could not be removed. Check previous error messages."
	fi
}

#Help text
display_help() {
	echo "ip6neigh Installer Script"
	echo -e
	echo "usage: $1 command"
	echo -e
	echo "where command is one of:"
	echo -e
	echo -e "\tinstall\t\tInstall ip6neigh"
	echo -e "\tremove\t\tRemove ip6neigh from the system"
	echo -e
}

#Check input parameters
case "$1" in
	"install") install;;
	"remove") uninstall;;
	*) display_help "$0"
esac

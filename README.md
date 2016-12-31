## Giving local DNS names to IPv6 SLAAC addresses 
#### OpenWrt shell script

## Synopsis

The purpose of the script is to automatically generate and update IPv6 DNS host names on the OpenWrt router, making access to devices by name (either IPv4 or IPv6) on your network a snap. It does this by creating a hosts file giving local DNS names to IPv6 addresses that IPv6 enabled devices took via SLAAC mechanism.

Rather than using clunky IP addresses (v4 or v6), devices on your network now become:
* router.lan
* mycomputer.lan

## Motivation

IPv6 addresses are difficult to remember. DNS provides an abstraction layer, so that IP addresses do not have to be memorized. There are at least two situations where this set up is useful:

1. When you need to trace some network activity through tcpdump or Realtime Connections page on LuCI and there are lots of IPv6 addresses there and you don't know who/what they belong to.

2. When you are accessing your LAN hosts either locally or remotely through VPN. Even if the local and remote IPv4 subnets conflicts you can still use IPv6 ULA addresses (e.g FDxx:xxxx:...) to connect to your services. DNS names make this *much* easier.

## Installation

1. Install dependencies, `ip` and `curl`

	```
	# opkg update
	# opkg install ip
	# opkg install curl
	```
	
2. Download the installer script script to /tmp on your router by running the following command:
	
	```
	# curl -k -o /tmp/ip6neigh_setup.sh https://raw.githubusercontent.com/AndreBL/ip6neigh/master/ip6neigh_setup.sh
	# chmod +x /tmp/ip6neigh_setup.sh
	```

3. Change directory to /tmp, and run `ip6neigh_setup.sh install`

	
	```
	# ./ip6neigh_setup.sh install
	Checking installer version...
	Installer script is up to date.

	Creating directory /usr/share/ip6neigh/
	Downloading ip6neigh_setup.sh
	Downloading main/ip6neigh_svc.sh
	Downloading etc/init.d/ip6neigh
	Downloading etc/hotplug.d/iface/30-ip6neigh
	Downloading etc/config/ip6neigh
	Downloading extra/ip6neigh_oui_download.sh
	Downloading extra/ip6neigh_host_show.sh
	Downloading extra/ip6neigh_ddns.sh

	Not overwriting existing config file /etc/config/ip6neigh.
	The downloaded example config file will be moved to /etc/config/ip6neigh.example.
	Removing directory tree /tmp/ip6neigh/

	--- The installation was successful. ---
	
	Run the following command if you want to download an offline OUI lookup database:

		ip6neigh_oui_download.sh

	Start ip6neigh by running:

		/etc/init.d/ip6neigh start
	```
   
4. (Optional) Edit your current dhcp config file /etc/config/dhcp for adding predefined SLAAC hosts. 

   Examples provided at: [dhcp](https://github.com/AndreBL/ip6neigh/blob/master/etc/config/dhcp)

6. Start ip6neigh...

	manually with

    ```
    /etc/init.d/ip6neigh start
    ```

	or on boot with
	
	```
	/etc/init.d/ip6neigh enable
	sync
	reboot
	```
7. Use names instead of addresses for connecting to IPv6 hosts in your network.

### Uninstalling ip6neigh

ip6neigh can be uninstalled by using the `remove` parameter to the installer:

```
/tmp/ip6neigh_setup.sh remove 
Stopping ip6neigh...

Removing /tmp/hosts/ip6neigh
Removing /tmp/ip6neigh.cache
Removing /etc/hotplug.d/iface/30-ip6neigh
Removing etc/hotplug.d/iface/30-ip6neigh
Removing /etc/init.d/ip6neigh
Removing etc/init.d/ip6neigh
Removing /usr/bin/ip6neigh_ddns.sh
Removing /usr/bin/ip6neigh_host_show.sh
Removing /usr/bin/ip6neigh_oui_download.sh
Removing /usr/bin/ip6neigh_setup.sh
Removing /usr/sbin/ip6neigh_svc.sh
Removing directory tree /usr/share/ip6neigh/

The config file /etc/config/ip6neigh was kept in place for future use. Please remove this file manually if you will not need it anymore.

Finished uninstalling ip6neigh.
```

## Accessing the Host file from the Web (LuCI) 
It is possible to see the host file via the LuCI web interface by using luci-app-commands package. 

1. Install by:

	```
	opkg update
	opkg install luci-app-commands
	```

2. Once installed, add the following to /etc/config/luci

	```
	#ip6neigh commands
	config command
        	option name 'IPv6 Neighbors'
        	option command 'ip6neigh_host_show.sh'

	config command
        	option name 'ip6neigh log'
        	option command 'cat /tmp/log/ip6neigh.log'
	```

3. Now log into the LuCI web interface:

![Figure 1](art/openwrt_login_router.lan.png?raw=true)

4. And Navigate to System->Custom Commands. Clicking on **Run** will display the host file:

![Figure 2](art/ip6neigh_host_show_web.png?raw=true)

5. Or run from CLI

	```
	# ip6neigh_host_show.sh 
	#Predefined                              SLAAC addresses
	fe80::224:a5ff:fed7:3088                 Router.LL.lan 
	2001:470:ebbd:4::1                       Router 

	#Discovered                              IPv6 neighbors
	fe80::5048:e4ff:fe4d:a27d                alarm.LL.lan 
	2001:470:ebbd:4:5048:e4ff:fe4d:a27d      alarm 
	```
	

## Installing MAC OUI lookup feature
`ip6neigh_svc.sh` can use an offline MAC address OUI lookup, if the file `oui.gz` is present. This makes names more readable for clients which do not send their hostname (e.g. the Chromebook) when making a DHCP request.

To install, run `ip6neigh_oui_download.sh` tool, which will install oui.gz for offline oui lookup.


```
#./ip6neigh_oui_download.sh 
Downloading Nmap MAC prefixes...
Connecting to linuxnet.ca (24.222.55.20:80)
oui-raw.txt          100% |***********************************************************************|   552k  0:00:00 ETA

Applying filters...
Compressing database...
Moving the file...

The new compressed OUI database file is at: /usr/share/ip6neigh/oui.gz
```

Hosts which do not send their hostname (e.g. Unknown-9BA.LL.lan) will now have an OUI manufacterer as part of the name, such as Speed-9BA.LL.lan (Speed is a Speed Dragon Multimedia Limited MAC device).

## Troubleshooting

`ip6neigh_svc` should start up after step 6 above. You can check that it is running by typing

```
# ps | grep ip6negh
16727 root      1452 S    {ip6neigh_svc.sh} /bin/sh /usr/sbin/ip6neigh_svc.sh -s
16773 root      1452 S    {ip6neigh_svc.sh} /bin/sh /usr/sbin/ip6neigh_svc.sh -s
16775 root      1356 S    grep ip6
```

You can also check the log file (enabled/disabled in `/etc/config/ip6negh`)

```
# cat /tmp/log/ip6neigh.log
Fri Dec 23 23:44:31 UTC 2016 Starting ip6neigh script for physdev br-lan with domain lan
Fri Dec 23 23:44:31 UTC 2016 Network does not have ULA prefix. Clearing label for GUAs.
Fri Dec 23 23:44:31 UTC 2016 Generating predefined SLAAC addresses for router
Fri Dec 23 23:44:41 UTC 2016 Added: alarm.LL.lan fe80::5048:e4ff:fe4d:a27d
Fri Dec 23 23:44:54 UTC 2016 Added: alarm.TMP.lan 2001:470:ebbd:4:3466:322a:649a:7172
Fri Dec 23 23:44:54 UTC 2016 Probing other possible addresses for alarm: fe80::3466:322a:649a:7172 fe80::5048:e4ff:fe4d:a27d 
..
Tue Dec 27 01:32:17 UTC 2016 Added: Unknown-01e0a4.LL.lan fe80::d69a:20ff:fe01:e0a4
Tue Dec 27 01:32:19 UTC 2016 Added: Unknown-01e0a4.TMP.lan 2001:470:ebbd:4:1d82:c1c3:c2a3:d46b
Tue Dec 27 01:32:19 UTC 2016 Probing other possible addresses for Unknown-01e0a4: fe80::1d82:c1c3:c2a3:d46b fe80::d69a:20ff:fe01:e0a4 
Tue Dec 27 01:32:20 UTC 2016 Added: hau 2001:470:ebbd:4:d69a:20ff:fe01:e0a4
Tue Dec 27 01:32:20 UTC 2016 Probing other possible addresses for hau: fe80::d69a:20ff:fe01:e0a4 
```
   
To list the hostnames detected by **ip6neigh**.

```
# ip6neigh_host_show.sh
#Predefined                              SLAAC addresses
fe80::224:a5ff:fed7:3088                 Router.LL.lan 
2001:470:ebbd:4::1                       Router 
                                          
#Discovered                              IPv6 neighbors
fe80::d69a:20ff:fe01:e0a4                hau.LL.lan 
2001:470:ebbd:4:20ca:43:4559:9da4        hau.TMP.lan 
fe80::5048:e4ff:fe4d:a27d                alarm.LL.lan 
2001:470:ebbd:4:d69a:20ff:fe01:e0a4      hau 
2001:470:ebbd:4:5048:e4ff:fe4d:a27d      alarm 
```

## Dependencies

One only needs to install `ip` and `curl` packages. It has been tested on Chaos Calmer (v15.05.1) of OpenWrt. 

In order to use the LuCI web interface, one must install `luci-app-commands`   

## More Details

ip6neigh is designed to operate in a dual-stack network with both IPv4 and IPv6 running. It will collect host names and return them when queried by DNS.

ip6neigh relies on DHCPv4/client to report its hostname (option 12) or DHCPv6 Client Option . If the client does not report the hostname, then an "Unknown-xxx" name will be applied with *xxx* as the last three bytes of the MAC address. If the offline MAC OUI lookup has been activated (by running the script  ip6neigh_oui_download.sh), then the MAC OUI manufacturer name will be used instead of Unknown.

Names will be discovered in the following order (and priority):

1. Static hosts in /etc/config/dhcp
2. DHCPv6 leases
3. DHCPv4 leases
4. OUI manufacurer-xxx
5. simple Unknown-xxx names.


### Assumptions

ip6neigh_svc.sh assumes that IPv6 subnets are /64 (which is what hosts should see in an IPv6 network for SLAAC to work). It also assumes DHCPv4 and SLAAC environments, but can also work in other environments (such as DHCPv6-only).

## Contributors

The script is written by André Lange. Suggestions, and additions are welcome. Acknowledgements to Craig Miller for debugging and documentation. 

## License

This project is open source, under the GPLv2 license (see [LICENSE](LICENSE))

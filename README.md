## Giving local DNS names to IPv6 SLAAC addresses 
#### OpenWrt shell script

## Synopsis

The purpose of the script is to automatically generate and update IPv6 DNS host names on the OpenWrt router, making access to devices by name (either IPv4 or IPv6) on your network a snap. It does this by creating a hosts file giving local DNS names to IPv6 addresses that IPv6 enabled devices took via SLAAC mechanism.

Rather than using clunky IP addresses (v4 or v6), devices on your network now become:
* router.lan
* mycomputer.lan

or simply
* router
* mycomputer

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
	# curl -k -o /tmp/ip6neigh-setup.sh https://raw.githubusercontent.com/AndreBL/ip6neigh/master/ip6neigh-setup.sh
	# chmod +x /tmp/ip6neigh-setup.sh
	```

3. Change directory to /tmp, and run `ip6neigh-setup.sh install`

	
	```
	# ./ip6neigh-setup.sh install
	Checking installer version...
	The installer script is up to date.

	Creating directory /usr/share/ip6neigh/
	Downloading ip6neigh-setup.sh
	Downloading main/ip6neigh-svc.sh
	Downloading main/ip6neigh.sh
	Downloading etc/init.d/ip6neigh
	Downloading etc/hotplug.d/iface/30-ip6neigh
	Downloading etc/config/ip6neigh
	
	The downloaded example config file will be moved to /etc/config/ip6neigh.example.
	Removing directory tree /tmp/ip6neigh/

	--- The installation was successful. ---
	
	Run the following command if you want to download an offline OUI lookup database:

		ip6neigh oui download

	Start ip6neigh with:

		ip6neigh start
	```
   
4. (Optional) Edit your current dhcp config file /etc/config/dhcp for adding predefined SLAAC hosts. 

   Examples provided at: [dhcp](https://github.com/AndreBL/ip6neigh/blob/master/etc/config/dhcp)

5. Start ip6neigh...

	manually with

    ```
    ip6neigh start
    ```

	or on boot with
	
	```
	ip6neigh enable
	sync
	reboot
	```
6. Use names instead of addresses for connecting to IPv6 hosts in your network.

### Uninstalling ip6neigh

A copy of the installer script will be available in /usr/bin/ after installation. ip6neigh can be uninstalled by passing the `remove` parameter to the installer:

```
# ip6neigh-setup remove
Stopping ip6neigh...

Removing /tmp/hosts/ip6neigh
Removing /tmp/ip6neigh.cache
Removing /etc/hotplug.d/iface/30-ip6neigh
Removing /etc/init.d/ip6neigh
Removing /usr/bin/ip6neigh
Removing /usr/bin/ip6neigh-oui-download
Removing /usr/bin/ip6neigh-setup
Removing /usr/sbin/ip6neigh-svc.sh
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
        	option command 'ip6neigh list'

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
	# ip6neigh list 
	#Predefined hosts
	Router                         2001:470:ebbd:4::1 
	Router.LL.lan                  fe80::224:a5ff:fed7:3088 

	#Discovered hosts
	Speed-9BA                      2001:470:ebbd:4:213:3bff:fe99:19ba 
	Speed-9BA.LL.lan               fe80::213:3bff:fe99:19ba 
	Speed-9BA.TMP.lan              2001:470:ebbd:4:b5e3:1def:443b:f7b9 
	alarm                          2001:470:ebbd:4:5048:e4ff:fe4d:a27d 
	alarm.LL.lan                   fe80::5048:e4ff:fe4d:a27d 
	alarm.TMP.lan                  2001:470:ebbd:4:614b:2c7:27af:6713 
	hau                            2001:470:ebbd:4:d69a:20ff:fe01:e0a4 
	hau.LL.lan                     fe80::d69a:20ff:fe01:e0a4 
	hau.TMP.lan                    2001:470:ebbd:4::46f 

	```

## Using DNS Labels
`ip6neigh` uses DNS labels, which can be thought of as subdomains for the top level domain `lan`. Example DNS labels (in bold) that `ip6neigh` use are:

* Computer.**TMP**.lan (a temporary address)
* Computer.**LL**.lan (a link-local address)
* Computer.**TMP.PUB**.lan (a temporary GUA)
* Computer (no DNS label applied, e.g. a simple name)

DNS Labels used by `ip6neigh` can be configured in `/etc/config/ip6neigh` file.

The rule of thumb for configuring DNS labels is to clear the label for the scope of address that you consider as preferred for local connectivity, and give DNS labels for every other scope of address, providing unique names to *all* IPv6 addresses on the network.
By default, ip6neigh will use simple names (with no label) for non-temporary ULA addresses if the router's LAN interface has an ULA prefix. If no ULA prefix is present, ip6neigh will consider non-temporary GUA addresses as preferred for local connectivity and will give names without labels for them.
	
## Tools

Included is a versatile tool called `ip6negh` which controls most of the functions, starting, stopping, as well as an aid in troubleshooting.

### Help

```
# ip6neigh
ip6neigh Command Line Script

Usage: /usr/bin/ip6neigh COMMAND ...

Command list:
        { start | restart|rst | stop }
        { enable | disable }
        list|lst        [ all | sta[tic] | dis[covered] ]
        addr[ess]       { NAME } [ 1 ]
        name            { ADDRESS }
        res[olve]       { ADDRESS | NAME } [ 1 ]
        who[is|s]       { NAME | ADDRESS | MAC }


```
`ip6neigh` options include:

* `list    [ all | sta[tic] | dis[covered] ]`
With no extra argument: Shows all entries in hosts file, with comments and blank line.
	* `all` Displays all entries in hosts file without comments or blank lines. Can be used for scripting purposes.
	* `static` Displays the static entries in the host file.
	* `discovered` Displays the dynamically learned entries in the host file.
	* This command replaces `ip6neigh_hosts_show.sh`
*  `name    { ADDRESS }`
Displays the FQDN (Fully Qualified Domain Name) for the IPv6 address. Depending on the user configuration in `/etc/config/ip6neigh`, the top level domain will not appear if the host has no DNS label.  
* `address { NAME } [ 1 ]`
Returns the IPv6 addresses for the FQDN. The top level domain name (e.g. 'lan') may be optionally omitted for convenience. Input examples: Laptop, Laptop.PUB, Laptop.PUB.lan, Laptop.TMP 
	* This command has a clean output for external scripting, like supplying the address to DDNS Scripts or to a custom firewall script that generates rules for GUAs based on names because ISP is issuing a dynamic prefix.
It is possible that hosts will have multiple temp addresses and they will have the same FQDN. If the extra argument '1' is supplied, limits the output to the first address associated with that FQDN.
This command replaces `ip6neigh_ddns.sh`
* `mac     { NAME | ADDRESS }`
Shows the MAC address for the FQDN, simple name or IPv6 address. Clean output.
* `host    { NAME | ADDRESS }`
Verbose style output for resolving FQDN to IPv6 addresses or IPv6 address to FQDN. The top level domain name (e.g. 'lan') may be optionally omitted cor convenience and is not expected to be supplied for names that don't have labels.
Input examples for FQDN: Laptop, Laptop.PUB, Laptop.PUB.lan, Laptop.TMP ...
* `whois   { ADDRESS | MAC | NAME }`
Verbose style output for helping to trace a device's SLAAC activity. `whois ipv6_addr` and `whois mac_addr` are designed to identify the device that owns such addresses. If the argument is a name, it is expected to be the simple name that represents the device like 'Laptop' (not a FQDN) and it will list all FQDN names and the corresponding addresses that belong to that device.



`ip6neigh` not only lists the discovered hosts, but also can do name resolution based on name, IPv6 address or even MAC address. Some of the options (such as list, name and address) are specifically designed in assisting the user in other scripting projects, and therefore have very simple (easily parsed) output.



## Installing MAC OUI lookup feature
`ip6neigh-svc.sh` can use an offline MAC address OUI lookup, if the file `oui.gz` is present. This makes names more readable for clients which do not send their hostname (e.g. the Chromebook) when making a DHCP request.

To install, run `ip6neigh oui download` command, which will install oui.gz for offline oui lookup.


```
# ip6neigh oui download 
Downloading Nmap MAC prefixes...
Connecting to linuxnet.ca (24.222.55.20:80)
oui-raw.txt          100% |***********************************************************************|   552k  0:00:00 ETA

Applying filters...
Compressing database...
Moving the file...

The new compressed OUI database file was successfully moved to: /usr/share/ip6neigh/oui.gz
```

Hosts which do not send their hostname (e.g. Unknown-9BA.LL.lan) will now have an OUI manufacterer as part of the name, such as Speed-9BA.LL.lan (Speed is a Speed Dragon Multimedia Limited MAC device).

## Troubleshooting

`ip6neigh-svc.sh` should start up after step 6 above. You can check that it is running by typing

```
# ps | grep ip6negh
16727 root      1452 S    {ip6neigh-svc.sh} /bin/sh /usr/sbin/ip6neigh-svc.sh -s
16773 root      1452 S    {ip6neigh-svc.sh} /bin/sh /usr/sbin/ip6neigh-svc.sh -s
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
# ip6neigh list 
#Predefined hosts
Router                         2001:470:ebbd:4::1 
Router.LL.lan                  fe80::224:a5ff:fed7:3088 

#Discovered hosts
Speed-9BA                      2001:470:ebbd:4:213:3bff:fe99:19ba 
Speed-9BA.LL.lan               fe80::213:3bff:fe99:19ba 
Speed-9BA.TMP.lan              2001:470:ebbd:4:b5e3:1def:443b:f7b9 
alarm                          2001:470:ebbd:4:5048:e4ff:fe4d:a27d 
alarm.LL.lan                   fe80::5048:e4ff:fe4d:a27d 
alarm.TMP.lan                  2001:470:ebbd:4:614b:2c7:27af:6713 
hau                            2001:470:ebbd:4:d69a:20ff:fe01:e0a4 
hau.LL.lan                     fe80::d69a:20ff:fe01:e0a4 
hau.TMP.lan                    2001:470:ebbd:4::46f 
```

## Dependencies

One only needs to install `ip` and `curl` packages. It has been tested on Chaos Calmer (v15.05.1) of OpenWrt. 

In order to use the LuCI web interface, one must install `luci-app-commands`   

## More Details

ip6neigh is designed to operate in a dual-stack network with both IPv4 and IPv6 running. It will collect host names and return them when queried by DNS.

ip6neigh relies on DHCPv4 client to report its hostname (option 12) or DHCPv6 client option 39. If the client does not report the hostname, then an "Unknown-XXX" name will be applied with *XXX* as the last three hex digits of the MAC address. If the offline MAC OUI lookup has been activated (by running the command ip6neigh oui download), then the MAC OUI manufacturer name will be used instead of Unknown.

Names will be discovered in the following order (and priority):

1. Static hosts in /etc/config/dhcp
2. DHCPv6 leases
3. DHCPv4 leases
4. OUI manufacturer-XXX
5. simple Unknown-XXX names.


### Assumptions

ip6neigh-svc.sh assumes that IPv6 subnets are /64 (which is what hosts should see in an IPv6 network for SLAAC to work). It also assumes DHCPv4 and SLAAC environments, but can also work in other environments (such as DHCPv6-only).

## Contributors

The script is written by André Lange. Suggestions, and additions are welcome. Acknowledgements to Craig Miller for debugging and documentation. 

## License

This project is open source, under the GPLv2 license (see [LICENSE](LICENSE))

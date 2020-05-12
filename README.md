## Giving local DNS names to IPv6 SLAAC addresses 
#### OpenWrt/LEDE shell script

## Synopsis

The purpose of the script is to automatically generate and update IPv6 DNS host names on the OpenWrt/LEDE router, making access to devices by name (either IPv4 or IPv6) on your network a snap. It does this by creating a hosts file giving local DNS names to IPv6 addresses that IPv6 enabled devices took via SLAAC mechanism.

Rather than using clunky IP addresses (v4 or v6), devices on your network now become:

* router.lan
* mycomputer.lan

or simply

* router
* mycomputer

## Motivation

IPv6 addresses are difficult to remember. DNS provides an abstraction layer, so that IP addresses do not have to be memorized. There are at least three situations where this set up is useful:

1. When you need to trace some network activity through tcpdump or Realtime Connections page on LuCI and there are lots of IPv6 addresses there and you don't know who or what they belong to.

2. When your ISP delegates a dynamic IPv6 prefix. Using names to refer to hosts will help automatically updating firewall rules and AAAA address records for local hosts on a remote DDNS service.

3. When you are accessing your LAN hosts either locally or remotely through VPN. If the local and remote IPv4 subnets conflicts you can still use IPv6 ULA addresses (e.g FDxx:xxxx:...) to connect to your services. DNS names make this *much* easier.

When using ip6neigh, names are applied to local IPv6 hosts, rather than cryptic IPv6 addresses, such as shown in this OpenWrt Realtime Connections page:

![luci connections](art/luci_connections_names.png?raw=true)

## Installation

1. Install dependencies, `curl` and `ip-full`

	```
	# opkg update
	# opkg install curl ip-full
	```

	**NOTE:** Special procedure for LEDE systems: When using LEDE v17.01.**0**, the `ip-full` package needs to be upgraded to a newer build which has fixed the 'ip monitor' bug. For 17.01.x systems, please navigate to [https://downloads.lede-project.org/snapshots/packages/](https://downloads.lede-project.org/snapshots/packages/) , find your platform directory, download `ip-full_4.4.0-X_platform.ipk` (where X corresponds to the latest version) and install it on the router. For OpenWrt 18.06.x install the package from 17.01.x by navigating to: [http://downloads.openwrt.org/releases/17.01.6/packages/[arch]/base/](http://downloads.openwrt.org/releases/17.01.6/packages).
	
Example for the x86_64 platform:
	
	```
	# cd /tmp
	# wget http://downloads.lede-project.org/snapshots/packages/x86_64/base/ip-full_4.4.0-10_x86_64.ipk
	# opkg remove ip-full
	# opkg install ip-full_4.4.0-10_x86_64.ipk
	# rm ip-full_4.4.0-10_x86_64.ipk
	```

	**Hint:** When copying the download URL from your browser, change `https` to `http` like the example above to allow downloading without having to install CA certificates.
	
	**OpenWrt** releases and LEDE since v17.01.**1** *do not require* upgrading the `ip-full` package version (normal installation by `opkg install ip-full` is enough).
	
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

	Creating directory /usr/lib/ip6neigh/
	Creating directory /usr/share/ip6neigh/
	Downloading ip6neigh-setup.sh
	Downloading lib/ip6addr_functions.sh
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

   Examples of predefined hosts at: [dhcp](etc/config/dhcp)

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
Removing directory tree /usr/lib/ip6neigh/

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
        	option command 'ip6neigh list active'

	config command
        	option name 'ip6neigh log'
        	option command 'ip6neigh logread'
	```

3. Now log into the LuCI web interface:

![Figure 1](art/openwrt_login_router.lan.png?raw=true)

4. And Navigate to System->Custom Commands. Clicking on **Run** will display the host file:

![Figure 2](art/ip6neigh_host_show_web.png?raw=true)

5. Or run from CLI

	```
	# ip6neigh list active
	Chromecast                     fd32:197d:3022:1101:a677:33ff:fe52:45d2
	Chromecast.GUA.lan             2804:7f5:f080:29a2:a677:33ff:fe52:45d2
	Chromecast.LL.lan              fe80::a677:33ff:fe52:45d2
	Chromecast.TMP.GUA.lan         2804:7f5:f080:29a2:1dc9:ae37:c1fb:6bec
	Chromecast.TMP.lan             fd32:197d:3022:1101:1dc9:ae37:c1fb:6bec
	Android-Andre                  fd32:197d:3022:1101:f6f5:24ff:fe9e:5ac7
	Android-Andre.GUA.lan          2804:7f5:f080:29a2:f6f5:24ff:fe9e:5ac7
	Android-Andre.LL.lan           fe80::f6f5:24ff:fe9e:5ac7
	Android-Andre.TMP.GUA.lan      2804:7f5:f080:29a2:7094:bdf0:4911:6bf9
	Android-Andre.TMP.lan          fd32:197d:3022:1101:7094:bdf0:4911:6bf9
	Laptop                         fd32:197d:3022:1101:c4d7:e94:282d:60b1
	Laptop.GUA.lan                 2804:7f5:f080:29a2:c4d7:e94:282d:60b1
	Laptop.LL.lan                  fe80::c4d7:e94:282d:60b1
	Laptop.TMP.GUA.lan             2804:7f5:f080:29a2:a840:ce89:7c91:93bd
	Laptop.TMP.lan                 fd32:197d:3022:1101:4c62:38c9:247d:5b1f

	```

## Using DNS Labels
`ip6neigh` uses DNS labels, which can be thought of as subdomains for the top level domain `lan`. Example DNS labels (in bold) that `ip6neigh` use are:

* Computer.**TMP**.lan (a temporary address)
* Computer.**LL**.lan (a link-local address)
* Computer.**TMP.GUA**.lan (a temporary GUA)
* Computer (no DNS label applied, e.g. a non-temporary ULA)

DNS Labels used by `ip6neigh` can be configured in `/etc/config/ip6neigh` file.

The rule of thumb for configuring DNS labels is to clear with '0' the label for the scope of address that you consider as preferred for local connectivity, and give DNS labels for every other scope of address, providing unique names to *all* IPv6 addresses on the network.
By default, ip6neigh will use simple names (with no label, such as Computer1) for non-temporary ULA addresses if the router's LAN interface has an ULA prefix. If no ULA prefix is present, ip6neigh will consider non-temporary GUA addresses as preferred for local connectivity and will give names without labels for them.

## Customizing ip6neigh configuration
For normal operations, you won't need to do any custom configuration. However, `ip6neigh` is more powerful than just doing DNS resolution for IPv6 hosts.

### Config: Predefined Hosts
ip6neigh will discover new hosts on the LAN and assign them names. But you may want to **predefine** the common hosts or servers on your network. This can be done by editing the `/etc/config/dhcp` file.

Predefined hosts are added to the `/etc/config/dhcp` file using the following:

```
# Example 1: Devices that use standard EUI-64 interface identifiers (IIDs)
# for all scopes:
config host
	option name		'Android-John'
	#Copy the MAC address of the device.
	option mac		'1a:41:8e:83:66:74'
	option slaac	'1'
	option iface	'lan'

```
For Windows machines which do not use RFC 4862 EUI-64 SLAAC addressing (based on the MAC address):

```
# Example 2: Windows machines or other hosts that do not use EUI-64 IIDs, but
# use other static IIDs instead:
config host
	option name		'Laptop-Paul'
	#Copy the MAC address of the device.
	option mac		'2e:36:e7:85:d3:3b'
	#Copy the interface identifier from the link-local address of
	#of the device.
	option slaac	'daa1:4554:747b:1f50'
	option iface	'lan'

```
Addresses with Stable (not Constant) Semantically Opaque IIDs (RFC 7217) cannot be currently added as predefined hosts (MacOS X 10.12, and iOS 10) if the prefix from the ISP is dynamic, as the host portion of the address (the IID) also changes when the prefix changes.

### Configuration: Dynamic DNS (DDNS)
Dynamic DNS utilizes the `ddns-scripts` package. In the usual case for IPv6, ddns-scripts is used to update the router's address into the AAAA record of an external DDNS service. `ip6neigh` allows one to update the DDNS with an arbitrary internal host's address instead of the router's own address.

Providing there is a firewall rule to allow access to the internal host, then running an externally accessible IPv6 server (i.e. web, ftp, RDP) is feasible even when the **delegated prefix** if frequently changed by the ISP.

To accomplish this:

1. Set up the DDNS config at the router to obtain the Host IPv6 address via an external script. Set this script to be the ip6neigh command that will echo the intended host's GUA:

	```
	/usr/bin/ip6neigh addr MyServer.GUA.lan 1
	```

Regardless of prefix changes, `ip6neigh` will keep the IPv6 address up to date by name, and return the correct IPv6 address at the time of DDNS update.


### Configuration: Dynamic Firewall Rules
When ISP changes the prefix, it can be challenging to update the firewall rules to permit external access. `ip6neigh` can also support the dynamic updating of firewall rules, based on DNS names (which remain constant, even though the prefix changes). 

To setup Dynamic Firewall access rules:

1. Set up predefined hosts (see above).
2. Edit /etc/firewall.user and add lines:

	```
	 #ip6neigh
	 touch /tmp/etc/firewall.ip6neigh
	 ip6tables -N wan6_forwarding
	 ip6tables -A forwarding_wan_rule -d 2000::/3 -j wan6_forwarding
	```
3. Edit /etc/config/firewall and right after

	```
    config include
     	   option path '/etc/firewall.user'
	```
	add these two lines:

	```
    config include
            option path '/tmp/etc/firewall.ip6neigh'
	```
4. Create your custom dynamic firewall script /root/ip6neigh_rules.sh using this template:

	```
    #!/bin/sh

    #Initialize the temp firewall script
    TMP_SCRIPT='/tmp/etc/firewall.ip6neigh'
    echo "ip6tables -F wan6_forwarding" > $TMP_SCRIPT

    #Create new rules for dynamic IPv6 addresses here. Example for accepting TCP connections on port 80 on a local server that identifies itself as 'Webserver' through DHCP.
    echo "ip6tables -A wan6_forwarding -d $(ip6neigh addr Webserver.GUA 1) -p tcp --dport 80 -j ACCEPT" >> $TMP_SCRIPT

    #Run the generated temp firewall script
    /bin/sh "$TMP_SCRIPT"
	```
5. Add your /root/ip6neigh_rules.sh script to ip6neigh config file /etc/config/ip6neigh

	```
    list fw_script '/root/ip6neigh_rules.sh'
	```
6. Restart the OpenWrt firewall and ip6neigh:

	```
    /etc/init.d/firewall restart
    ip6neigh restart
    ```
7. Wait a minute and check if the rules were successfully created:

	```
    root@OpenWrt:~# ip6tables -L wan6_forwarding
    Chain wan6_forwarding (1 references)
    target     prot opt source               destination
    ACCEPT     tcp      anywhere             Webserver.GUA.lan     tcp dpt:www
    ```

## Tools

Included is a versatile tool called `ip6neigh` which controls most of the functions, starting, stopping, as well as an aid in troubleshooting.

### Help

```
# ip6neigh
ip6neigh Command Line Script

Usage: /usr/bin/ip6neigh COMMAND ...

Command list:
        { start | restart | stop }
        { enable | disable }
        list            [ all | static | discovered | active | host HOSTNAME ]
        name            { ADDRESS }
        address         { FQDN } [ 1 ]
        mac             { HOSTNAME | ADDRESS }
        oui             { MAC | download }
        resolve         { FQDN | ADDRESS }
        whois           { HOSTNAME | ADDRESS | MAC }
        logread         [ REGEX ]

        --version       Print version information and exit.

Typing shortcuts: rst lst sta dis act hst addr downl res who whos log
```
`ip6neigh` options include:

* `list    [ all | static | discovered | active | host HOSTNAME ]`
With no extra argument: Shows all entries in the hosts file, with comments and blank line.
	* `all` Displays all entries in hosts file without comments or blank lines. May be used for scripting purposes.
	* `static` Displays the static entries in the host file.
	* `discovered` Displays the dynamically discovered hosts in the host file.
	* `active` Displays the entries that have REACHABLE or STALE NUD status in the router's neighbors table. Helps to find out which hosts have been recently online on the network.
	* `host HOSTNAME` Displays the entries that are related to a single host device.
*  `name { ADDRESS }`
Displays the FQDN (Fully Qualified Domain Name) for the IPv6 address. Depending on the user configuration in `/etc/config/ip6neigh`, the top level domain will not appear if the host has no DNS label.  
* `address { NAME } [ 1 ]`
Returns the IPv6 addresses for the FQDN. The top level domain name (e.g. 'lan') may be optionally omitted for convenience. Input examples: Laptop, Laptop.GUA, Laptop.GUA.lan, Laptop.TMP 
	* This command has a clean output for external scripting, like supplying the address to DDNS Scripts or to a custom firewall script that generates rules for GUAs based on names because ISP is issuing a dynamic prefix.
It is possible that hosts will have multiple temp addresses and they will have the same FQDN. If the extra argument '1' is supplied, limits the output to the first address associated with that FQDN.
This command replaces `ip6neigh_ddns.sh`
* `mac { NAME | ADDRESS }`
Shows the MAC address for the host device or address. Clean output.
* `oui { MAC | download }`
Displays the manufacturer name for the supplied MAC address. If the argument is 'download', the local offline OUI database will be installed or updated.
* `resolve { FQDN | ADDRESS }`
Verbose style output for resolving FQDN to IPv6 addresses or IPv6 address to FQDN. The top level domain name (e.g. 'lan') may be optionally omitted cor convenience.
Input examples for FQDN: Laptop, Laptop.GUA, Laptop.GUA.lan, Laptop.TMP ...
* `whois { HOSTNAME | ADDRESS | MAC }`
Displays host name information, related FQDN, MAC address and manufacturer info for the specified host, address or MAC.
* `logread [ REGEX ]`
Prints the ip6neigh log output, passing anything in the optional REGEX argument as the match string to grep command.
* `--version`
Displays version information.

`ip6neigh` not only lists the discovered hosts, but also can do name resolution based on host name, IPv6 address or even MAC address. Some of the options (such as list, name and address) are specifically designed in assisting the user in other scripting projects, and therefore have very simple (easily parsed) output.



## Installing MAC OUI lookup feature
`ip6neigh-svc.sh` can use an offline MAC address OUI lookup, if the file `oui.gz` is present. This makes names more identifiable for clients which do not send their hostname (e.g. the Chromebook) when making a DHCP request.

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

Hosts which do not send their hostname (e.g. Unknown-9BA.LL.lan) will now have an OUI manufacterer name as part of the host name, such as Speed-9BA.LL.lan (Speed is a Speed Dragon Multimedia Limited MAC device).

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
# ip6neigh logread
Fri Dec 23 23:44:31 UTC 2016 Starting ip6neigh script for physdev br-lan with domain lan
Fri Dec 23 23:44:31 UTC 2016 Network does not have ULA prefix. Clearing label for GUAs.
Fri Dec 23 23:44:31 UTC 2016 Generating predefined SLAAC addresses for router
Fri Dec 23 23:44:41 UTC 2016 Added: alarm.LL.lan fe80::5048:e4ff:fe4d:a27d
Fri Dec 23 23:44:54 UTC 2016 Added: alarm.TMP.lan 2001:db8:ebbd:4:3466:322a:649a:7172
Fri Dec 23 23:44:54 UTC 2016 Probing other possible addresses for alarm: fe80::3466:322a:649a:7172 fe80::5048:e4ff:fe4d:a27d 
..
Tue Dec 27 01:32:17 UTC 2016 Added: Unknown-01e0a4.LL.lan fe80::d69a:20ff:fe01:e0a4
Tue Dec 27 01:32:19 UTC 2016 Added: Unknown-01e0a4.TMP.lan 2001:db8:ebbd:4:1d82:c1c3:c2a3:d46b
Tue Dec 27 01:32:19 UTC 2016 Probing other possible addresses for Unknown-01e0a4: fe80::1d82:c1c3:c2a3:d46b fe80::d69a:20ff:fe01:e0a4 
Tue Dec 27 01:32:20 UTC 2016 Added: hau 2001:db8:ebbd:4:d69a:20ff:fe01:e0a4
Tue Dec 27 01:32:20 UTC 2016 Probing other possible addresses for hau: fe80::d69a:20ff:fe01:e0a4 
```
   
To list the hostnames detected by **ip6neigh**.

```
# ip6neigh list 
#Predefined hosts
Router                         fd32:197d:3022:1101::1
Router.GUA.lan                 2804:7f5:f080:29a2::1
Router.LL.lan                  fe80::c66e:1fff:fed6:18c4

#Discovered hosts
Laptop                         fd32:197d:3022:1101:c4d7:e94:282d:60b1
Laptop.GUA.lan                 2804:7f5:f080:29a2:c4d7:e94:282d:60b1
Laptop.LL.lan                  fe80::c4d7:e94:282d:60b1
Laptop.TMP.GUA.lan             2804:7f5:f080:29a2:a840:ce89:7c91:93bd
Laptop.TMP.lan                 fd32:197d:3022:1101:4c62:38c9:247d:5b1f
```

## Dependencies

One only needs to install `ip-full` and `curl` packages. It has been tested on the following router operating systems:

* OpenWrt Chaos Calmer v15.05.1
* OpenWrt Chaos Calmer v15.05
* LEDE v17.01.1
* LEDE v17.01.0 (requires upgrading ip-full package to v4.4.0-9 or later, from the snapshot build)


Additional dependency for 'snooping' mode is `tcpdump`.

In order to use the LuCI web interface, one must install `luci-app-commands`   

## More Details

ip6neigh is designed to operate in a dual-stack network with both IPv4 and IPv6 running. It will collect host names and return them when queried by DNS.

ip6neigh relies on DHCPv4 client to report its hostname (option 12) or DHCPv6 client option 39. If the client does not report the hostname, then an "Unknown-XXX" name will be applied with *XXX* as the last three hex digits of the MAC address. If the offline MAC OUI lookup has been activated (by running the command `ip6neigh oui download`), then the MAC OUI manufacturer name will be used instead of Unknown.

SLAAC addresses are discovered by three methods:

1. Passively monitoring of changes in the reachability status of neighbors that occur in the router's IPv6 neighbors table.
2. If package `tcpdump` is installed and option dad_snoop is set in /etc/config/ip6neigh, the script will listen to Neighbor Solicitation (NS) messages that are part of the Duplicate Address Detection (DAD) process. The new addresses will be discovered as soon as their host joins the network.
3. After discovering any new addresses with the previous methods, ip6neigh will actively check if the host has took more addresses by guessing different Interface Identifiers (IID) that could match that same host and then sending NS messages to those guessed addresses.

Names for the discovered addresses will be learned or generated in the following order (and priority):

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


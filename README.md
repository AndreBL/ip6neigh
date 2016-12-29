## Giving local DNS names to IPv6 SLAAC addresses 
#### OpenWrt shell script

## Synopsis

The purpose of the script is to automatically generate and update IPv6 DNS host names on the OpenWRT router, making access to devices by name (either IPv4 or IPv6) on your network a snap. It does this by creating a hosts file giving local DNS names to IPv6 addresses that IPv6 enabled devices took via SLAAC mechanism.

Rather than using clunky IP addresses (v4 or v6), devices on your network now become:
* router.lan
* mycomputer.lan

## Motivation

IPv6 addresses are difficult to remember. DNS provides an abstraction layer, so that IP addresses do not have to be memorized. There are at least two situations where this set up is useful:

1. When you need to trace some network activity through tcpdump or Realtime Connections page on LuCI and there are lots of IPv6 addresses there and you don't know who/what they belong to.

2. When you are accessing your LAN hosts either locally or remotely through VPN. Even if the local and remote IPv4 subnets conflicts you can still use IPv6 ULA addresses (e.g FDxx:xxxx:...) to connect to your services. DNS names make this *much* easier.

## Installation

1. Create script `/root/ip6neigh_mon.sh` . If you want to store it in a different place, you'll need to change the path in the init.d script.

    Script code is at: [ip6neigh_mon.sh](https://github.com/AndreBL/ip6neigh/blob/master/ip6neigh_mon.sh)
	
	Make it executable with:
	
	```
	chmod +x /root/ip6neigh_mon.sh
	```
2. Create initialization script `/etc/init.d/ip6neigh`

    Script code is at: [ip6neigh](https://github.com/AndreBL/ip6neigh/blob/master/etc/init.d/ip6neigh)

	Make it executable with:
	
	```
	chmod +x /etc/init.d/ip6neigh
	```
3. Create hotplug script `/etc/hotplug.d/iface/30-ip6neigh`

    Script code is at: [30-ip6neigh](https://github.com/AndreBL/ip6neigh/blob/master/etc/hotplug.d/iface/30-ip6neigh)
	
4. Create UCI config file `/etc/config/ip6neigh`

   Example config is at: [ip6neigh](https://github.com/AndreBL/ip6neigh/blob/master/etc/config/ip6neigh)
   
5. (Optional) Edit your current dhcp config file /etc/config/dhcp for adding predefined SLAAC hosts. 

   Examples provided at: [dhcp](https://github.com/AndreBL/ip6neigh/blob/master/etc/config/dhcp)

6. Start it...
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

## Accessing the Host file from the Web (luci) 
It is possible to see the host file via the luci web interface by using luci-app-commands package. 

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
        	option command '/root/ip6neigh_host_show.sh'

	config command
        	option name 'ip6neigh log'
        	option command 'cat /tmp/log/ip6neigh.log'

	```
3. Create script `/root/ip6neigh_host_show.sh` . .

    Script code is at: [ip6neigh_host_show.sh](https://github.com/AndreBL/ip6neigh/blob/master/more/ip6neigh_host_show.sh)
	
	Make it executable with:
	
	```
	chmod +x /root/ip6neigh_host_show.sh
	```


4. Now log into the luci web interface:

![Figure 1](art/openwrt_login_router.lan.png?raw=true)

5. And Navigate to System->Custom Commands. Clicking on **Run** will display the host file:

![Figure 2](art/ip6neigh_host_show_web.png?raw=true)


## Installing MAC OUI lookup feature
`ip6neigh_mon.sh` can use an offline MAC address OUI lookup, if the file `oui.gz` is present.This makes names more readable for clients which do not send their hostname (e.g. the Chromebook) when making a DHCPv4 reqeust.

To install, copy the `oui.gz` file to the router root directory by running `ip6neigh_oui_download.sh` tool


```
cd /root
#./ip6neigh_oui_download.sh 
Downloading file...
Connecting to linuxnet.ca (24.222.55.20:80)
oui-raw.txt          100% |********************************************|   432k  0:00:00 ETA

Filtering database...

Compressing database...

Moving the file...

The new compressed OUI database file is at: /root/oui.gz
# 

```

Hosts which do not send their hostname (e.g. Unknown-9BA.LL.lan) will now have a OUI manufacterer as part of the name, such as Speed-9BA.LL.lan (Speed is a Speed Dragon Multimedia Limited MAC device)

## Troubleshooting

`ip6neigh_mon` should start up after step 6 above. You can check that it is running by typing

```
# ps | grep ip6negh
 3718 root      1356 S    grep ip6neigh
20882 root      1444 S    {ip6neigh_mon.sh} /bin/sh /root/ip6neigh_mon.sh -s
20916 root      1448 S    {ip6neigh_mon.sh} /bin/sh /root/ip6neigh_mon.sh -s
# 
```

You can also check the long file (enabled/disabled in `/etc/config/ip6negh`)

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
# 
```
   
To list the hostnames detected by **ip6neigh**.

```
# /root/ip6neigh_host_show.sh
#Predefined                              SLAAC addresses
fe80::224:a5ff:fed7:3088                 Router.LL.lan 
2001:470:ebbd:4::1                       Router 
                                          
#Discovered                              IPv6 neighbors
fe80::d69a:20ff:fe01:e0a4                hau.LL.lan 
2001:470:ebbd:4:20ca:43:4559:9da4        hau.TMP.lan 
fe80::5048:e4ff:fe4d:a27d                alarm.LL.lan 
2001:470:ebbd:4:d69a:20ff:fe01:e0a4      hau 
2001:470:ebbd:4:5048:e4ff:fe4d:a27d      alarm 
# 
```

## Dependencies

One only needs to install `ip` package. It has been tested on Chaos Calmer (v15.05.1) of OpenWRT. 

In order to use the luci web interface, one must install `luci-app-commands`   

## More Details

ip6neigh is designed to operate in a dual-stack network with both IPv4 and IPv6 running. It will collect host names and return them when queried by DNS.

ip6neigh relies on DHCPv4 client to report its hostname (option 12). If the client does not report the hostname, then an "Unknown-xxx" name will be applied with *xxx* as the last three bytes of the MAC address. If the offline MAC OUI lookup has been activated (by running the script  ip6neigh_oui_download.sh), then the MAC OUI manufacturer name will be used instead of Unknown.


### Assumptions

ip6neigh_mon.sh assumes that IPv6 subnets are /64 (which is what hosts should see in an IPv6 network for SLAAC to work). It also assumes DHCPv4 and SLAAC environments.

## Contributors

The script is written by André Lange. Suggestions, and additions are welcome. Acknowledgements to Craig Miller for debugging and documentation. 

## License

This project is open source, under the GPLv2 license (see [LICENSE](LICENSE))

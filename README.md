## Giving local DNS names to IPv6 SLAAC addresses 
#### OpenWrt shell script

## Synopsis

The purpose of the script is to automatically generate and update a hosts file giving local DNS names to IPv6 addresses that IPv6 enabled devices took via SLAAC mechanism.


## Motivation

IPv6 addresses are difficult to remember. DNS provides an abstraction layer, so that IP addresses do not have to be memorized. There are at least two situations where this set up is useful:

1. When you need to trace some network activity through tcpdump or Realtime Connections page on LuCI and there are lots of IPv6 addresses there and you don't know who/what they belong to.

2. When you are accessing your LAN hosts remotely through VPN. Even if the local and remote IPv4 subnets conflicts you can still use IPv6 ULA addresses to connect to your services. This task becomes much easier if ULAs have names.

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
# cat /tmp/hosts/ip6neigh 
#Predefined SLAAC addresses

#Discovered IPv6 neighbors
fe80::d69a:20ff:fe01:e0a4 hau.LL.lan
fe80::d69a:20ff:fe01:e0a4 hau.LL.lan
fe80::5048:e4ff:fe4d:a27d alarm.LL.lan
fe80::5048:e4ff:fe4d:a27d alarm.LL.lan
2001:470:ebbd:4:e5c6:4e4b:bc3b:df3 alarm.TMP.lan
2001:470:ebbd:4:d69a:20ff:fe01:e0a4 hau.lan
```
   

   

## Contributors

The script is written by André Lange. Suggestions, and additions are welcome. Acknowledgements to Craig Miller for debugging and documentation. 

## License

This project is open source, under the GPLv2 license (see [LICENSE](LICENSE))

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
7. Check the log file:

   ```
   cat /tmp/log/ip6neigh.log
   ```
   
8. Check if your hosts file is being populated:

   ```
   cat /tmp/hosts/ip6neigh
   ```
   
9. Use names instead of addresses for connecting to IPv6 hosts in your network.

## Contributors

The script is written by André L. Suggestions, and additions are welcome.

## License

This project is open source, under the GPLv2 license (see [LICENSE](LICENSE))

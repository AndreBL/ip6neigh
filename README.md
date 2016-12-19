## Giving local DNS names to IPv6 SLAAC addresses 
#### OpenWrt shell script

## Synopsis

The purpose of the script is to automatically generate and update a hosts file giving local DNS names to IPv6 addresses that IPv6 enabled devices took via SLAAC mechanism


## Motivation

IPv6 addresses are difficult to remember. DNS provides an abstraction layer, so that IP addresses do not have to be memorized. There are at least two situations where this set up is useful:

1. When you need to trace some network activity through tcpdump or Realtime Connections page on LuCI and there are lots of IPv6 addresses there and you don't know who/what they belong to.

2. When you are accessing your LAN hosts remotely through VPN. Even if the local and remote IPv4 subnets conflicts you can use IPv6 ULA addresses to connect to your services. It's much easier if the ULAs have names.

## Installation

1. Create script `/root/ip6neigh_mon.sh` . If you want to store it in a different place, you'll need to change the path in the init.d script.

    Script code is at: [https://github.com/AndreBL/ip6neigh/blo … igh_mon.sh](https://github.com/AndreBL/ip6neigh/blo … igh_mon.sh)

2. Create initialization script `/etc/init.d/ip6neigh`

    Script code is at: [https://github.com/AndreBL/ip6neigh/blo … d/ip6neigh](https://github.com/AndreBL/ip6neigh/blo … d/ip6neigh)

	Make it executable with:
	
	```
	chmod +x /etc/init.d/ip6neigh
	```
3. Create hotplug script `/etc/hotplug.d/iface/30-ip6neigh`

    Script code is at: [https://github.com/AndreBL/ip6neigh/blo … 0-ip6neigh](https://github.com/AndreBL/ip6neigh/blo … 0-ip6neigh)

4. Start it...
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

## Contributors

The script is written by Andre L. Suggestions, and additions or suggestions are welcome.

## License

This project is open source, under the GPLv2 license (see [LICENSE](LICENSE))





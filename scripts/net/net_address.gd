class_name NetAddress
extends RefCounted
## Address helpers for the lobby: which of this PC's addresses to show a host's mates,
## and parsing what a joining player types ("1.2.3.4", "1.2.3.4:24566", "host.name").


## This PC's IPv4 addresses on home/office networks (192.168.x, 10.x, 172.16-31.x).
static func lan_addresses() -> Array[String]:
	var out: Array[String] = []
	for ip in IP.get_local_addresses():
		if is_ipv4(ip) and is_private(ip) and not out.has(ip):
			out.append(ip)
	out.sort()
	return out


## Addresses from VPNs like Tailscale or ZeroTier/Radmin that use the 100.64.0.0/10 or
## 25.x ranges. Mates on the same VPN can join on these with no router setup.
static func vpn_addresses() -> Array[String]:
	var out: Array[String] = []
	for ip in IP.get_local_addresses():
		if is_ipv4(ip) and (is_cgnat(ip) or ip.begins_with("25.")) and not out.has(ip):
			out.append(ip)
	out.sort()
	return out


static func is_ipv4(ip: String) -> bool:
	return ip.is_valid_ip_address() and ip.count(".") == 3 and not ":" in ip


static func _octets(ip: String) -> PackedInt32Array:
	var o := PackedInt32Array()
	for part in ip.split("."):
		o.append(int(part))
	return o


## Private (RFC 1918) address: reachable only inside the same network.
static func is_private(ip: String) -> bool:
	if not is_ipv4(ip):
		return false
	var o := _octets(ip)
	return o[0] == 10 or (o[0] == 172 and o[1] >= 16 and o[1] <= 31) or (o[0] == 192 and o[1] == 168)


## Carrier-grade NAT range (100.64.0.0/10). If a router's "internet" address is in here,
## the internet provider shares one public address between customers and port opening
## can't work. Tailscale also hands out addresses in this range.
static func is_cgnat(ip: String) -> bool:
	if not is_ipv4(ip):
		return false
	var o := _octets(ip)
	return o[0] == 100 and o[1] >= 64 and o[1] <= 127


static func is_loopback(ip: String) -> bool:
	return ip.begins_with("127.") or ip == "::1" or ip.to_lower() == "localhost"


## Splits "address[:port]" into [address, port]. Returns [] if it can't be used.
static func parse(text: String, default_port: int) -> Array:
	var t := text.strip_edges().replace(" ", "")
	if t == "":
		return []
	var host := t
	var port := default_port
	# Allow "1.2.3.4:5000" and "name:5000" but leave bare IPv6 alone.
	if t.count(":") == 1:
		var parts := t.split(":")
		host = parts[0]
		if not parts[1].is_valid_int():
			return []
		port = int(parts[1])
	elif t.begins_with("[") and "]:" in t:
		host = t.substr(1, t.find("]") - 1)
		port = int(t.substr(t.find("]:") + 2))
	if host == "" or port < 1 or port > 65535:
		return []
	return [host, port]

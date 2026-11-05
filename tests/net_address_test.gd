extends SceneTree
## Headless checks for joining problems: address parsing, private/shared address
## detection, a join to nowhere timing out with a helpful message, and hosting
## filling in host_info (addresses, router port attempt) without hanging.
## Run: godot --headless --path . --script res://tests/net_address_test.gd

var _fails := 0


func _initialize() -> void:
	await process_frame
	var NA: GDScript = load("res://scripts/net/net_address.gd")  # class names compile before autoloads
	_check(NA.parse("81.2.3.4", 24565) == ["81.2.3.4", 24565], "plain ip")
	_check(NA.parse(" 81.2.3.4:24600 ", 24565) == ["81.2.3.4", 24600], "ip:port")
	_check(NA.parse("pub.example.com:7000", 24565) == ["pub.example.com", 7000], "name:port")
	_check(NA.parse("[::1]:7000", 24565) == ["::1", 7000], "[ipv6]:port")
	_check(NA.parse("", 24565).is_empty(), "empty rejected")
	_check(NA.parse("1.2.3.4:abc", 24565).is_empty(), "bad port rejected")
	_check(NA.is_private("192.168.1.20") and NA.is_private("10.0.0.5") and NA.is_private("172.20.1.1"), "private")
	_check(not NA.is_private("81.2.3.4") and not NA.is_private("172.32.0.1"), "public")
	_check(NA.is_cgnat("100.70.1.2") and not NA.is_cgnat("100.200.1.2"), "cgnat range")

	var net := root.get_node("Net")
	_check(net.join("", "A", 0) != OK, "empty join refused")
	_check("doesn't look right" in net.last_error, "empty join message")

	# Nothing listens here, so the join must give up on its own with advice.
	var failed := [false]
	net.connection_failed.connect(func(): failed[0] = true)
	var start := Time.get_ticks_msec()
	_check(net.join("127.0.0.1:24611", "A", 0) == OK, "join starts")
	while not failed[0] and Time.get_ticks_msec() - start < 40000:
		await process_frame
	var secs := (Time.get_ticks_msec() - start) / 1000.0
	_check(failed[0], "join to nowhere failed")
	_check(secs < net.JOIN_TIMEOUT + 2.0, "join gave up within the timeout (%.1fs)" % secs)
	_check("127.0.0.1 means this computer" in net.last_error, "loopback advice: " + net.last_error)

	_check(net.host("H", 0, 24612) == OK, "host")
	_check(net.host_info.get("port") == 24612 and net.host_info.has("lan"), "host_info filled")
	start = Time.get_ticks_msec()
	while net.host_info.get("upnp") == "trying" and Time.get_ticks_msec() - start < 20000:
		await process_frame
	_check(net.host_info.get("upnp") in ["open", "failed"], "router attempt finished: %s" % net.host_info.get("upnp"))
	net.leave()
	_check(net.host_info.is_empty(), "host_info cleared on leave")

	print("NET ADDRESS %s" % ("OK" if _fails == 0 else "FAILED (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		push_error("FAIL: " + what)

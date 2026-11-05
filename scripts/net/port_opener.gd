class_name PortOpener
extends Node
## Asks the router to open the game's UDP port (UPnP) and looks up the public address,
## so a host's mates can join over the internet without the host editing router settings.
## UPnP discovery blocks for a couple of seconds, so it runs on a thread.
## Net owns one of these; the lobby reads Net.host_info.

signal finished(result: Dictionary)

const DESCRIPTION := "Crown and Punchbowl"
const DISCOVER_TIMEOUT_MS := 2500
const PUBLIC_IP_URL := "https://api.ipify.org"

var _thread: Thread
var _upnp: UPNP
var _port := 0
var _mapped := false
var _close_when_done := false


## Starts opening `port`. Emits finished({"ok", "external_ip", "error"}) on the main thread.
func open(port: int) -> void:
	close()
	_port = port
	_close_when_done = false
	_thread = Thread.new()
	_thread.start(_open_threaded.bind(port))


## Removes the mapping (or arranges for it to be removed if opening is still running).
func close() -> void:
	if _thread and _thread.is_started():
		_close_when_done = true
		return
	if _mapped and _upnp:
		_upnp.delete_port_mapping(_port, "UDP")
	_mapped = false


func is_busy() -> bool:
	return _thread != null and _thread.is_started()


func _open_threaded(port: int) -> Array:
	var result := {"ok": false, "external_ip": "", "error": ""}
	var upnp := UPNP.new()
	var err := upnp.discover(DISCOVER_TIMEOUT_MS, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS:
		result["error"] = "Your router didn't answer an automatic port request (UPnP is off or not supported)."
	elif upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
		result["error"] = "No router that supports automatic port opening was found."
	else:
		result["external_ip"] = upnp.query_external_address()
		var map_err := upnp.add_port_mapping(port, port, DESCRIPTION, "UDP", 0)
		if map_err != UPNP.UPNP_RESULT_SUCCESS:
			# Some routers refuse permanent leases; try a long timed one instead.
			map_err = upnp.add_port_mapping(port, port, DESCRIPTION, "UDP", 4 * 3600)
		if map_err == UPNP.UPNP_RESULT_SUCCESS:
			result["ok"] = true
		else:
			result["error"] = "Your router refused to open port %d automatically (UPnP error %d)." % [port, map_err]
	_finish.call_deferred()
	return [upnp, result]


func _finish() -> void:
	if _thread == null:
		return
	var out: Array = _thread.wait_to_finish()
	_thread = null
	_upnp = out[0]
	var result: Dictionary = out[1]
	_mapped = result["ok"]
	if _close_when_done:
		close()
		return
	finished.emit(result)


## Looks up this connection's public address. Calls back with "" on failure.
func fetch_public_ip(callback: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 6.0
	add_child(req)
	req.request_completed.connect(func(res: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		var ip := body.get_string_from_utf8().strip_edges()
		req.queue_free()
		callback.call(ip if res == HTTPRequest.RESULT_SUCCESS and code == 200 and ip.is_valid_ip_address() else ""))
	if req.request(PUBLIC_IP_URL) != OK:
		req.queue_free()
		callback.call("")


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		var out: Array = _thread.wait_to_finish()
		_thread = null
		_upnp = out[0]
		_mapped = out[1]["ok"]
	_close_when_done = false
	close()

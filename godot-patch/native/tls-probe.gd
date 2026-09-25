## CI diagnostic: does the engine's own HTTPS reach the backend from this machine?
##   godot --headless --script tls-probe.gd
extends SceneTree


func _init() -> void:
	# The tree is not running yet during _init: start the request on the first frame.
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var http := HTTPRequest.new()
	http.timeout = 30.0
	root.add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray):
		print("tls-probe: result %d, HTTP %d" % [result, code])
		quit(0 if result == 0 else 1))
	if http.request("https://api.chikimonsters.com/health") != OK:
		print("tls-probe: could not start")
		quit(1)

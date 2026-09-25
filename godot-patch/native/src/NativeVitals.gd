## HOW THE GAME RUNS ON REAL IPHONES — sent to the backend's /client-diag, the same place the
## web-view app reported its load failures.
##
## The CI simulator has no GPU and runs the game ~20x too slowly to measure anything, so the only
## honest performance numbers come from phones. Once a minute (and 20 s after launch) this posts one
## snapshot of the launch: frame rate (now, average and worst second over the last minute), slow
## frames, memory, GPU memory, draw calls, the quality settings in force, the screen and its safe
## area, and whether the previous launch ended without the app closing cleanly (iOS memory kill or
## crash). Declared in App Privacy as Other Diagnostic Data, not linked: `session` is a random id
## per launch; no account, device id or location is sent.
extends Node

const API := "https://api.chikimonsters.com"
const FIRST_AFTER := 20.0
const EVERY := 60.0
const RUNNING := "user://vitals_running"

var _session := ""
var _started := 0
var _fps_seconds: Array[float] = []
var _slow_frames := 0
var _frames := 0
var _worst_ms := 0.0
var _second := 0.0
var _prev_unclean := false
var _http: HTTPRequest
var _sends := 0


func _ready() -> void:
	if not ChikFeat.native():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session = Crypto.new().generate_random_bytes(8).hex_encode()
	_started = Time.get_ticks_msec()
	_prev_unclean = FileAccess.file_exists(RUNNING)
	var f := FileAccess.open(RUNNING, FileAccess.WRITE)
	if f != null:
		f.store_string(_session)
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = FIRST_AFTER
	t.timeout.connect(func():
		_send()
		t.one_shot = false
		t.wait_time = EVERY
		t.start())
	add_child(t)
	t.start()


func _notification(what: int) -> void:
	# a clean close removes the marker; a launch that finds it knows the last one was killed
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNNING))
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		# backgrounded: iOS may end it there without a crash, so do not count that as unclean
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNNING))
		_send()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		var f := FileAccess.open(RUNNING, FileAccess.WRITE)
		if f != null:
			f.store_string(_session)


func _process(delta: float) -> void:
	_frames += 1
	var ms := delta * 1000.0
	if ms > 50.0:
		_slow_frames += 1
	_worst_ms = maxf(_worst_ms, ms)
	_second += delta
	if _second >= 1.0:
		_fps_seconds.append(Engine.get_frames_per_second())
		if _fps_seconds.size() > 60:
			_fps_seconds.pop_front()
		_second = 0.0


func _send() -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_sends += 1
	var fps_avg := 0.0
	var fps_min := 0.0
	if not _fps_seconds.is_empty():
		fps_min = 1000.0
		for v in _fps_seconds:
			fps_avg += v
			fps_min = minf(fps_min, v)
		fps_avg /= _fps_seconds.size()
	var vp := get_viewport()
	var mn = get_tree().get_first_node_in_group("world_main")
	var mem: Dictionary = OS.get_memory_info()
	var safe := DisplayServer.get_display_safe_area()
	var body := {
		"session": _session,
		"native": true,
		"app": "%s (%s)" % [ProjectSettings.get_setting("application/config/version", "?"), OS.get_name()],
		"model": OS.get_model_name(),
		"ios": OS.get_version(),
		"ramGB": snappedf(float(mem.get("physical", 0)) / 1073741824.0, 0.1),
		"hd": ChikFeat.native_hd(),
		"tier": mn.gfx_tier() if (mn != null and mn.has_method("gfx_tier")) else -1,
		"scale3d": snappedf(vp.scaling_3d_scale, 0.01),
		"screen": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"safe": [safe.position.x, safe.position.y, safe.size.x, safe.size.y],
		"uptime": int((Time.get_ticks_msec() - _started) / 1000),
		"fps": Engine.get_frames_per_second(),
		"fpsAvg60": snappedf(fps_avg, 0.1),
		"fpsMin60": fps_min,
		"slowFrames": _slow_frames,
		"frames": _frames,
		"worstMs": int(_worst_ms),
		"memMB": int(OS.get_static_memory_usage() / 1048576),
		"memPeakMB": int(OS.get_static_memory_peak_usage() / 1048576),
		"vramMB": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576),
		"texMB": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576),
		"drawCalls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"scene": _scene_name(),
		"prevUnclean": _prev_unclean,
		"sends": _sends,
	}
	_slow_frames = 0
	_worst_ms = 0.0
	_http.request(API + "/client-diag", PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, JSON.stringify(body))


func _scene_name() -> String:
	var cs := get_tree().current_scene
	if cs == null:
		return ""
	var s: Script = cs.get_script()
	return s.resource_path.get_file() if s != null else str(cs.name)

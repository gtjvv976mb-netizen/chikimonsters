## HOW THE GAME RUNS ON REAL IPHONES — sent to the backend's /client-diag, the same place the
## web-view app reported its load failures.
##
## The CI simulator has no GPU and runs the game ~20x too slowly to measure anything, so the only
## honest performance numbers come from phones. Once a minute (and 20 s after launch) this posts one
## snapshot of the launch: frame rate (now, average and worst second over the last minute), slow
## frames, memory, GPU memory, draw calls, the quality settings in force, the screen and its safe
## area, and whether the previous launch ended without the app closing cleanly (iOS memory kill or
## crash). Declared in App Privacy (and the export's privacy manifest) as Performance Data, Crash
## Data and Other Diagnostic Data, none linked: `session` is a random id per launch; no account,
## device id or location is sent.
extends Node

const API := "https://api.chikimonsters.com"
const FIRST_AFTER := 20.0
const EVERY := 60.0
const RUNNING := "user://vitals_running"

var _session := ""
var _app := ""  # "1.4 (130)": CI writes it into the pack's override.cfg; empty in a local build
var _started := 0
var _fps_seconds: Array[float] = []
var _slow_frames := 0
var _frames := 0
var _worst_ms := 0.0
var _second := 0.0
var _prev_unclean := false
var _prev_last := {}  # the previous session's last breadcrumb, when it did not close cleanly
var _crumb_t := 0.0
var _http: HTTPRequest
var _sends := 0
var _last_send := -1000000
var _grace := 0.0  # seconds after a return to the foreground that are not sampled


func _ready() -> void:
	# phones only: a desktop test run (CHIK_NATIVE_TEST) or the simulator, whose model is its CPU
	# ("arm64"), would report its own numbers as the app's
	if not ChikFeat.native() or not OS.has_feature("ios") or not OS.get_model_name().begins_with("iP"):
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session = Crypto.new().generate_random_bytes(8).hex_encode()
	_app = str(ProjectSettings.get_setting("application/config/version", ""))
	if _app.is_empty():
		_app = "unversioned"
	_started = Time.get_ticks_msec()
	_prev_unclean = FileAccess.file_exists(RUNNING)
	if _prev_unclean:
		var last = JSON.parse_string(FileAccess.get_file_as_string(RUNNING))
		if last is Dictionary:
			_prev_last = last
	_mark()
	_http = HTTPRequest.new()
	# Long enough for the backend to wake from idle. Polled on the main loop, never threaded: a
	# threaded request's timeout joins its thread on the main thread, and that thread sits in a
	# blocking read until the server answers, so a slow or lost response froze the game.
	_http.timeout = 50.0
	add_child(_http)
	# A launch after one that died reports it now, not in 20 s: a phone that is memory-killed
	# while the world loads would otherwise never get a report out.
	if _prev_unclean:
		_send.call_deferred()
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


## The marker: present only while the game is on screen and active, and holding a breadcrumb of the
## session (uptime, memory, quality level, scene), rewritten every 5 s. A launch that finds it knows
## the last session died in the foreground (a crash or a memory kill) and reports its breadcrumb.
## iPhone's usual close is swipe-up-and-flick in the app switcher: the app only goes INACTIVE
## (focus out) before it is killed, never background, so the marker goes on focus-out too (builds
## 118-121 counted every such close as unclean).
func _mark() -> void:
	var mem: Dictionary = OS.get_memory_info()
	var f := FileAccess.open(RUNNING, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"session": _session, "app": _app, "uptime": int((Time.get_ticks_msec() - _started) / 1000),
			"availMB": int(float(mem.get("available", 0)) / 1048576.0),
			"vramMB": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576),
			"fps": Engine.get_frames_per_second(), "scene": _scene_name(),
			"qualityLevel": get_node("/root/NativeQuality").get("level") if has_node("/root/NativeQuality") else -1,
		}))


func _unmark() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUNNING))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_unmark()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		# inactive: the app switcher, a call, the lock screen; a kill from here is a close. The
		# report is taken now; the main loop stops with focus out, so it leaves on the way back.
		_unmark()
		if Time.get_ticks_msec() - _last_send > 10000:
			_send()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_mark()
		# the first frame back spans the whole time away: not a hitch the player saw
		_grace = 2.0
		_second = 0.0


func _process(delta: float) -> void:
	if _grace > 0.0:
		_grace -= delta
		return
	_frames += 1
	var ms := delta * 1000.0
	if ms > 50.0:
		_slow_frames += 1
	_worst_ms = maxf(_worst_ms, ms)
	_crumb_t += delta
	if _crumb_t >= 5.0:
		_crumb_t = 0.0
		if FileAccess.file_exists(RUNNING):
			_mark()
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
	_last_send = Time.get_ticks_msec()
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
		"app": _app,
		"model": OS.get_model_name(),
		"ios": OS.get_version(),
		"ramGB": snappedf(float(mem.get("physical", 0)) / 1073741824.0, 0.1),
		"hd": ChikFeat.native_hd(),
		"qualityLevel": get_node("/root/NativeQuality").get("level") if has_node("/root/NativeQuality") else -1,
		"availMB": int(float(mem.get("available", 0)) / 1048576.0),
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
		# the engine's own memory counters read 0 in release builds; this is the phone's used RAM
		"sysUsedMB": int(float(mem.get("physical", 0) - mem.get("available", 0)) / 1048576.0),
		"vramMB": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576),
		"texMB": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576),
		"drawCalls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"triangles": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"voxelModelsMeshed": get_node("/root/NativeVoxelMesh").get("converted") if has_node("/root/NativeVoxelMesh") else -1,
		"textureFormat": "astc",
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"scene": _scene_name(),
		"prevUnclean": _prev_unclean,
		"prevLast": _prev_last,
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

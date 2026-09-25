## The smallest iOS app that answers one question: does the engine's own HTTPS work on iOS?
## Built by ios-native.yml's tls-smoke job with the same engine template as the game.
extends Node2D

const TARGETS := [
	["http://neverssl.com/", false],
	["https://api.chikimonsters.com/health", true],
	["https://api.chikimonsters.com/health", false],
	["https://chikimonsters.com/realm/updates.json", false],
	["https://chiki-backend-singapore.onrender.com/health", false],
]


var _label := Label.new()


func _say(line: String) -> void:
	print(line)
	_label.text += line + "\n"


func _ready() -> void:
	# results also on screen, for the CI screenshot and a phone
	_label.position = Vector2(24, 48)
	_label.add_theme_font_size_override("font_size", 22)
	add_child(_label)
	_say("[probe] rng " + Crypto.new().generate_random_bytes(8).hex_encode())
	for t in TARGETS:
		var h := HTTPRequest.new()
		h.timeout = 30.0
		add_child(h)
		if t[1]:
			h.set_tls_options(TLSOptions.client_unsafe())
		var t0 := Time.get_ticks_msec()
		if h.request(t[0]) != OK:
			_say("[probe] %s: could not start" % t[0])
			continue
		var r: Array = await h.request_completed
		_say("[probe] %s%s: result %d, HTTP %d, %d ms" % [t[0], " (no cert check)" if t[1] else "", r[0], r[1], Time.get_ticks_msec() - t0])
		h.queue_free()
	_say("[probe] done")

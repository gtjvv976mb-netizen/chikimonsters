extends Node
## Regression: a signature Sunder's brief Weaken must show the casting card's own 2D art,
## including favored attack cards that have no authored long-form status layer.

const Horde := preload("res://TempleHorde3D.gd")
const Visual := preload("res://TempleAbilityVisual.gd")
const Sprites := preload("res://TempleAbilitySprites.gd")
const Traits := preload("res://ChikimonSpeciesTraits.gd")
const Econ := preload("res://Econ.gd")
var failures := 0
var checks := 0
var game: Node

func install_exact_sidecar_effect(profile: Dictionary) -> void:
	var root := OS.get_environment("CHIKI_SIDECAR_ROOT")
	var spec := Sprites.reborn_stream_spec(profile, "effect")
	check(root != "" and not spec.is_empty(), "exact illustrated sidecar is configured")
	if root == "" or spec.is_empty():
		return
	var path := root.path_join(String(spec.get("path", "")))
	check(FileAccess.file_exists(path), "manifest-owned effect exists: %s" % String(profile.get("key", "")))
	if not FileAccess.file_exists(path):
		return
	var image := Image.new()
	check(image.load(path) == OK, "manifest-owned WebP decodes: %s" % String(profile.get("key", "")))
	if image.is_empty():
		return
	image.convert(Image.FORMAT_RGBA8)
	check(Sprites.install_reborn_image(profile, "effect", image),
		"runtime accepts the exact reviewed effect atlas: %s" % String(profile.get("key", "")))

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL sunder status: ", label)

func status(owner: String) -> Dictionary:
	for value in (game.call("debug_status_visuals") as Dictionary).get("active", []):
		var item := value as Dictionary
		if String(item.get("owner", "")) == owner:
			return item
	return {}

func case(species: String, slot: int, expected_layer: String) -> void:
	check(bool(game.call("debug_restart_with", {"uid": "sunder-%s" % species,
		"species": species, "kind": Econ.unit_kind(species), "level": 1})),
		"%s starts with a real Chikimon" % species)
	game.call("debug_start_wave", 0)
	var foe := (game.get("_enemy_pool") as Array)[0] as Dictionary
	var point := Vector2(game.get("_ppos")) + Vector2(140.0, -35.0)
	game.call("_activate_enemy", foe, point, 0)
	foe["hp"] = float(foe["maxhp"])
	var profile := Visual.profile(species, slot)
	install_exact_sidecar_effect(profile)
	var arch := String((Econ.CARDS[slot] as Dictionary)["arch"])
	check(String((Traits.profile(species) as Dictionary)["signature_arch"]) == arch,
		"%s case exercises its favored card" % species)
	var held := Sprites.reborn_effect_layer_asset(profile, "status")
	if held.is_empty():
		held = Sprites.reborn_effect_layer_asset(profile, "impact")
	check(not held.is_empty(), "%s has an authored status/impact image" % species)
	profile["_trait_status_asset"] = held
	profile["combat_attack_id"] = 7000 + checks
	game.set("_energy", 1.0)
	game.call("_damage_enemy", foe, 0.01, arch, "", profile)
	if arch == "wither":
		check(float(foe["weaken"]) >= 3.4 and float(foe["weaken"]) <= 4.1,
			"%s preserves authored Wither, with a capped Sunder extension" % species)
	else:
		check(is_equal_approx(float(foe["weaken"]), 2.0),
			"%s applies a two-second Weaken, past Hogwert's 1.47s tell and charge" % species)
	var owner := "enemy:%d" % int(foe["eid"])
	var visual := status(owner)
	check(bool(visual.get("visible", false)) and bool(visual.get("has_texture", false)),
		"%s keeps a visible 2D sustained sprite" % species)
	check(String(visual.get("source", "")) == "illustrated_card" \
		and String(visual.get("profile_key", "")) == String(profile.get("key", "")),
		"%s sustained art belongs to the casting card, not a generic sprite" % species)
	check(String(visual.get("asset_layer", "")) == expected_layer,
		"%s uses the expected per-card %s layer" % [species, expected_layer])
	var old_at := visual.get("position", Vector3.ZERO) as Vector3
	foe["p"] = Vector2(foe["p"]) + Vector2(60.0, 20.0)
	var moved := status(owner)
	check((moved.get("position", Vector3.ZERO) as Vector3).distance_to(old_at) > 0.1,
		"%s sustained mark follows the moving corruptimon" % species)
	foe["weaken"] = 0.0
	foe["stun"] = 0.0
	foe["slow"] = 0.0
	game.call("_refresh_status_visuals", 0.0)
	check(status(owner).is_empty(), "%s status image retires when Weaken expires" % species)
	game.call("_deactivate_enemy", foe)

func _ready() -> void:
	game = Horde.new()
	game.call("set_party", [{"uid": "sunder-first", "species": "electrox",
		"kind": "normal", "level": 1}])
	add_child(game)
	await get_tree().process_frame
	game.call("enter", "classic")
	game.call("start_stage")
	await get_tree().process_frame
	game.set_process(false)
	game.set_physics_process(false)
	var sunder_count := 0
	for species_v in Traits.PROFILES.keys():
		var species := String(species_v)
		var trait_profile := Traits.profile(species)
		if String(trait_profile["signature_effect"]) != "sunder":
			continue
		sunder_count += 1
		var favored := String(trait_profile["signature_arch"])
		var slot := -1
		for candidate_v in Econ.unlocked_slots(Econ.unit_kind(species), 1, species, species):
			var candidate := int(candidate_v)
			if String((Econ.CARDS[candidate] as Dictionary)["arch"]) == favored:
				slot = candidate
				break
		check(slot >= 0, "%s Sunder starts in its level-one hand" % species)
		if slot < 0:
			continue
		var authored := Visual.profile(species, slot)
		install_exact_sidecar_effect(authored)
		var layer := Sprites.reborn_effect_layer_asset(authored, "status")
		if layer.is_empty():
			layer = Sprites.reborn_effect_layer_asset(authored, "impact")
		check(not layer.is_empty() and String(layer.get("source", "")) == "illustrated",
			"%s Sunder has its own 2D held-effect source" % species)
	check(sunder_count == 9, "all nine Sunder species are audited")
	# Attack cards with no native status strip derive a single, low-opacity held frame from their
	# own 2D impact image; native status cards retain their authored moving loop.
	case("electrox", 1, "impact")
	case("chloe", 2, "impact")
	case("grovador", 8, "status")
	case("grumpycat", 10, "status")
	var probe: Dictionary = game.call("debug_status_visuals")
	check(int(probe.get("pool_cap", 0)) == 10,
		"all sustained Sunder images reuse the existing ten-slot mobile status pool")
	for sound_v in game.get("_audio_pool"):
		var sound := sound_v as AudioStreamPlayer
		sound.stop()
		sound.stream = null
	await get_tree().create_timer(0.2).timeout
	game.queue_free()
	await get_tree().process_frame
	Sprites.clear_reborn_cache()
	print("TEMPLE_SUNDER_STATUS_QA checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

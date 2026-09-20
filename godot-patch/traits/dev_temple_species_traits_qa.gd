extends SceneTree
## Run with CHIKI_TRAIT_MANIFEST=<absolute server JSON> Godot --headless --path game
## --script res://dev_temple_species_traits_qa.gd. This file is excluded from release exports.

const Econ := preload("res://Econ.gd")
const Traits := preload("res://ChikimonSpeciesTraits.gd")
const Horde := preload("res://TempleHorde3D.gd")
const EFFECTS := ["surge", "recover", "sunder", "fury"]
var failures := 0
var checks := 0

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL trait QA: ", label)

func _initialize() -> void:
	var manifest_path := OS.get_environment("CHIKI_TRAIT_MANIFEST")
	_check(manifest_path != "" and FileAccess.file_exists(manifest_path), "canonical server manifest supplied")
	if failures > 0:
		quit(1)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	_check(parsed is Dictionary, "manifest parses")
	if not parsed is Dictionary:
		quit(1)
		return
	var document := parsed as Dictionary
	var profiles := document.get("profiles", {}) as Dictionary
	var signatures := document.get("signatures", {}) as Dictionary
	_check(Traits.PROFILES.size() == 41 and profiles.size() == 41 and signatures.size() == 41,
		"all 41 species exist on both runtimes")
	for species_v in Traits.PROFILES.keys():
		var species := String(species_v)
		var client_row := Traits.PROFILES[species] as Array
		var server_row := profiles.get(species, []) as Array
		var server_signature := signatures.get(species, []) as Array
		_check(client_row.size() == 8 and server_row.size() == 6 and server_signature.size() == 2,
			"%s rows retain the public schema" % species)
		if client_row.size() != 8 or server_row.size() != 6 or server_signature.size() != 2:
			continue
		for i in range(6):
			_check(client_row[i] == server_row[i], "%s attribute %d matches server" % [species, i])
		_check(client_row[6] == server_signature[0] and client_row[7] == server_signature[1],
			"%s signature matches server" % species)
		_check(EFFECTS.has(String(client_row[7])), "%s has a bounded effect" % species)
		var kind := Econ.unit_kind(species)
		var slots := Econ.unlocked_slots(kind, 1, species, species)
		var unlocked_arches: Array = []
		for slot_v in slots:
			unlocked_arches.append(String((Econ.CARDS[int(slot_v)] as Dictionary).get("arch", "")))
		_check(unlocked_arches.has(String(client_row[6])),
			"%s favored card is usable from level 1" % species)
		_check(Econ.CARD_NAMES.has(species), "%s has authored card names" % species)
	# Exercise the live Temple helper for every species without building 41 rigs or atlases.
	# The signature must fire once on its own card and never from a repeated/AoE contact.
	var horde := Horde.new()
	for species_v in Traits.PROFILES.keys():
		var species := String(species_v)
		var species_profile := Traits.profile(species)
		horde.set("_selected_unit", {"uid": "trait-qa", "species": species,
			"kind": Econ.unit_kind(species), "level": 1})
		horde.set("_species_trait", species_profile)
		horde.set("_trait_proc_ids", [])
		horde.set("_energy", 1.0)
		horde.set("_hp", 80.0)
		horde.set("_max_hp", 100.0)
		horde.set("_heal_bank", 0.0)
		var prior_procs := int(horde.get("_trait_procs"))
		var arch := String(species_profile["signature_arch"])
		var effect := String(species_profile["signature_effect"])
		var cast := {"combat_attack_id": 1000 + checks}
		var foe := {"weaken": 0.0}
		var self_card := arch in ["guard", "charge", "rally", "bulwark"]
		if self_card:
			horde.call("_trait_on_self_cast", arch, cast)
		else:
			horde.call("_trait_on_confirmed_hit", arch, foe, cast)
		_check(int(horde.get("_trait_procs")) == prior_procs + 1,
			"%s favored card triggers once" % species)
		if self_card:
			horde.call("_trait_on_self_cast", arch, cast)
		else:
			horde.call("_trait_on_confirmed_hit", arch, foe, cast)
		_check(int(horde.get("_trait_procs")) == prior_procs + 1,
			"%s repeat contact cannot double-proc" % species)
		var other_arch := "quick" if arch == "strike" else "strike"
		horde.call("_trait_on_confirmed_hit", other_arch, foe,
			{"combat_attack_id": int(cast["combat_attack_id"]) + 1})
		_check(int(horde.get("_trait_procs")) == prior_procs + 1,
			"%s other cards do not borrow the signature" % species)
		match effect:
			"surge": _check(is_equal_approx(float(horde.get("_energy")), 1.25),
				"%s grants bounded energy" % species)
			"recover": _check(is_equal_approx(float(horde.get("_hp")), 84.0),
				"%s restores four HP" % species)
			"sunder": _check(is_equal_approx(float(foe["weaken"]), 2.0),
				"%s opens a two-second weakened window on the first foe" % species)
			"fury": _check(is_equal_approx(float(horde.call("_trait_damage_multiplier", arch, cast)), 1.07),
				"%s grants seven percent to its favored hit" % species)
		_check(is_equal_approx(float(horde.call("_move_speed_multiplier")), float(species_profile["stride"])),
			"%s Stride reaches Temple locomotion" % species)
		_check(is_equal_approx(float(horde.call("_trait_reach")), float(species_profile["reach"])),
			"%s Reach reaches Temple targeting" % species)
		horde.set("_hp", 80.0)
		horde.set("_invuln_t", 0.0)
		horde.set("_shield", 0.0)
		horde.call("_damage_player", 10.0, Vector2.ZERO)
		_check(absf(float(horde.get("_hp")) - (80.0 - 10.0 / float(species_profile["ward"]))) < 0.001,
			"%s Ward applies to an incoming Temple hit" % species)
	horde.free()
	print("TEMPLE_SPECIES_TRAITS_QA checks=%d failures=%d species=%d" % [
		checks, failures, Traits.PROFILES.size()])
	quit(0 if failures == 0 else 1)

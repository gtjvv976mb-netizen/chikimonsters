extends Node
# Focused regression scene for the expanded Wicked Temple horde redesign.
#
# This scene is intentionally isolated from the normal test suite. It reads public debug seams
# where they exist and uses narrowly-scoped deterministic calls for timing/pool invariants that
# cannot be observed from a rendered frame. It never emits or grants a reward.

const Econ := preload("res://Econ.gd")
const AbilityVisual := preload("res://TempleAbilityVisual.gd")
const AbilitySprites := preload("res://TempleAbilitySprites.gd")
const RebornFX := preload("res://RebornCombat.gd")
const HORDE_PATH := "res://TempleHorde3D.gd"

const EXPECTED_PROFILE_COUNT := 402
const EXPECTED_VFX_TEXTURES := 12
const EXPECTED_PACKS_PER_WAVE := 3
const EXPECTED_ACTIVE_CAP := 6
const EXPECTED_PLAYER_HEIGHT_M := 1.42
const EXPECTED_FOE_HEIGHT_M := 1.12
const EXPECTED_DARKEON_HEIGHT_M := 1.24
const EXPECTED_BOSS_HEIGHT_M := 1.62
const EXPECTED_PLAYER_WALK_STRIDE_PX := 72.0
const EPS := 0.002

var _game: Node = null
var _fails := 0
var _phone := false


func _ok(condition: bool, message: String) -> void:
	print(("ok:   " if condition else "FAIL: ") + message)
	if not condition:
		_fails += 1


func _near(a: float, b: float, epsilon: float = EPS) -> bool:
	return absf(a - b) <= epsilon


func _frames(count: int = 2) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _unit(kind: String = "normal") -> Dictionary:
	return {"uid": "redesign-regression", "species": "firix", "kind": kind, "level": 50}


func _state() -> Dictionary:
	var value: Variant = _game.call("debug_state") if _game != null else {}
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _constants() -> Dictionary:
	if _game == null or _game.get_script() == null:
		return {}
	return (_game.get_script() as Script).get_script_constant_map()


func _enemy_pool() -> Array:
	var value: Variant = _game.get("_enemy_pool") if _game != null else []
	return value as Array if value is Array else []


func _deactivate_minions_until(limit: int) -> void:
	var live := 0
	for value in _enemy_pool():
		var enemy := value as Dictionary
		if not bool(enemy.get("active", false)):
			continue
		live += 1
		if live > limit:
			_game.call("_deactivate_enemy", enemy)


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_phone = OS.get_environment("CHIK_FORCEPHONE") == "1"
	print("=== WICKED TEMPLE REDESIGN REGRESSION · %s ===" % ("PHONE" if _phone else "HD"))
	_test_ability_profiles()
	await _spawn_game()
	if _game == null:
		print("TEMPLE_HORDE_REDESIGN_DONE profile=%s fails=%d" % ["phone" if _phone else "hd", _fails])
		get_tree().quit(1)
		return

	_test_reborn_card_renderer()
	_test_expanded_world_and_route()
	_test_reference_art_contract()
	_test_visual_heights()
	_test_projectile_pool_reveal_order()
	_test_reinforcement_director()
	_test_travel_target()
	_test_malformed_rarity()
	_test_one_tap_and_release_timing()
	_test_boss_parity_contract()
	_test_collision_resolved_gait()

	print("TEMPLE_HORDE_REDESIGN_DONE profile=%s fails=%d" % ["phone" if _phone else "hd", _fails])
	_game.queue_free()
	_game = null
	await _frames(3)
	get_tree().quit(1 if _fails > 0 else 0)


func _spawn_game() -> void:
	var HordeScript: Script = load(HORDE_PATH)
	_ok(HordeScript != null, "TempleHorde3D parses and loads in the %s profile" % ("phone" if _phone else "HD"))
	if HordeScript == null:
		return
	_game = HordeScript.new()
	_ok(_game is Node3D, "the redesign still renders through the real Temple3D world")
	if not (_game is Node3D):
		_game.free()
		_game = null
		return
	_game.call("set_party", [_unit()])
	add_child(_game)
	await _frames(1)
	_game.call("enter", "classic")
	await _frames(2)
	_game.call("start_stage")
	await _frames(2)
	_game.set_process(false)
	_game.set_physics_process(false)
	var state := _state()
	_ok(String((state.get("caps", {}) as Dictionary).get("profile", "")) == ("phone" if _phone else "hd"),
		"the scene exercised the requested %s runtime path" % ("forced-phone" if _phone else "HD"))


func _test_ability_profiles() -> void:
	print("--- 402 card-specific visual profiles / 12 shared stamps ---")
	AbilityVisual.clear_texture_cache()
	var seen := {}
	var profiles: Array = []
	var valid := true
	var timing_valid := true
	var identity_valid := true
	for species_value in Econ.CARD_NAMES.keys():
		var species := String(species_value)
		var names := Econ.CARD_NAMES[species] as Array
		for slot in range(mini(names.size(), Econ.CARDS.size())):
			var profile := AbilityVisual.profile(species, slot)
			profiles.append(profile)
			valid = valid and not profile.is_empty()
			identity_valid = identity_valid and String(profile.get("key", "")) == "%s:%d" % [species, slot] \
				and String(profile.get("card_name", "")) != "" \
				and String(profile.get("delivery", "")) != "" \
				and String(profile.get("motif", "")) != ""
			timing_valid = timing_valid and float(profile.get("release", 0.0)) > 0.0 \
				and float(profile.get("duration", 0.0)) > float(profile.get("release", 0.0))
			seen[String(profile.get("key", ""))] = true
	_ok(AbilityVisual.profile_count() == EXPECTED_PROFILE_COUNT and profiles.size() == EXPECTED_PROFILE_COUNT,
		"every one of the 402 authored card/species pairs has a profile")
	_ok(valid and identity_valid and seen.size() == EXPECTED_PROFILE_COUNT,
		"all card profiles preserve unique species, slot, name, delivery, and motif identity")
	_ok(timing_valid, "every card profile has a positive release tell followed by contact/recovery")
	_ok(AbilityVisual.texture_count() == 0,
		"enumerating all 402 profiles allocates no VFX textures eagerly")
	var textures_valid := true
	for profile_value in profiles:
		var texture := AbilityVisual.texture_for_profile(profile_value as Dictionary)
		textures_valid = textures_valid and texture != null and texture.get_width() == 64 \
			and texture.get_height() == 64
	var keys := AbilityVisual.texture_keys()
	_ok(textures_valid and AbilityVisual.texture_count() == EXPECTED_VFX_TEXTURES and keys.size() == EXPECTED_VFX_TEXTURES,
		"402 cards share exactly twelve crisp 64×64 archetype stamps")


func _test_unique_card_renderer() -> void:
	print("--- per-creature / per-card renderer identity ---")
	_game.call("_clear_transient_pools")
	_game.call("_deactivate_all_projectiles")
	var center := Vector2(_game.get("_ppos"))
	var first := AbilityVisual.profile("firix", 0)
	var second := AbilityVisual.profile("borealon", 0)
	var first_signature: Texture2D = AbilityVisual.signature_texture_for_profile(first)
	var second_signature: Texture2D = AbilityVisual.signature_texture_for_profile(second)
	_ok(not first.is_empty() and not second.is_empty() \
		and String(first.get("arch", "")) == String(second.get("arch", "")) \
		and first_signature != null and second_signature != null and first_signature != second_signature,
		"two creatures using the same archetype still own different exact card crests")

	_game.call("_profile_effect", center, first, "impact")
	var effect_pool := _game.get("_effect_pool") as Array
	var first_layers := 0
	var first_archetype := 0
	var first_delivery := 0
	var first_unique := 0
	var first_shock := 0
	for value in effect_pool:
		var effect := value as Dictionary
		if not bool(effect.get("active", false)):
			continue
		first_layers += 1
		var node := effect.get("node") as Sprite3D
		if String(effect.get("profile_key", "")) == String(first.get("key", "")) \
				and String(effect.get("layer_role", "")) == "shock_impact":
			first_shock += 1
		if String(effect.get("profile_key", "")) == String(first.get("key", "")) \
				and String(effect.get("layer_role", "")) == "runtime_archetype_impact" \
				and node != null and node.texture == AbilitySprites.archetype_texture_for_profile(first):
			first_archetype += 1
		if String(effect.get("profile_key", "")) == String(first.get("key", "")) \
				and String(effect.get("layer_role", "")) == "runtime_delivery_impact" \
				and node != null and node.texture == AbilitySprites.delivery_texture_for_profile(first):
			first_delivery += 1
		if String(effect.get("profile_key", "")) == String(first.get("key", "")) \
				and String(effect.get("layer_role", "")) == "signature_impact" \
				and node != null and node.texture == first_signature:
			first_unique += 1
	# Four named layers: two compact animated masters, the exact card crest, and the impact ring.
	# Archetype preserves combat readability; delivery distinguishes how this card reaches its target.
	_ok(first_layers == 4 and first_archetype == 1 and first_delivery == 1 \
		and first_unique == 1 and first_shock == 1,
		"an instant card layers animated archetype/delivery art, its exact crest, and one shockwave")

	# A directional delivery is drawn pointing right in source art. Prove a north-facing cast turns
	# the sheet north and that the seed offset remains only a small, deterministic accent.
	_game.call("_clear_transient_pools")
	_game.set("_face_dir", Vector2.UP)
	_game.call("_profile_effect", center, first, "gather")
	var oriented_delivery := 0
	var expected_angle := float(_game.call("_runtime_sheet_angle", Vector2.UP)) \
		+ (float(int(first.get("seed", 0)) % 19) - 9.0) * 0.008
	for value in effect_pool:
		var effect := value as Dictionary
		var node := effect.get("node") as Sprite3D
		if bool(effect.get("active", false)) \
				and String(effect.get("layer_role", "")) == "runtime_delivery_gather" \
				and node != null and absf(node.rotation.z - expected_angle) <= EPS \
				and is_zero_approx(float(effect.get("fx_spin", 1.0))):
			oriented_delivery += 1
	_ok(oriented_delivery == 1,
		"directional delivery art points along the cast vector without rotating sideways")

	# Dirty every dynamic field that previously leaked through the pool, release it, and inspect the
	# exact inactive slot. Generic dodge/trail/shock effects must start from these clean defaults.
	var pool_reset_ok := false
	for value in effect_pool:
		var effect := value as Dictionary
		if not bool(effect.get("active", false)):
			continue
		effect["peak_alpha"] = 0.2; effect["fx_travel"] = 9.0; effect["fx_rise"] = 9.0
		effect["fx_spin"] = 9.0; effect["fx_arc"] = 9.0; effect["fx_pop"] = 9.0
		effect["fx_el"] = {"flick": 1.0}; effect["fx_vec"] = Vector2.ONE
		_game.call("_release_effect", effect)
		var node := effect.get("node") as Sprite3D
		pool_reset_ok = not bool(effect.get("active", true)) \
			and not bool(effect.get("sprite_sheet", true)) \
			and is_equal_approx(float(effect.get("peak_alpha", 0.0)), 1.0) \
			and is_zero_approx(float(effect.get("fx_travel", 1.0))) \
			and is_zero_approx(float(effect.get("fx_rise", 1.0))) \
			and is_zero_approx(float(effect.get("fx_spin", 1.0))) \
			and is_zero_approx(float(effect.get("fx_arc", 1.0))) \
			and is_equal_approx(float(effect.get("fx_pop", 0.0)), 1.0) \
			and (effect.get("fx_el", {}) as Dictionary).is_empty() \
			and node != null and node.material_override == null and not node.region_enabled \
			and node.texture == (_game.get("_orb_tex") as Texture2D)
		break
	_ok(pool_reset_ok, "pooled ability sprites clear all sheet, material, and motion state on release")

	_game.call("_clear_transient_pools")
	_game.call("_profile_effect", center, second, "gather")
	var second_unique := 0
	for value in effect_pool:
		var effect := value as Dictionary
		var node := effect.get("node") as Sprite3D
		if bool(effect.get("active", false)) \
				and String(effect.get("profile_key", "")) == String(second.get("key", "")) \
				and String(effect.get("layer_role", "")) == "signature_gather" \
				and node != null and node.texture == second_signature:
			second_unique += 1
	_ok(second_unique == 1,
		"switching creatures switches the live gather effect to that creature's card crest")

	# Projectile deliveries use the exact crest as their moving core while the bounded trail keeps
	# the archetype's larger silhouette. No extra nodes or texture atlases are created.
	_game.call("_deactivate_all_projectiles")
	var projectile_profile := AbilityVisual.profile("firix", 1)
	var projectile_signature: Texture2D = AbilityVisual.signature_texture_for_profile(projectile_profile)
	_game.call("_player_projectile", {}, 1.0, String(projectile_profile.get("arch", "blast")),
		Econ.CARDS[1] as Dictionary, 0, projectile_profile)
	var projectiles := _game.get("_projectile_pool") as Array
	var signature_projectiles := 0
	for value in projectiles:
		var projectile := value as Dictionary
		var node := projectile.get("node") as Sprite3D
		if bool(projectile.get("active", false)) and bool(projectile.get("signature_core", false)) \
				and String(projectile.get("visual_id", "")) == String(projectile_profile.get("visual_id", "")) \
				and node != null and node.texture == projectile_signature:
			signature_projectiles += 1
	_ok(signature_projectiles == 1,
		"a travelling ability carries its exact card crest as the visible projectile core")
	_game.call("_deactivate_all_projectiles")
	_game.call("_clear_transient_pools")
	var sprite_cache := AbilitySprites.cache_report()
	_ok(AbilityVisual.total_texture_count() <= AbilityVisual.total_texture_cache_limit() \
		and int(sprite_cache.get("count", 999)) <= int(sprite_cache.get("limit", -1)) \
		and int(sprite_cache.get("material_count", 999)) <= int(sprite_cache.get("count", -1)),
		"procedural identity and animated-master caches both stay inside their mobile budgets")


func _test_reborn_card_renderer() -> void:
	print("--- Reborn exact-card atlas / semantic projectile renderer ---")
	_game.call("_clear_transient_pools")
	_game.call("_deactivate_all_projectiles")
	var center := Vector2(_game.get("_ppos"))
	var first := AbilityVisual.profile("firix", 0)
	var second := AbilityVisual.profile("borealon", 0)
	var first_asset := AbilitySprites.reborn_effect_asset(first)
	var second_asset := AbilitySprites.reborn_effect_asset(second)
	_ok(not first_asset.is_empty() and not second_asset.is_empty()
		and first_asset.get("texture") != second_asset.get("texture")
		and first_asset.get("cell", Vector2i.ZERO) == Vector2i(160, 160),
		"different creature/cards bind different exact transparent 160px effect atlases")

	_game.call("_profile_effect", center, first, "impact")
	var effect_pool := _game.get("_effect_pool") as Array
	var atlas_layers := 0
	var shock_layers := 0
	var obsolete_marks := 0
	for value in effect_pool:
		var effect := value as Dictionary
		if not bool(effect.get("active", false)):
			continue
		var role := String(effect.get("layer_role", ""))
		var node := effect.get("node") as Sprite3D
		if role == "reborn_atlas_impact" and node != null \
				and node.texture == first_asset.get("texture") and node.region_enabled:
			atlas_layers += 1
		if role == "reborn_shock_impact" and node != null \
				and node.texture == RebornFX.texture("ring"):
			shock_layers += 1
		if role.begins_with("signature_") or role.begins_with("runtime_") \
				or role.begins_with("archetype_"):
			obsolete_marks += 1
	_ok(atlas_layers == 1 and shock_layers == 1 and obsolete_marks == 0,
		"impact shows one exact card sequence plus one readable contact ring and no encoded crest")

	_game.call("_clear_transient_pools")
	_game.set("_face_dir", Vector2.UP)
	_game.call("_profile_effect", center, first, "gather")
	var oriented_atlas := 0
	for value in effect_pool:
		var effect := value as Dictionary
		var node := effect.get("node") as Sprite3D
		if bool(effect.get("active", false)) \
				and String(effect.get("layer_role", "")) == "reborn_atlas_gather" \
				and node != null and node.texture == first_asset.get("texture") \
				and absf(node.rotation.z - float(_game.call("_runtime_sheet_angle", Vector2.UP))) <= EPS:
			oriented_atlas += 1
	_ok(oriented_atlas == 1,
		"directional exact art points along the cast vector without rotating sideways")

	var pool_reset_ok := false
	for value in effect_pool:
		var effect := value as Dictionary
		if not bool(effect.get("active", false)):
			continue
		effect["peak_alpha"] = 0.2
		effect["fx_travel"] = 9.0
		effect["fx_rise"] = 9.0
		effect["fx_spin"] = 9.0
		_game.call("_release_effect", effect)
		var node := effect.get("node") as Sprite3D
		pool_reset_ok = not bool(effect.get("active", true)) \
			and not bool(effect.get("sprite_sheet", true)) \
			and is_equal_approx(float(effect.get("peak_alpha", 0.0)), 1.0) \
			and is_zero_approx(float(effect.get("fx_travel", 1.0))) \
			and is_zero_approx(float(effect.get("fx_rise", 1.0))) \
			and is_zero_approx(float(effect.get("fx_spin", 1.0))) \
			and node != null and node.material_override == null and not node.region_enabled \
			and node.texture == (_game.get("_orb_tex") as Texture2D)
		break
	_ok(pool_reset_ok, "pooled exact-card sprites clear texture/material/motion state on release")

	_game.call("_clear_transient_pools")
	_game.call("_profile_effect", center, second, "gather")
	var second_exact := 0
	for value in effect_pool:
		var effect := value as Dictionary
		var node := effect.get("node") as Sprite3D
		if bool(effect.get("active", false)) \
				and String(effect.get("profile_key", "")) == String(second.get("key", "")) \
				and String(effect.get("layer_role", "")) == "reborn_atlas_gather" \
				and node != null and node.texture == second_asset.get("texture"):
			second_exact += 1
	_ok(second_exact == 1,
		"switching creatures switches the live gather sequence to that exact card atlas")

	_game.call("_deactivate_all_projectiles")
	var projectile_profile := AbilityVisual.profile("firix", 1)
	_game.call("_player_projectile", {}, 1.0, String(projectile_profile.get("arch", "blast")),
		Econ.CARDS[1] as Dictionary, 0, projectile_profile)
	var projectiles := _game.get("_projectile_pool") as Array
	var semantic_projectiles := 0
	for value in projectiles:
		var projectile := value as Dictionary
		var node := projectile.get("node") as Sprite3D
		var expected_shape := RebornFX.delivery_shape(projectile_profile)
		if bool(projectile.get("active", false)) \
				and not bool(projectile.get("signature_core", true)) \
				and String(projectile.get("reborn_shape", "")) == expected_shape \
				and node != null and node.texture == RebornFX.texture(expected_shape):
			semantic_projectiles += 1
	_ok(semantic_projectiles == 1,
		"travelling attacks use their clean delivery silhouette rather than a floating catalogue mark")
	_game.call("_deactivate_all_projectiles")
	_game.call("_clear_transient_pools")
	var reborn_cache := AbilitySprites.reborn_status()
	var fallback_cache := RebornFX.cache_report()
	_ok(int(reborn_cache.get("texture_count", 999)) <= int(reborn_cache.get("cache_limit", -1))
		and int(fallback_cache.get("textures", 999)) <= int(fallback_cache.get("limit", -1)),
		"exact atlases and semantic fallback masks both stay inside mobile cache budgets")


func _test_expanded_world_and_route() -> void:
	print("--- expanded continuous temple and authored route ---")
	var world := _game.call("debug_world_metrics") as Dictionary
	var bounds := world.get("gameplay_bounds", Rect2()) as Rect2
	var wing_m := world.get("wing_m", Vector2.ZERO) as Vector2
	var hall_m := world.get("hall_m", Vector2.ZERO) as Vector2
	_ok(bounds.size.x >= 4200.0 and bounds.size.y >= 1240.0 and wing_m.x >= 17.0 and wing_m.y >= 22.0,
		"the playable temple spans at least 4,200×1,240 px with 17×22 m continuous wings")
	_ok(hall_m.x >= 43.0 and hall_m.y >= 22.0,
		"the original 43 m main hall remains the route spine instead of being replaced by a small box")

	var constants := _constants()
	var arenas_v: Variant = constants.get("ARENAS", [])
	var arenas := arenas_v as Array if arenas_v is Array else []
	_ok(arenas.size() == 5, "five distinct sanctums form one continuous combat route")
	var regions := _game.call("gameplay_regions") as Array
	var route_length := 0.0
	var centers: Array[Vector2] = []
	var sizes_valid := arenas.size() == 5
	var centers_walkable := arenas.size() == 5
	for i in range(arenas.size()):
		var arena := arenas[i] as Dictionary
		var rect := arena.get("rect", Rect2()) as Rect2
		var center := arena.get("center", Vector2.ZERO) as Vector2
		centers.append(center)
		if i < 4:
			sizes_valid = sizes_valid and rect.size.x >= 800.0 and rect.size.y >= 620.0
		else:
			sizes_valid = sizes_valid and rect.size.x >= 1400.0 and rect.size.y >= 880.0
		var walkable := false
		for region_value in regions:
			if (region_value as Rect2).has_point(center):
				walkable = true
				break
		centers_walkable = centers_walkable and walkable
		if i > 0:
			route_length += centers[i - 1].distance_to(center)
	_ok(sizes_valid, "side sanctums are at least 800×620 px and the boss floor is at least 1,400×880 px")
	_ok(centers_walkable, "every sanctum center lies inside the shared Temple3D navigation regions")
	_ok(route_length >= 5900.0, "the five-sanctum route provides nearly 6,000 px of traversal between fights")

	var connectors_v: Variant = world.get("connectors", [])
	var connectors := connectors_v as Array if connectors_v is Array else []
	var west := world.get("west_wing", Rect2()) as Rect2
	var east := world.get("east_wing", Rect2()) as Rect2
	var hall := Rect2(96.0, 176.0, 2208.0, 1160.0)
	var seams_valid := connectors.size() == 4
	for i in range(connectors.size()):
		var connector := connectors[i] as Rect2
		var wing := west if i < 2 else east
		seams_valid = seams_valid and connector.intersects(wing, true) and connector.intersects(hall, true)
	_ok(seams_valid, "all four wing connectors overlap both hall and wing, leaving no navigation seam")


func _test_reference_art_contract() -> void:
	print("--- reference-matched temple art / mobile lighting budget ---")
	var floor_art := load("res://wicked_temple_floor_v2.png") as Texture2D
	var wall_art := load("res://wicked_temple_wall_v2.png") as Texture2D
	_ok(floor_art != null and floor_art.get_width() == 1024 and floor_art.get_height() == 1024,
		"the premium 1024px violet-charcoal flagstone material is present")
	_ok(wall_art != null and wall_art.get_width() == 1024 and wall_art.get_height() == 1024,
		"the premium 1024px stacked-temple masonry material is present")

	var floor_used := false
	var wall_used := false
	var cyan_emissive := 0
	var violet_emissive := 0
	var dynamic_lights := 0
	var visible_transparent := 0
	var stack: Array[Node] = [_game]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		for child in node.get_children():
			stack.append(child as Node)
		if node is Light3D:
			dynamic_lights += 1
		if node is Sprite3D and (node as Sprite3D).is_visible_in_tree():
			visible_transparent += 1
		var material: StandardMaterial3D = null
		var visual_instances := 1
		if node is MeshInstance3D:
			material = (node as MeshInstance3D).material_override as StandardMaterial3D
		elif node is MultiMeshInstance3D:
			var multi_instance := node as MultiMeshInstance3D
			material = multi_instance.material_override as StandardMaterial3D
			visual_instances = multi_instance.multimesh.instance_count \
				if multi_instance.multimesh != null else 0
		else:
			continue
		if material == null:
			continue
		var texture := material.albedo_texture
		if texture != null:
			floor_used = floor_used or texture.resource_path.ends_with("wicked_temple_floor_v2.png")
			wall_used = wall_used or texture.resource_path.ends_with("wicked_temple_wall_v2.png")
		if material.emission_enabled:
			var color := material.emission
			if color.g > 0.55 and color.b > 0.65 and color.r < 0.35:
				cyan_emissive += visual_instances
			if color.r > 0.35 and color.b > 0.55 and color.g < 0.55:
				violet_emissive += visual_instances

	_ok(floor_used and wall_used,
		"the generated floor and wall art is bound to real 3D mesh materials, not a flat backdrop")
	_ok(cyan_emissive >= 2 and violet_emissive >= 2,
		"cyan channels and violet corruption are both authored as reusable emissive geometry")
	_ok(dynamic_lights <= (2 if _phone else 4),
		"dynamic lights stay inside the %s reference-art budget (%d live)" % [
			"phone" if _phone else "HD", dynamic_lights])
	_ok(visible_transparent <= (40 if _phone else 48),
		"visible transparent cards, flames, and glows remain bounded (%d)" % visible_transparent)
	_ok(not bool(_game.call("_show_decorative_sanctum_seals")),
		"the horde renderer does not restore nonfunctional decorative floor seals")


func _rig_metrics(rig: Node) -> Dictionary:
	if rig != null and rig.has_method("visual_metrics"):
		var value: Variant = rig.call("visual_metrics")
		return value as Dictionary if value is Dictionary else {}
	return {}


func _test_visual_heights() -> void:
	print("--- normalized 2D silhouette scale in the 3D world ---")
	var player_rig := _game.find_child("PlayerSpeciesRig", true, false)
	var player := _rig_metrics(player_rig)
	_ok(bool(player.get("valid", false)) and _near(float(player.get("normalized_visible_height_m", 0.0)), EXPECTED_PLAYER_HEIGHT_M),
		"the player's painted silhouette is normalized to 1.42 m regardless of atlas padding")
	_ok(float(player.get("alpha_scissor_threshold", 1.0)) <= 0.04,
		"soft sprite edges survive the alpha cut instead of losing limbs or outlines")

	var foes_valid := true
	var foe_count := 0
	for value in _enemy_pool():
		var enemy := value as Dictionary
		var species := String(enemy.get("species", ""))
		var metrics := _rig_metrics(enemy.get("rig") as Node)
		var expected := EXPECTED_DARKEON_HEIGHT_M if species == "darkeon" else EXPECTED_FOE_HEIGHT_M
		foes_valid = foes_valid and bool(metrics.get("valid", false)) \
			and _near(float(metrics.get("normalized_visible_height_m", 0.0)), expected)
		foe_count += 1
	var expected_pool := int(_constants().get("PHONE_FOES" if _phone else "MAX_FOES", -1))
	_ok(foes_valid and foe_count == expected_pool,
		"all %d pooled corrupted sprites use the 1.12 m / 1.24 m enemy scale contract" % expected_pool)
	_ok(EXPECTED_PLAYER_HEIGHT_M < 1.60 and EXPECTED_FOE_HEIGHT_M < EXPECTED_PLAYER_HEIGHT_M,
		"characters remain subordinate to the enlarged architecture and the player stays readable")


func _test_projectile_pool_reveal_order() -> void:
	print("--- pooled projectile initialization order ---")
	_game.call("_deactivate_all_projectiles")
	var pool_v: Variant = _game.get("_projectile_pool")
	var pool := pool_v as Array if pool_v is Array else []
	_ok(not pool.is_empty(), "the runtime owns a bounded projectile pool")
	if pool.is_empty():
		return
	var first := pool[0] as Dictionary
	var sprite := first.get("node") as Sprite3D
	if sprite == null:
		_ok(false, "pooled projectile entries own Sprite3D nodes")
		return
	sprite.global_position = Vector3(91.0, 17.0, -33.0)
	sprite.visible = true
	first["active"] = false
	var acquired := _game.call("_acquire_projectile") as Dictionary
	_ok(not acquired.is_empty() and bool(acquired.get("active", false)) and not (acquired.get("node") as Sprite3D).visible,
		"acquiring a reused projectile hides it before any new transform/artwork is applied")
	_game.call("_deactivate_projectile", acquired)


func _test_reinforcement_director() -> void:
	print("--- three-pack director / six-live cap ---")
	var constants := _constants()
	_ok(int(constants.get("MAX_ACTIVE_FOES", -1)) == EXPECTED_ACTIVE_CAP,
		"desktop and phone share one explicit six-live-enemy ceiling")
	_ok(int(constants.get("PHONE_FOES", 99)) <= 12,
		"the phone preallocates no more than twelve reusable corrupted rigs")
	var authored_waves := constants.get("WAVE_PACKS", []) as Array
	var expected_minions := [14, 15, 15, 15, 13]
	var authored_totals_ok := authored_waves.size() == expected_minions.size()
	for wave_i in range(mini(authored_waves.size(), expected_minions.size())):
		var authored_total := 0
		var authored_packs := authored_waves[wave_i] as Array
		for pack_value in authored_packs:
			authored_total += (pack_value as Array).size()
		authored_totals_ok = authored_totals_ok and authored_total == int(expected_minions[wave_i])
	_ok(authored_totals_ok,
		"Horde packs match the authored 14/15-enemy sanctum objectives, with Grimwick counted separately")
	var parity_valid := true
	for wave in range(5):
		_game.call("debug_start_wave", wave)
		var state := _state()
		parity_valid = parity_valid and int(state.get("packs", -1)) == EXPECTED_PACKS_PER_WAVE \
			and int(state.get("active_foes", 99)) <= EXPECTED_ACTIVE_CAP
		for _pack in range(1, EXPECTED_PACKS_PER_WAVE):
			_deactivate_minions_until(1)
			_game.call("_spawn_next_pack")
			state = _state()
			parity_valid = parity_valid and int(state.get("active_foes", 99)) <= EXPECTED_ACTIVE_CAP
		parity_valid = parity_valid and int(_state().get("pack", -1)) == EXPECTED_PACKS_PER_WAVE
	_ok(parity_valid,
		"all five waves deliver three reinforcement packs without exceeding six live foes (%s)" % ("phone" if _phone else "HD"))


func _test_travel_target() -> void:
	print("--- post-sanctum traversal ---")
	_game.call("debug_start_wave", 0)
	var constants := _constants()
	var arenas := constants.get("ARENAS", []) as Array
	# A sanctum is intentionally immune to completion while its entrance countdown is active.
	_game.call("debug_advance", 1.46)
	_game.call("debug_complete_wave")
	_ok(String(_state().get("wave_phase", "")) == "clear", "clearing a sanctum enters its authored recovery beat")
	_game.call("debug_advance", 1.16)
	var state := _state()
	var expected := Vector2((arenas[1] as Dictionary).get("center", Vector2.ZERO)) if arenas.size() > 1 else Vector2.ZERO
	var target := Vector2(state.get("travel_target", Vector2.ZERO))
	var marker := _game.get("_travel_marker") as Node3D
	var arena_rect := _game.get("_arena_rect") as Rect2
	_ok(String(state.get("wave_phase", "")) == "travel" and target == expected and target != Vector2.ZERO,
		"wave one opens continuous traversal toward the next sanctum instead of teleporting")
	_ok(marker != null and marker.visible and arena_rect.size == Vector2.ZERO,
		"the route marker is visible and the old arena clamp is removed during travel")


func _test_malformed_rarity() -> void:
	print("--- malformed rarity fallback ---")
	var stats := _game.call("rarity_stats", "UNKNOWN_BROKEN_KIND") as Dictionary
	_ok(String(stats.get("label", "")) == "NORMAL" and _near(float(stats.get("hp", -1.0)), 1.0) \
		and _near(float(stats.get("damage", -1.0)), 1.0),
		"an unknown rarity resolves to the Normal 1.0× stat contract")
	_game.call("debug_restart_with", _unit("corrupt-client-value"))
	var state := _state()
	_ok(_near(float(state.get("rarity_mult", -1.0)), 1.0) and _near(float(state.get("rarity_hp_mult", -1.0)), 1.0),
		"malformed roster data cannot inherit Legendary or Meme combat advantages")


func _prepare_card_target() -> Dictionary:
	_game.call("debug_start_wave", 0)
	_game.call("_deactivate_all_enemies")
	_game.set("_wave_phase", "fight")
	_game.set("_pack_at", EXPECTED_PACKS_PER_WAVE)
	_game.set("_stage_over", false)
	_game.set("_input_on", true)
	_game.set("_attack_cd", 0.0)
	_game.set("_pending_cast", {})
	_game.set("_card_cooldowns", {})
	_game.set("_energy", 4.0)
	var center := Vector2((_constants().get("ARENAS", [])[0] as Dictionary).get("center", Vector2.ZERO))
	_game.set("_ppos", center)
	_game.set("_face_dir", Vector2.UP)
	_game.call("_sync_player")
	var pool := _enemy_pool()
	if pool.is_empty():
		return {}
	var target := pool[0] as Dictionary
	_game.call("_activate_enemy", target, center + Vector2.UP * 42.0, 0)
	target["awake"] = false
	target["maxhp"] = 1000.0
	target["hp"] = 1000.0
	return target


func _test_one_tap_and_release_timing() -> void:
	print("--- one-tap card cast / release-frame damage ---")
	var target := _prepare_card_target()
	_ok(not target.is_empty(), "a deterministic corrupted target is available for the card timing probe")
	if target.is_empty():
		return
	var before_state := _state()
	var before_energy := float(before_state.get("energy", 0.0))
	var indices := _game.call("_page_indices") as Array
	var global_index := int(indices[0]) if not indices.is_empty() else 0
	var slots := before_state.get("card_slots", []) as Array
	var slot := int(slots[global_index]) if global_index < slots.size() else 0
	var cost := float((Econ.CARDS[slot] as Dictionary).get("cost", 0.0))
	var hp_before := float(target.get("hp", 0.0))
	_game.call("_on_card_pressed", 0)
	var cast_state := _state()
	var profile := cast_state.get("last_visual_profile", {}) as Dictionary
	var release := float(profile.get("release", 0.0))
	_ok(int(cast_state.get("selected_slot", -1)) == slot and bool(cast_state.get("pending_cast", false)) \
		and _near(float(cast_state.get("energy", 0.0)), before_energy - cost),
		"one card-button press both selects and begins the exact card, spending its cost once")
	_ok(release > 0.02, "the selected card exposes a readable positive release time")

	var first_slice := release * 0.50
	_game.call("_tick_pending_cast", first_slice)
	var hp_before_release := float(target.get("hp", 0.0))
	_ok(_near(hp_before_release, hp_before), "card damage is absent before profile.release")
	_game.call("_tick_pending_cast", release - first_slice + 0.001)
	var hp_after_release := float(target.get("hp", 0.0))
	_ok(hp_after_release < hp_before and not bool(_state().get("pending_cast", true)),
		"the card resolves exactly when its visual profile reaches release")
	_game.call("_tick_pending_cast", release + 0.50)
	_ok(_near(float(target.get("hp", 0.0)), hp_after_release),
		"the resolved cast cannot apply a second hit on later frames")


func _test_boss_parity_contract() -> void:
	print("--- Grimwick HD/phone parity and boss visual scale ---")
	_game.call("debug_start_wave", 4)
	var boss_v: Variant = _game.get("_boss")
	var boss := boss_v as Dictionary if boss_v is Dictionary else {}
	var expected_hp := 110.0 * clampf(0.92 + 0.012 * 49.0, 0.92, 1.52)
	_ok(bool(boss.get("active", false)) and _near(float(boss.get("maxhp", 0.0)), expected_hp, 0.01),
		"level-50 Grimwick uses the same %.2f HP contract in the %s profile" % [expected_hp, "phone" if _phone else "HD"])
	var rig := boss.get("rig") as Node3D
	var body := boss.get("body") as Node3D
	var metrics := _rig_metrics(rig)
	var effective_height := float(metrics.get("normalized_visible_height_m", 0.0)) \
		* (body.scale.y if body != null else 0.0)
	_ok(bool(metrics.get("valid", false)) and _near(effective_height, EXPECTED_BOSS_HEIGHT_M),
		"Grimwick's effective painted silhouette is 1.62 m, larger than the player but not room-sized")
	_ok(EXPECTED_BOSS_HEIGHT_M > EXPECTED_PLAYER_HEIGHT_M and EXPECTED_BOSS_HEIGHT_M < 2.0,
		"boss hierarchy is readable without returning to oversized floating cutouts")


func _test_collision_resolved_gait() -> void:
	print("--- collision-resolved player/enemy gait ---")
	_game.call("_deactivate_all_enemies")
	var arenas := _constants().get("ARENAS", []) as Array
	if arenas.is_empty():
		_ok(false, "an arena exists for the collision-resolved gait probe")
		return
	var arena := arenas[0] as Dictionary
	var rect := arena.get("rect", Rect2()) as Rect2
	var center := arena.get("center", Vector2.ZERO) as Vector2
	_game.set("_arena_rect", rect)
	_game.set("_arena_center", center)
	_game.set("_started", false)
	_game.set("_stage_over", false)
	_game.set("_input_on", true)
	_game.set("_dodge_t", 0.0)

	# The horde clamp is resolved inside _move_player(), before Temple3D measures displacement.
	# Pressing outward at the wall therefore leaves the rig idle and adds exactly zero foot phase.
	var rig := _game.get("_rig") as Node3D
	_ok(rig != null and rig.has_method("walk_cycle_phase"),
		"the controlled Chikimon exposes its distance-driven gait")
	if rig == null or not rig.has_method("walk_cycle_phase"):
		return
	rig.call("set_distance_driven_walk", true, EXPECTED_PLAYER_WALK_STRIDE_PX)
	rig.call("play", "idle")
	_game.set("_ppos", Vector2(rect.position.x + 22.0, center.y))
	_game.call("_sync_player")
	_game.set("_touch_move", Vector2.LEFT)
	var player_before := Vector2(_game.get("_ppos"))
	var player_distance_before := float(rig.get("_walk_distance"))
	_game.call("_process", 0.20)
	var player_blocked := Vector2(_game.get("_ppos")) == player_before \
		and String(rig.call("clip")) == "idle" \
		and _near(float(rig.get("_walk_distance")), player_distance_before)
	_ok(player_blocked,
		"a player pressing into a wall neither slides nor advances a phantom footstep")

	# Actual inward travel advances the cumulative phase. Expiring a cast while movement remains held
	# must immediately restore the walk clip instead of leaving an idle creature gliding over ground.
	_game.set("_touch_move", Vector2.RIGHT)
	var inward_before := Vector2(_game.get("_ppos"))
	_game.call("_process", 0.10)
	var inward_actual := Vector2(_game.get("_ppos")).distance_to(inward_before)
	var distance_after_inward := float(rig.get("_walk_distance"))
	var inward_walks := inward_actual > 0.01 and String(rig.call("clip")) == "walk" \
		and _near(distance_after_inward - player_distance_before, inward_actual)
	_ok(inward_walks, "player gait advances by actual inward ground distance")
	rig.call("attack", "strike")
	rig.call("_process", 0.50)
	rig.call("_process", 0.0)
	var resume_before := float(rig.get("_walk_distance"))
	_game.call("_process", 0.10)
	_ok(String(rig.call("clip")) == "walk" and float(rig.get("_walk_distance")) > resume_before,
		"held movement resumes the alternating walk immediately after a card action")

	# Enemies use their post-clamp displacement too. A Darkeet at the boundary can request an
	# outward chase step, but its feet stay idle until the same AI actually covers ground inward.
	_game.set("_wave_phase", "fight")
	var darkeet: Dictionary = {}
	for value in _enemy_pool():
		var candidate := value as Dictionary
		if String(candidate.get("species", "")) == "darkeet":
			darkeet = candidate
			break
	_ok(not darkeet.is_empty(), "a pooled Darkeet is available for the enemy gait probe")
	if darkeet.is_empty():
		_game.set("_touch_move", Vector2.ZERO)
		return
	var edge := Vector2(rect.position.x + 20.0, center.y)
	_game.call("_activate_enemy", darkeet, edge, 0)
	darkeet["awake"] = true
	darkeet["state"] = "hunt"
	darkeet["attack_cd"] = 99.0
	var enemy_rig := darkeet.get("rig") as Node3D
	enemy_rig.call("set_distance_driven_walk", true,
		EXPECTED_PLAYER_WALK_STRIDE_PX * EXPECTED_FOE_HEIGHT_M / EXPECTED_PLAYER_HEIGHT_M)
	enemy_rig.call("play", "idle")
	_game.set("_ppos", edge - Vector2(400.0, 0.0))
	var enemy_distance_before := float(enemy_rig.get("_walk_distance"))
	_game.call("_tick_enemies", 0.18)
	var enemy_blocked := Vector2(darkeet.get("p", Vector2.ZERO)) == edge \
		and String(enemy_rig.call("clip")) == "idle" \
		and _near(float(enemy_rig.get("_walk_distance")), enemy_distance_before)
	_ok(enemy_blocked,
		"an enemy clamped at the arena edge cannot animate nonexistent travel")
	_game.set("_ppos", edge + Vector2(400.0, 0.0))
	_game.call("_tick_enemies", 0.18)
	var enemy_actual := Vector2(darkeet.get("p", Vector2.ZERO)).distance_to(edge)
	var enemy_walks := enemy_actual > 0.01 and String(enemy_rig.call("clip")) == "walk" \
		and _near(float(enemy_rig.get("_walk_distance")) - enemy_distance_before, enemy_actual)
	_ok(enemy_walks, "enemy gait advances only by its post-clamp ground distance")
	_game.set("_touch_move", Vector2.ZERO)

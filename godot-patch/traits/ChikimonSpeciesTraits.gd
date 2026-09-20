extends RefCounted
## Chikiseum/Wicked Temple species identity. Keep the first six values of every row identical
## to server/production-pvp/chikiseum-species-traits.json. Values seven and eight mirror its
## signatures table (the level-one favored card and its once-per-cast tactical effect).

const PROFILES := {
	"galador": ["Tidal Conductor", "controller", 0.98, 1.08, 1.00, 1.04, "drain", "surge"],
	"adalor": ["Dawn Bastion", "guardian", 0.96, 1.03, 1.08, 1.00, "rally", "recover"],
	"tyrannos": ["Apex Pursuit", "hunter", 1.08, 0.96, 0.99, 1.02, "rend", "fury"],
	"grovador": ["Tempest Stalker", "skirmisher", 1.05, 0.97, 0.98, 1.05, "jolt", "sunder"],
	"dragonos": ["Inferno Drive", "pressure", 1.04, 1.06, 0.94, 1.02, "charge", "surge"],
	"popcat": ["Pop Tempo", "skirmisher", 1.07, 1.03, 0.94, 1.00, "quick", "fury"],
	"moodeng": ["River Tumble", "survivor", 1.02, 1.02, 1.05, 0.95, "guard", "recover"],
	"doge": ["Such Pursuit", "hunter", 1.06, 0.98, 1.01, 0.97, "quick", "surge"],
	"pepe": ["Feels Ward", "guardian", 0.96, 1.06, 1.04, 0.99, "wither", "sunder"],
	"chillguy": ["Unbothered Flame", "survivor", 0.95, 1.05, 1.06, 0.98, "guard", "recover"],
	"alon": ["Token Surge", "pressure", 1.04, 1.07, 0.95, 0.99, "charge", "surge"],
	"electrox": ["Arc Runner", "skirmisher", 1.07, 0.98, 0.96, 1.03, "blast", "sunder"],
	"firix": ["Cinder Rush", "pressure", 1.05, 1.03, 0.95, 1.00, "strike", "fury"],
	"forestle": ["Rooted Ambush", "controller", 0.97, 0.99, 1.05, 1.05, "strike", "recover"],
	"healix": ["Lumen Reserve", "survivor", 0.97, 1.07, 1.04, 0.96, "blast", "recover"],
	"jellox": ["Elastic Current", "skirmisher", 1.06, 1.00, 0.96, 1.02, "quick", "surge"],
	"mushrow": ["Spore Patience", "guardian", 0.96, 1.04, 1.06, 0.98, "blast", "sunder"],
	"owzard": ["Talon Sight", "controller", 0.98, 1.00, 0.98, 1.08, "quick", "recover"],
	"scorplex": ["Pincer Circuit", "hunter", 1.04, 0.96, 1.02, 1.04, "strike", "sunder"],
	"solarix": ["Solar Overdrive", "pressure", 1.03, 1.08, 0.95, 0.99, "blast", "fury"],
	"drolax": ["Deepwater Anchor", "guardian", 0.95, 1.04, 1.07, 0.98, "quick", "surge"],
	"astraya": ["Starlit Reach", "controller", 0.98, 1.03, 0.96, 1.08, "quick", "fury"],
	"bamboran": ["Bamboo Counter", "guardian", 0.97, 0.98, 1.08, 1.03, "guard", "recover"],
	"borealon": ["Glacial Hold", "guardian", 0.94, 1.02, 1.09, 1.00, "guard", "recover"],
	"horoxyn": ["Storm Talons", "hunter", 1.08, 0.97, 0.96, 1.04, "quick", "sunder"],
	"rivaros": ["River Slip", "skirmisher", 1.07, 1.02, 0.97, 0.98, "rally", "surge"],
	"solvarex": ["Sunfire Lunge", "pressure", 1.05, 1.05, 0.95, 0.98, "rally", "surge"],
	"astragor": ["Astral Grapple", "hunter", 1.03, 0.95, 1.03, 1.05, "rend", "fury"],
	"crysalune": ["Crystal Refraction", "controller", 0.96, 1.05, 1.02, 1.04, "jolt", "sunder"],
	"vesperos": ["Moonveil Step", "skirmisher", 1.06, 0.98, 1.00, 1.01, "jolt", "recover"],
	"ansem": ["Horn Charge", "hunter", 1.07, 0.96, 1.00, 1.01, "rally", "recover"],
	"babygoat": ["Little Resolve", "survivor", 1.00, 1.02, 1.07, 0.96, "quick", "recover"],
	"chloe": ["Side-Eye Spark", "controller", 0.99, 1.05, 0.96, 1.06, "quick", "sunder"],
	"cryingcat": ["Tear Tide", "survivor", 0.97, 1.08, 1.01, 0.98, "drain", "recover"],
	"grumpycat": ["Stubborn Guard", "guardian", 0.95, 0.99, 1.09, 1.00, "wither", "sunder"],
	"nervousmonkey": ["Nervous Reflex", "skirmisher", 1.09, 0.96, 0.94, 1.02, "quick", "surge"],
	"peanut": ["Acorn Footwork", "hunter", 1.05, 0.98, 1.01, 1.00, "charge", "surge"],
	"stonks": ["Momentum Gain", "pressure", 1.02, 1.09, 0.96, 1.00, "charge", "surge"],
	"successkid": ["Clutch Resolve", "survivor", 0.98, 1.01, 1.08, 0.99, "jolt", "surge"],
	"thisisfine": ["Calm in Chaos", "pressure", 1.00, 1.08, 0.97, 1.02, "guard", "recover"],
	"triplet": ["Triple Feint", "skirmisher", 1.08, 0.97, 0.97, 1.01, "quick", "fury"],
}

static func profile(species: String) -> Dictionary:
	var row: Array = PROFILES.get(species.to_lower(), [])
	if row.size() != 8:
		return {"name": "Balanced", "style": "balanced", "stride": 1.0,
			"focus": 1.0, "ward": 1.0, "reach": 1.0,
			"signature_arch": "", "signature_effect": ""}
	return {"name": String(row[0]), "style": String(row[1]), "stride": float(row[2]),
		"focus": float(row[3]), "ward": float(row[4]), "reach": float(row[5]),
		"signature_arch": String(row[6]), "signature_effect": String(row[7])}

static func signature_description(species: String) -> String:
	var species_profile := profile(species)
	var arch := String(species_profile["signature_arch"]).capitalize()
	match String(species_profile["signature_effect"]):
		"surge": return "%s restores card energy once per cast" % arch
		"recover": return "%s restores health once per cast" % arch
		"sunder": return "%s briefly weakens one corruptimon" % arch
		"fury": return "%s deals 7%% extra damage" % arch
	return "A balanced companion for every arena"

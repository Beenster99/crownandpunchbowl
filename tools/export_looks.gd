extends SceneTree
## Writes every base look (and the crowd variants each type can roll) to JSON for the
## Blender build script. Run after changing CharacterLooks, then rebuild the models:
##   godot --headless --path . --script res://tools/export_looks.gd
##   blender -b -P tools/blender/build_characters.py

const OUT := "res://assets/models/characters/looks.json"
const ENUMS := {"hair": "Hair", "beard": "Beard", "top": "Top", "over": "Over", "hat": "Hat"}


func _initialize() -> void:
	var out := {}
	for table in [CharacterLooks.FARMERS, CharacterLooks.PUNTERS, CharacterLooks.POLICE, CharacterLooks.STAFF]:
		for id in table:
			var look := CharacterLooks._make(id, table, id)
			var d := {}
			for p in look.get_property_list():
				if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
					continue
				var v = look.get(p["name"])
				if ENUMS.has(p["name"]):
					v = _enum_name(p["name"], v)
				elif v is Color:
					v = v.to_html(false)
				d[p["name"]] = v
			# Pieces the crowd variation can switch to, so the model carries them all.
			var variants := {"hair": [d["hair"]], "beard": [d["beard"]], "hat": [d["hat"]], "top": [d["top"]]}
			if not table == CharacterLooks.FARMERS and not look.feminine and look.top != CharacterLook.Top.POLICE:
				variants["beard"].append("STUBBLE")
			var vary: Dictionary = CharacterLooks.VARY.get(id, {})
			for key in variants:
				for v in vary.get(key, []):
					var n := _enum_name(key, v)
					if not variants[key].has(n):
						variants[key].append(n)
			d["variants"] = variants
			out[id] = d
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t", false))
	print("wrote %d looks to %s" % [out.size(), OUT])
	quit(0)


func _enum_name(prop: String, value: int) -> String:
	var e: Dictionary = _enum(prop)
	return e.find_key(value)


func _enum(prop: String) -> Dictionary:
	match prop:
		"hair": return CharacterLook.Hair
		"beard": return CharacterLook.Beard
		"top": return CharacterLook.Top
		"over": return CharacterLook.Over
		_: return CharacterLook.Hat

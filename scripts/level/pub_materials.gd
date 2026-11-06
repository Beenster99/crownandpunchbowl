class_name PubMaterials
extends RefCounted
## Textured PBR materials for the pubs and their props. Texture sets come from
## tools/textures/build_textures.py (assets/textures/materials/<set>_albedo/normal/rough.jpg);
## albedo is mostly neutral detail, so each material is a texture set tinted with a colour.
##
## Two uses:
##  - `PubMaterials.named("M_wood_oak")`: the shared prop materials the Blender models
##    are exported with (see tools/blender/props_kit.py). PropLibrary swaps them in.
##  - `PubMaterials.surface(set, color, ...)`: architecture (walls, floors, beams, the bar)
##    tinted with the era colours from PubEra.
##
## Everything uses triplanar mapping, so no UVs are needed. Architecture maps in world space,
## so textures run on across wall pieces. Props map in object space, so the grain moves
## with them when they're knocked flying. Results are cached, so the same name or arguments
## always return the same material (cheap batching, and set_highlight copies before changing).

const TEX_DIR := "res://assets/textures/materials/%s_%s.jpg"

## name: [texture set or "", colour, metallic, roughness, texture scale (repeats per metre), options]
## options: "alpha" for see-through, "emit" to glow, "rim" for a soft sheen (fabric/felt).
const NAMED := {
	"wood_oak": ["wood", Color("8a5e3a"), 0.0, 1.0, 1.6, ""],
	"wood_dark": ["wood", Color("4a2e1a"), 0.0, 0.9, 1.6, ""],
	"wood_pine": ["wood", Color("c09a68"), 0.0, 1.0, 1.4, ""],
	"wood_mahogany": ["wood", Color("4e2216"), 0.0, 0.75, 1.8, ""],
	"wood_painted_green": ["grime", Color("34523e"), 0.0, 1.0, 1.0, ""],
	"wood_painted_cream": ["grime", Color("d8cdb0"), 0.0, 1.0, 1.0, ""],
	"wood_black": ["wood", Color("201c18"), 0.0, 0.7, 1.8, ""],
	"iron": ["cast_iron", Color("2a2a2a"), 0.85, 1.0, 3.0, ""],
	"brass": ["metal", Color("d2a848"), 0.85, 1.1, 3.0, ""],
	"copper": ["metal", Color("c47844"), 0.85, 1.2, 2.0, ""],
	"pewter": ["metal", Color("9a9c98"), 0.75, 1.4, 3.0, ""],
	"chrome": ["metal", Color("d8d8d8"), 0.7, 1.0, 3.0, ""],
	"gilt": ["metal", Color("d0a848"), 0.85, 1.3, 2.0, ""],
	"glass": ["", Color(0.55, 0.62, 0.6, 0.16), 0.0, 0.05, 1.0, "alpha"],
	"glass_green": ["", Color(0.1, 0.26, 0.13, 0.8), 0.0, 0.06, 1.0, "alpha"],
	"glass_brown": ["", Color(0.24, 0.11, 0.03, 0.86), 0.0, 0.06, 1.0, "alpha"],
	"glass_thick": ["", Color(0.55, 0.64, 0.62, 0.3), 0.0, 0.05, 1.0, "alpha"],
	"glass_blue": ["", Color(0.08, 0.16, 0.36, 0.78), 0.0, 0.06, 1.0, "alpha"],
	"ale": ["", Color(0.62, 0.34, 0.08, 0.92), 0.0, 0.1, 1.0, "alpha"],
	"lager": ["", Color(0.85, 0.64, 0.18, 0.85), 0.0, 0.1, 1.0, "alpha"],
	"stout": ["", Color("120a06"), 0.0, 0.15, 1.0, ""],
	"cider": ["", Color(0.82, 0.62, 0.22, 0.78), 0.0, 0.1, 1.0, "alpha"],
	"wine_red": ["", Color(0.3, 0.02, 0.06, 0.92), 0.0, 0.1, 1.0, "alpha"],
	"whisky": ["", Color(0.62, 0.36, 0.1, 0.8), 0.0, 0.1, 1.0, "alpha"],
	"water": ["", Color(0.85, 0.92, 0.92, 0.3), 0.0, 0.05, 1.0, "alpha"],
	"foam": ["plaster", Color("e0d4b8"), 0.0, 1.0, 6.0, ""],
	"leather_red": ["leather", Color("7a2018"), 0.0, 0.9, 3.0, ""],
	"leather_brown": ["leather", Color("5a3420"), 0.0, 0.9, 3.0, ""],
	"leather_green": ["leather", Color("244632"), 0.0, 0.9, 3.0, ""],
	"fabric_red": ["fabric", Color("8a2e2e"), 0.0, 1.0, 4.0, "rim"],
	"fabric_green": ["fabric", Color("2e5236"), 0.0, 1.0, 4.0, "rim"],
	"fabric_tweed": ["fabric", Color("7a6a50"), 0.0, 1.0, 4.0, "rim"],
	"fabric_blue": ["fabric", Color("2e3a58"), 0.0, 1.0, 4.0, "rim"],
	"rush": ["fabric", Color("b09858"), 0.0, 1.0, 2.0, ""],
	"felt": ["felt", Color("1f7038"), 0.0, 1.0, 2.0, "rim"],
	"ceramic": ["grime", Color("eee8da"), 0.0, 0.5, 2.0, ""],
	"ceramic_blue": ["grime", Color("2e4e90"), 0.0, 0.5, 2.0, ""],
	"stoneware": ["stone", Color("c4ac84"), 0.0, 0.6, 4.0, ""],
	"ivory": ["grime", Color("efe6cf"), 0.0, 0.6, 2.0, ""],
	"black_gloss": ["grime", Color("121212"), 0.0, 0.35, 2.0, ""],
	"paper": ["fabric", Color("e8e0c8"), 0.0, 1.0, 6.0, ""],
	"wax": ["grime", Color("efe6cc"), 0.0, 1.2, 4.0, ""],
	"flame": ["", Color("ffb040"), 0.0, 1.0, 1.0, "emit"],
	"plaster": ["plaster", Color("d8cdb4"), 0.0, 1.0, 1.0, ""],
	"stone": ["stone", Color("8a8478"), 0.0, 1.0, 1.5, ""],
	"rope": ["fabric", Color("a08850"), 0.0, 1.0, 3.0, ""],
	"plastic_red": ["", Color("b8201c"), 0.0, 0.35, 1.0, ""],
	"plastic_black": ["", Color("1a1a1a"), 0.0, 0.4, 1.0, ""],
	"neon": ["", Color("ff6a3a"), 0.0, 0.5, 1.0, "emit"],
	"foliage": ["leather", Color("2e5a2a"), 0.0, 0.8, 6.0, ""],
	"soil": ["stone", Color("2a1c10"), 0.0, 1.0, 6.0, ""],
	"bone": ["grime", Color("e4dcc4"), 0.0, 1.0, 3.0, ""],
	"chalk": ["plaster", Color("2a2e2c"), 0.0, 1.0, 2.0, ""],
}

static var _cache := {}
static var _textures := {}


## The shared prop material for an exported name such as "M_brass" (null if unknown).
static func named(material_name: String) -> Material:
	var key := material_name.trim_prefix("M_")
	if _cache.has("n/" + key):
		return _cache["n/" + key]
	if not NAMED.has(key):
		return null
	var d: Array = NAMED[key]
	var m := _make(String(d[0]), d[1], float(d[2]), float(d[3]), float(d[4]), String(d[5]), false)
	_cache["n/" + key] = m
	return m


## Architecture material: texture `set` tinted with `color`. `scale` is texture repeats
## per metre. `rough_mult` scales the texture's roughness (lower = shinier).
static func surface(set: String, color: Color, scale := 0.5, rough_mult := 1.0, metallic := 0.0) -> StandardMaterial3D:
	var key := "s/%s/%s/%.3f/%.2f/%.2f" % [set, color.to_html(), scale, rough_mult, metallic]
	if not _cache.has(key):
		_cache[key] = _make(set, color, metallic, rough_mult, scale, "", true)
	return _cache[key]


static func texture(set: String, map: String) -> Texture2D:
	var key := set + "/" + map
	if not _textures.has(key):
		var path := TEX_DIR % [set, map]
		_textures[key] = load(path) if ResourceLoader.exists(path) else null
	return _textures[key]


static func _make(set: String, color: Color, metallic: float, rough: float, scale: float, opts: String,
		world: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if set != "" and texture(set, "albedo") != null:
		m.albedo_texture = texture(set, "albedo")
		m.normal_enabled = true
		m.normal_texture = texture(set, "normal")
		m.normal_scale = 0.8
		m.roughness_texture = texture(set, "rough")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.roughness = clampf(rough, 0.0, 2.0)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = world
		m.uv1_triplanar_sharpness = 4.0
		m.uv1_scale = Vector3.ONE * scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if opts == "alpha" or color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.metallic_specular = 0.9
	if opts == "emit":
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if opts == "rim":
		m.rim_enabled = true
		m.rim = 0.35
		m.rim_tint = 0.6
	return m

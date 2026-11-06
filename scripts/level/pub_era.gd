class_name PubEra
extends RefCounted
## Era styles for the village pubs: colours, floor pattern, ceiling height and lighting.
## Each pub picks one with `PubEra.get_style(id)` and the PubBuilder reads it when
## making walls, floors and lights. The colours tint PubMaterials texture sets: `wall_tex`
## and `dado_tex` name the sets for the upper wall and the dado, and timber, trim, bar
## and furniture colours get wood grain.

const STYLES := {
	# Low, dark and smoky: flagstones, whitewash between oak framing, low beams,
	# a big inglenook and candle/fire light.
	"17th": {
		"label": "17th century",
		"wall_tex": "plaster", "dado_tex": "plaster",
		"wall_height": 2.7,
		"floor": "flagstone", "floor_a": Color("6d675f"), "floor_b": Color("57524b"),
		"wall": Color("d8cdb4"), "dado": Color("d8cdb4"), "trim": Color("3a2414"),
		"timber": Color("3a2414"), "bar": Color("4a2c17"), "bar_top": Color("2e1a0c"),
		"furniture": Color("4a2d18"), "accent": Color("8a6a3c"),
		"beams": true, "beam_height": 2.35, "posts": true,
		"ambient": Color("5a3a22"), "ambient_energy": 0.45, "background": Color("0d0805"),
		"lamp": Color("ffa64d"), "lamp_energy": 1.4, "lamp_range": 6.0, "lamp_kind": "candle",
		"fog": Color("2a1a0e"), "fog_density": 0.012,
	},
	# Georgian: wide oak boards, painted walls over panelled dado, sash windows, brass.
	"18th": {
		"label": "18th century",
		"wall_tex": "plaster", "dado_tex": "panelling",
		"wall_height": 3.2,
		"floor": "boards", "floor_a": Color("7a5232"), "floor_b": Color("6a4529"),
		"wall": Color("8fa08a"), "dado": Color("4f5e4c"), "trim": Color("e7e0cc"),
		"timber": Color("5b3a20"), "bar": Color("5b3a20"), "bar_top": Color("3a2412"),
		"furniture": Color("5e3b20"), "accent": Color("c9a03a"),
		"beams": false, "beam_height": 3.0, "posts": false,
		"ambient": Color("6b5a44"), "ambient_energy": 0.6, "background": Color("110c08"),
		"lamp": Color("ffc078"), "lamp_energy": 1.8, "lamp_range": 8.0, "lamp_kind": "sconce",
		"fog": Color("231a12"), "fog_density": 0.008,
	},
	# Victorian: encaustic tiles, glazed tile dado, etched glass screens, gas lamps,
	# a big carved back bar.
	"19th": {
		"label": "19th century",
		"wall_tex": "wallpaper", "dado_tex": "glazed_tile",
		"wall_height": 3.4,
		"floor": "slate", "floor_a": Color("30363c"), "floor_b": Color("272c31"),
		"wall": Color("b9a27a"), "dado": Color("2f5a43"), "trim": Color("6b1f1f"),
		"timber": Color("4a1d12"), "bar": Color("5a2215"), "bar_top": Color("2b0f08"),
		"furniture": Color("4f2416"), "accent": Color("d6b25e"),
		"beams": false, "beam_height": 3.2, "posts": false,
		"ambient": Color("5d5640"), "ambient_energy": 0.55, "background": Color("0b0b08"),
		"lamp": Color("f4e3a1"), "lamp_energy": 2.0, "lamp_range": 8.5, "lamp_kind": "gas",
		"fog": Color("1e1c12"), "fog_density": 0.01,
	},
}


static func get_style(id: String) -> Dictionary:
	return STYLES.get(id, STYLES["17th"])

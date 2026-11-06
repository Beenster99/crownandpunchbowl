shader_type spatial;
// Bruises, swelling and cuts drawn over a character's skin (see scripts/fx/wound_skin.gd).
// It runs as the skin material's next pass: the same mesh drawn again a hair further out,
// see-through except where it's marked. Swollen spots push the skin out for real (a closing
// eye, a fat lip). Spots live in the mesh's rest pose (CUSTOM0 holds each vertex's rest
// position), so marks stay put on the face whatever the bones are doing.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

const int MAX_SPOTS = 16;

uniform int spot_count = 0;
uniform vec4 spot_pos[MAX_SPOTS];   // xyz centre (rest pose), w radius
uniform vec4 spot_dmg[MAX_SPOTS];   // x bruise, y swelling, z cut, w seconds since first hit
uniform vec4 spot_cut[MAX_SPOTS];   // xyz direction of the split, w half length
uniform vec4 spot_out[MAX_SPOTS];   // xyz outward from the skin, w swelling scale

uniform sampler2D skin_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform vec4 skin_tint : source_color = vec4(0.8, 0.6, 0.5, 1.0);
uniform float blood = 1.0;          // 0 with gore off: cuts show as scabs, no trickle
// Nosebleed and split-mouth blood (BloodFx face blood, 0..1): a smear under the nose and
// at the mouth with thin runs down to the chin. Stays on those spots, never the whole head.
uniform float face_blood = 0.0;
uniform int nose_spot = -1;
uniform int lip_spot = -1;

varying vec3 rest;
varying float puff;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// 1 at the centre, 0 at r, smooth both ends.
float bump(float d, float r) {
	float x = clamp(d / max(r, 0.0001), 0.0, 1.0);
	float y = 1.0 - x * x;
	return y * y;
}

void vertex() {
	rest = CUSTOM0.xyz;
	float push = 0.0;
	float p = 0.0;
	for (int i = 0; i < MAX_SPOTS; i++) {
		if (i >= spot_count) break;
		float s = spot_dmg[i].y;
		if (s <= 0.0) continue;
		float w = bump(distance(rest, spot_pos[i].xyz), spot_pos[i].w * 1.3) * s;
		push += w * spot_pos[i].w * spot_out[i].w;
		p = max(p, w);
	}
	puff = p;
	VERTEX += NORMAL * (0.0008 + push);
}

void fragment() {
	vec3 base = skin_tint.rgb;
	if (use_texture) {
		base *= texture(skin_texture, UV).rgb;
	}
	float n1 = noise3(rest * 70.0);
	float n2 = noise3(rest * 260.0);
	float bruise = 0.0;
	vec3 bruise_tint = vec3(1.0);
	float red = 0.0;
	float gash = 0.0;
	float wet = 0.0;
	for (int i = 0; i < MAX_SPOTS; i++) {
		if (i >= spot_count) break;
		vec4 dmg = spot_dmg[i];
		vec3 q = rest - spot_pos[i].xyz;
		float d = length(q);
		float r = spot_pos[i].w;
		if (d > r * 2.0) continue;
		// Bruise: a blotchy patch, dark red when fresh, purple-blue as it comes up, with a
		// yellowish edge once it's had time.
		float blot = bump(d, r * (0.7 + 0.6 * n1)) * (0.7 + 0.3 * n2);
		float b = dmg.x * blot;
		if (b > 0.0) {
			float old = clamp(dmg.w / 25.0, 0.0, 1.0);
			vec3 fresh = vec3(0.74, 0.42, 0.45);
			vec3 deep = mix(vec3(0.6, 0.45, 0.6), vec3(0.42, 0.34, 0.5), dmg.x);
			vec3 tint = mix(fresh, deep, old);
			float core = clamp(b * 1.4, 0.0, 1.0);
			float rim = clamp(b * 4.0, 0.0, 1.0) * (1.0 - core) * old;
			bruise_tint *= mix(vec3(1.0), tint, core) * mix(vec3(1.0), vec3(0.95, 0.92, 0.72), rim * 0.5);
			bruise = max(bruise, b);
		}
		// Swollen skin is tight and flushed.
		red = max(red, dmg.y * bump(d, r * 1.2) * 0.5);
		// Cut: a ragged split along spot_cut, tapering at the ends, with a raw rim.
		if (dmg.z > 0.0) {
			vec3 cd = spot_cut[i].xyz;
			float len = spot_cut[i].w * (0.55 + 0.45 * dmg.z);
			float t = clamp(dot(q, cd), -len, len);
			float dl = length(q - cd * t) + (n2 - 0.5) * 0.0014;
			float taper = 1.0 - pow(abs(t) / len, 2.0);
			float width = (0.0008 + 0.0016 * dmg.z) * taper;
			gash = max(gash, 1.0 - smoothstep(width * 0.5, width, dl));
			red = max(red, (1.0 - smoothstep(width, width * 5.0, dl)) * 0.9);
			wet = max(wet, (1.0 - smoothstep(width, width * 2.2, dl)) * blood);
			// Blood runs down from the cut: one run, and a second once it's opened up.
			if (blood > 0.0) {
				vec3 up = vec3(0.0, 1.0, 0.0);
				vec3 o = spot_out[i].xyz;
				for (int k = 0; k < 2; k++) {
					if (k == 1 && dmg.z < 0.55) break;
					float at = (k == 0 ? 0.25 : -0.6) * len;
					vec3 q2 = q - cd * at;
					float below = -dot(q2, up);
					float run = (0.01 + 0.045 * dmg.z) * clamp(dmg.w / 4.0 + 0.35, 0.0, 1.0) * (k == 0 ? 1.0 : 0.4);
					vec3 side = q2 - up * dot(q2, up) - o * dot(q2, o);
					float wob = sin(below * 180.0 + float(i) * 3.1) * 0.0009 + (n1 - 0.5) * 0.0012;
					float along = clamp(below / run, 0.0, 1.0);
					float tw = (0.0007 + 0.0008 * dmg.z) * (1.0 - along * 0.55) + 0.0007 * smoothstep(0.85, 1.0, along);
					float drip = (1.0 - smoothstep(tw * 0.5, tw, abs(length(side) + wob)))
						* step(0.0, below) * (1.0 - step(run, below));
					wet = max(wet, drip * blood * 0.95);
				}
			}
		}
	}
	if (face_blood > 0.0 && blood > 0.0) {
		vec3 up = vec3(0.0, 1.0, 0.0);
		for (int s = 0; s < 2; s++) {
			int i = s == 0 ? nose_spot : lip_spot;
			if (i < 0 || i >= spot_count) continue;
			vec3 o = spot_out[i].xyz;
			float r = spot_pos[i].w;
			// Under the nose (or on the lip): a small wet patch, ragged at the edge.
			vec3 c = spot_pos[i].xyz - up * r * (s == 0 ? 0.9 : 0.1);
			vec3 q = rest - c;
			// Measured across the face, not into it: the nose tip stands well proud of the lip.
			vec3 qf = q - o * dot(q, o);
			float patch = bump(length(qf * vec3(1.0, 1.5, 1.0)), r * (0.5 + 0.6 * face_blood) * (0.75 + 0.5 * n1));
			wet = max(wet, clamp(patch * 3.0, 0.0, 1.0) * (0.55 + 0.4 * face_blood));
			// Runs: two from the nostrils, one from a mouth corner, longer as it builds.
			for (int k = 0; k < 2; k++) {
				if (s == 1 && k == 1) break;
				float off = s == 0 ? (k == 0 ? -0.4 : 0.4) : 0.55;
				vec3 side_dir = normalize(cross(up, o));
				vec3 q2 = q - side_dir * off * r;
				float below = -dot(q2, up);
				float run = (0.012 + 0.05 * face_blood) * (s == 0 ? 1.0 : 0.7);
				vec3 side = q2 - up * dot(q2, up) - o * dot(q2, o);
				float wob = sin(below * 160.0 + float(k + s * 2) * 2.3) * 0.0008 + (n1 - 0.5) * 0.001;
				float along = clamp(below / run, 0.0, 1.0);
				float tw = (0.0022 + 0.0016 * face_blood) * (1.0 - along * 0.5) + 0.001 * smoothstep(0.85, 1.0, along);
				float drip = (1.0 - smoothstep(tw * 0.5, tw, abs(length(side) + wob)))
					* step(0.0, below) * (1.0 - step(run, below));
				wet = max(wet, drip * 0.95);
			}
		}
	}
	vec3 col = base;
	col = mix(col, col * vec3(1.05, 0.7, 0.68), clamp(red, 0.0, 1.0));
	col *= bruise_tint;
	col = mix(col, vec3(0.3, 0.015, 0.02), wet);
	col = mix(col, blood > 0.0 ? vec3(0.1, 0.0, 0.005) : vec3(0.22, 0.08, 0.06), gash);
	ALBEDO = col;
	ROUGHNESS = mix(mix(0.6, 0.48, clamp(puff * 1.5, 0.0, 1.0)), 0.18, max(gash, wet));
	SPECULAR = 0.5;
	// Match the skin material's rim (CharacterRig._material) so the overlay blends in.
	RIM = 0.25;
	RIM_TINT = 0.6;
	float a = max(max(bruise * 1.4, red * 1.1), max(gash, wet));
	a = max(a, clamp(puff * 6.0, 0.0, 1.0));
	if (a < 0.004) {
		discard;
	}
	ALPHA = clamp(a, 0.0, 1.0);
}

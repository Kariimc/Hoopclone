extends RefCounted
class_name CrowdBowl
## Crowd arc builder + hype dial, extracted from main.gd (Sprint 5 refactor).
## One continuous curved wall of animated crowd texture that wraps the far side
## and both baskets but stays OPEN behind the camera. Pure helpers: `build()`
## constructs the arc under a host node and returns the ShaderMaterial; the host
## holds that material and pokes `set_intensity()` on a made basket / big play.

# --- Crowd arc (curved wall; OPEN on the camera side) ---
const BOWL_BOTTOM_RADIUS := 22.0
const BOWL_TOP_RADIUS := 26.0     # wider top = raked seating, flares outward
const BOWL_Y_BOTTOM := -3.0       # starts below the floor (hidden), rises up
const BOWL_Y_TOP := 12.0
const BOWL_ARC_DEG := 260.0       # degrees of crowd; the rest is open toward the camera
const BOWL_SEGMENTS := 64
const IDLE_INTENSITY := 0.25

# Animates the crowd texture: sway, soft glowing camera flashes, brightness
# breath, and drift to soften tiling. uv_scale is the fan-size dial — HIGHER =
# more copies = SMALLER fans (4 keeps the photo's proportions correct). Unshaded.
const SHADER := """
shader_type spatial;
render_mode cull_disabled, unshaded;

uniform sampler2D crowd_tex : source_color, filter_linear, repeat_enable;
uniform float intensity : hint_range(0.0, 1.0) = 0.25;
uniform float uv_scale = 4.0;
uniform float sway_amount = 0.006;
uniform float sway_speed = 1.2;
uniform float flash_amount = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 raw = UV;          // 0..1 across the arc; drives flashes + drift
	vec2 uv = UV;
	uv.x *= uv_scale;       // tiled; samples the crowd texture

	// Sway: slow per-column vertical shimmer, like a crowd shifting in place.
	float sway = sin(uv.x * 6.2831 + TIME * sway_speed) * sway_amount * (0.5 + intensity);
	uv.y += sway;

	vec3 col = texture(crowd_tex, uv).rgb;

	// Drift: smooth brightness + tint variation at a different frequency than the
	// tiling, so repeats stop reading as stamped copies. No hard seams.
	float drift = sin(raw.x * 9.0) * 0.5 + sin(raw.x * 23.0 + 1.3) * 0.3 + sin(raw.x * 4.0 + 2.1) * 0.2;
	col *= 1.0 + drift * 0.10;
	float tintmix = sin(raw.x * 13.0) * 0.5 + 0.5;
	col *= mix(vec3(1.03, 1.0, 0.97), vec3(0.97, 1.0, 1.03), tintmix);

	// Camera flashes: occasional soft GLOWING pops (bright core + halo), like
	// phone flashes in the stands. Coarse grid + radial glow = no hard pixels.
	vec2 fgrid = vec2(34.0, 14.0);
	vec2 fid = floor(raw * fgrid);
	vec2 fuv = fract(raw * fgrid) - 0.5;
	float fh = hash21(fid);
	float fphase = fract(fh * 27.0 + TIME * 0.8);       // each cell on its own clock
	float pop = 1.0 - smoothstep(0.0, 0.09, fphase);    // brief bright pop, then fade
	float glow = exp(-dot(fuv, fuv) * 22.0);            // soft radial glow, core to halo
	float spark = step(0.96, fh) * pop * glow;          // only the rare cells, rarely
	col += vec3(0.9, 0.95, 1.0) * spark * flash_amount * (1.0 + intensity);

	// Brightness breath: gentle, lifts when hyped.
	col *= 1.0 + sin(TIME * 1.7) * 0.04 * (0.4 + intensity);

	ALBEDO = col;
}
"""

## Build the crowd arc under `host` and return the ShaderMaterial so the host can
## crank hype later. Reuses the texture already on Stands_Far, then hides it.
static func build(host: Node3D) -> ShaderMaterial:
	# Reuse the crowd texture already on the flat back wall, then hide that wall —
	# the arc replaces it. To swap in a new crowd image, just drop it on
	# Stands_Far's Albedo texture slot; this code picks it up automatically.
	var crowd_tex: Texture2D = null
	var back := host.get_node_or_null("Stands_Far") as MeshInstance3D
	if back != null:
		var src := back.get_active_material(0) as StandardMaterial3D
		if src != null:
			crowd_tex = src.albedo_texture
		back.visible = false
	if crowd_tex == null:
		push_warning("No crowd texture on Stands_Far — arc will render blank.")

	var shader := Shader.new()
	shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("crowd_tex", crowd_tex)
	mat.set_shader_parameter("intensity", IDLE_INTENSITY)

	var bowl := MeshInstance3D.new()
	bowl.name = "Crowd_Bowl"
	bowl.mesh = _make_crowd_arc()
	bowl.material_override = mat
	host.add_child(bowl)
	print("Crowd arc built: r %.0f-%.0f, arc %.0f deg" % [BOWL_BOTTOM_RADIUS, BOWL_TOP_RADIUS, BOWL_ARC_DEG])
	return mat

## Gameplay hook (Sprint 5): call on a made basket / big play to spike the crowd,
## then ease the value back toward idle from the caller. 0 = idle, 1 = roaring.
static func set_intensity(mat: ShaderMaterial, v: float) -> void:
	if mat != null:
		mat.set_shader_parameter("intensity", clampf(v, 0.0, 1.0))

static func _make_crowd_arc() -> ArrayMesh:
	# A vertical curved strip swept over BOWL_ARC_DEG degrees, centered on the far
	# sideline (-Z) and left open around the near side (+Z) where the camera lives.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half := BOWL_ARC_DEG * 0.5
	for i in range(BOWL_SEGMENTS + 1):
		var t := float(i) / float(BOWL_SEGMENTS)
		var ang := deg_to_rad(-half + BOWL_ARC_DEG * t)
		var sx := sin(ang)
		var sz := -cos(ang)   # ang 0 -> -Z (far crowd); opening is centered on +Z
		verts.push_back(Vector3(sx * BOWL_BOTTOM_RADIUS, BOWL_Y_BOTTOM, sz * BOWL_BOTTOM_RADIUS))
		uvs.push_back(Vector2(t, 1.0))
		verts.push_back(Vector3(sx * BOWL_TOP_RADIUS, BOWL_Y_TOP, sz * BOWL_TOP_RADIUS))
		uvs.push_back(Vector2(t, 0.0))
	for i in range(BOWL_SEGMENTS):
		var b0 := 2 * i
		var t0 := 2 * i + 1
		var b1 := 2 * (i + 1)
		var t1 := 2 * (i + 1) + 1
		indices.append_array([b0, t0, t1, b0, t1, b1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

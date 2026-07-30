extends RefCounted
class_name CrowdFans
## Real 3D spectators in the rows closest to camera, so the front of the bowl is
## living bodies instead of a photograph.
##
## Technique, and why: every fan is one instance of ONE small mesh drawn through
## a MultiMeshInstance3D, and all the motion happens in a vertex shader. That is
## the standard way a shipping game draws a stadium crowd - the CPU never touches
## a fan, so hundreds of them cost about as much as a single object. Animating
## them as individual nodes would not survive the frame budget.
##
## The body is a modelled seated spectator (assets/models/crowd_fan.glb, built by
## tools/models/build_fan.py in headless Blender - 456 triangles, watertight).
## Its second UV channel tags every vertex with which body part it belongs to,
## which is what lets one vertex shader sit them, sway them and stand them up.
##
## Every fan carries a per-instance seed (fed in as instance custom data) that
## offsets its idle rhythm, its build, its skin tone and how eagerly it reacts, so
## no two move together and the rows never read as a repeating pattern.
##
## Reactions ride on the same 0-1 intensity dial the photo bowl uses, so a made
## basket already lifts them - see CrowdBowl.set_intensity.

const ROWS := 8
const PER_ROW := 86
const ARC_DEG := 250.0            ## matches the photo bowl, open toward camera
const INNER_X := 21.0             ## clears the 28m court AND both hoop stanchions
const INNER_Z := 13.2
const ROW_STEP := 1.25            ## each row sits further out
const ROW_RISE := 0.62            ## and higher, like raked seating
const FAN_MESH := "res://assets/models/crowd_fan.glb"
## The spectator's colour map, written out beside the model by
## tools/models/prep_crowd_fan.py. It is loaded BY PATH rather than dug out of
## the imported glTF material, because that lookup kept returning nothing and the
## whole crowd rendered as flat mannequins with none of the photographed detail.
const FAN_ALBEDO := "res://assets/models/crowd_fan_albedo.png"
const FAN_SCALE_MIN := 0.92
const FAN_SCALE_MAX := 1.08

## Shirt palette: mostly muted everyday clothing with a scattering of both team
## colours, which is what a real arena looks like from the broadcast camera.
const SHIRT_COLORS := [
	Color(0.82, 0.82, 0.84), Color(0.20, 0.22, 0.28), Color(0.48, 0.10, 0.16),
	Color(0.16, 0.28, 0.52), Color(0.35, 0.36, 0.40), Color(0.62, 0.58, 0.52),
	Color(0.10, 0.11, 0.14), Color(0.70, 0.24, 0.16), Color(0.24, 0.42, 0.34),
	Color(0.88, 0.72, 0.30),
]

const FAN_SHADER := """
shader_type spatial;
render_mode cull_disabled;

uniform float intensity : hint_range(0.0, 1.0) = 0.25;
uniform sampler2D fan_tex : source_color, filter_linear_mipmap;
uniform float has_tex = 0.0;
// Broadcast arenas light the floor and let the stands fall away. Lit as brightly
// as the court, the crowd competes with the game for attention.
uniform float dim = 1.0;

// UV2.x says which body part a vertex belongs to - 0 legs, 1 torso, 2 arms,
// 3 head - and UV2.y how far up that part it sits, so bends pivot from the right
// place instead of shearing the whole body. The tags are baked into the model.
varying float v_part;
varying vec3 v_skin;
varying vec3 v_trousers;

void vertex() {
	float part = UV2.x;
	float up = UV2.y;
	v_part = part;

	float seed = INSTANCE_CUSTOM.r;
	float eager = INSTANCE_CUSTOM.g;
	float skin_t = INSTANCE_CUSTOM.b;
	float phase = seed * 6.2831;

	// Skin runs from fair to deep; trousers are a darkened, desaturated take on
	// the shirt so an outfit still reads as one person.
	v_skin = mix(vec3(0.86, 0.68, 0.55), vec3(0.28, 0.17, 0.11), skin_t);
	v_trousers = mix(COLOR.rgb * 0.35, vec3(0.16, 0.17, 0.20), 0.55);

	float moves = step(0.5, part);

	// Idle: a slow shift of weight, always present, never synchronised.
	VERTEX.x += sin(TIME * (0.7 + seed * 0.5) + phase) * 0.018 * up * moves;
	VERTEX.z += cos(TIME * (0.5 + seed * 0.4) + phase) * 0.012 * up * moves;

	// Reaction: rise out of the seat and throw the arms up, each fan on its own
	// slight delay so the wave spreads through the rows.
	float react = clamp((intensity - seed * 0.35) * 1.6, 0.0, 1.0) * eager;
	float bounce = max(sin(TIME * 6.0 + phase), 0.0) * react;
	VERTEX.y += (react * 0.34 + bounce * 0.07) * moves;

	if (part > 1.5 && part < 2.5) {
		VERTEX.y += react * 0.55 + bounce * 0.16;
		VERTEX.x += sign(VERTEX.x) * react * 0.10;
	}
}

void fragment() {
	vec3 base = mix(COLOR.rgb, texture(fan_tex, UV).rgb, has_tex);

	// Only the shirt takes the per-fan colour. Skin, hair and jeans keep what the
	// photographed texture gave them, or the crowd turns into painted statues.
	float is_torso = step(0.5, v_part) * step(v_part, 1.5);
	vec3 shirt = mix(base, base * (COLOR.rgb * 1.7), is_torso * 0.55 * has_tex);

	vec3 albedo = mix(base, shirt, has_tex);
	if (has_tex < 0.5) {
		albedo = COLOR.rgb;
		if (v_part < 0.5) albedo = v_trousers;
		if (v_part > 1.5) albedo = v_skin;
	}
	ALBEDO = albedo * dim;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
"""

var _fan_mat: ShaderMaterial
var _fan_tex: Texture2D

## Build the seated rows around `root`. Safe to call once from _ready().
func build(root: Node3D) -> void:
	var shader := Shader.new()
	shader.code = FAN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("intensity", 0.25)
	_fan_mat = mat

	if _fan_tex != null:
		mat.set_shader_parameter("fan_tex", _fan_tex)
		mat.set_shader_parameter("has_tex", 1.0)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _fan_mesh()
	if mm.mesh == null:
		push_warning("CrowdFans: no fan mesh; crowd not built")
		return
	mm.instance_count = ROWS * PER_ROW

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260729   # fixed, so the crowd looks identical every run
	var half := ARC_DEG * 0.5
	var i := 0
	for r in range(ROWS):
		var rx := INNER_X + r * ROW_STEP
		var rz := INNER_Z + r * ROW_STEP
		var y := 0.30 + r * ROW_RISE
		for s in range(PER_ROW):
			var t := (float(s) + rng.randf_range(-0.32, 0.32)) / float(PER_ROW - 1)
			var ang := deg_to_rad(-half + ARC_DEG * t)
			var pos := Vector3(sin(ang) * rx, y, -cos(ang) * rz)

			var basis := Basis(Vector3.UP, atan2(-pos.x, -pos.z))   # face the court
			basis = basis.scaled(Vector3.ONE * rng.randf_range(FAN_SCALE_MIN, FAN_SCALE_MAX))
			mm.set_instance_transform(i, Transform3D(basis, pos))

			var shirt: Color = SHIRT_COLORS[rng.randi_range(0, SHIRT_COLORS.size() - 1)]
			mm.set_instance_color(i, shirt.lerp(Color(0.5, 0.5, 0.55), rng.randf() * 0.25))
			# r = rhythm/threshold seed, g = eagerness, b = skin tone.
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(0.55, 1.0), rng.randf(), 0.0))
			i += 1

	var node := MultiMeshInstance3D.new()
	node.name = "Crowd_Fans"
	node.multimesh = mm
	node.material_override = mat
	# Seats are static; letting Godot skip per-frame culling maths on the whole
	# block is free performance.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	print("Crowd fans built: %d seated bodies across %d rows" % [mm.instance_count, ROWS])

## Match the photo bowl: 0 = idle, 1 = on their feet.
func set_intensity(v: float) -> void:
	if _fan_mat != null:
		_fan_mat.set_shader_parameter("intensity", clampf(v, 0.0, 1.0))

## The modelled seated spectator, pulled out of its glTF. Built once, instanced
## everywhere. Deliberately low - at broadcast distance a fan is a few dozen
## pixels, so silhouette and colour are all that read.
func _fan_mesh() -> Mesh:
	if not ResourceLoader.exists(FAN_MESH):
		push_warning("CrowdFans: %s missing - rebuild it with tools/models/build_fan.py" % FAN_MESH)
		return null
	var packed: PackedScene = load(FAN_MESH)
	var scene: Node = packed.instantiate()
	var found := _first_mesh(scene)
	if ResourceLoader.exists(FAN_ALBEDO):
		_fan_tex = load(FAN_ALBEDO) as Texture2D
	elif found != null and found.get_surface_count() > 0:
		var src := found.surface_get_material(0) as BaseMaterial3D
		if src != null:
			_fan_tex = src.albedo_texture
	if _fan_tex == null:
		push_warning("CrowdFans: no colour map; the crowd will render flat")
	scene.queue_free()
	return found

func _first_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return (n as MeshInstance3D).mesh
	for c in n.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null

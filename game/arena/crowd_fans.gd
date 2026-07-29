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
## Every fan carries a per-instance seed (fed in as instance colour) that offsets
## its idle rhythm, its build, its shirt colour and how eagerly it reacts, so no
## two move together and the rows never read as a repeating pattern.
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

// UV2.x tags what a vertex belongs to: 0 = seated lower body (never moves),
// 1 = upper body, 2 = arms. UV2.y is how far up that part the vertex sits,
// so bending pivots from the right place instead of shearing the whole mesh.
void vertex() {
	float part = UV2.x;
	float up = UV2.y;

	// INSTANCE_CUSTOM carries the per-fan seed written at build time.
	float seed = INSTANCE_CUSTOM.r;
	float eager = INSTANCE_CUSTOM.g;          // how strongly this fan reacts
	float phase = seed * 6.2831;

	// Idle: a slow shift of weight, always present, never synchronised.
	float idle = sin(TIME * (0.7 + seed * 0.5) + phase);
	VERTEX.x += idle * 0.018 * up * step(0.5, part);
	VERTEX.z += cos(TIME * (0.5 + seed * 0.4) + phase) * 0.012 * up * step(0.5, part);

	// Reaction: rise out of the seat and throw the arms up. Each fan reacts on
	// its own slight delay so the wave spreads through the rows.
	float react = clamp((intensity - seed * 0.35) * 1.6, 0.0, 1.0) * eager;
	float bounce = max(sin(TIME * 6.0 + phase), 0.0) * react;

	VERTEX.y += react * 0.34 * step(0.5, part) + bounce * 0.07 * step(0.5, part);

	if (part > 1.5) {
		// Arms swing up and outward as the fan celebrates.
		float lift = react * 0.55 + bounce * 0.16;
		VERTEX.y += lift;
		VERTEX.x += sign(VERTEX.x) * react * 0.10;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
"""

var _fan_mat: ShaderMaterial

## Build the seated rows around `root`. Safe to call once from _ready().
func build(root: Node3D) -> void:
	var shader := Shader.new()
	shader.code = FAN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("intensity", 0.25)
	_fan_mat = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _fan_mesh()
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
			# r = rhythm/threshold seed, g = how eagerly this fan reacts.
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(0.55, 1.0), 0.0, 0.0))
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

## One seated spectator, built once and instanced everywhere. Deliberately blocky
## - at broadcast distance a fan is a few dozen pixels, and silhouette plus colour
## is all that reads. UV2 tags each part for the vertex shader (see FAN_SHADER).
func _fan_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# part 0 = seated legs, 1 = torso/head, 2 = arms
	_box(st, Vector3(0.0, 0.18, 0.14), Vector3(0.34, 0.16, 0.42), 0.0, 0.0)   # thighs
	_box(st, Vector3(0.0, 0.09, 0.34), Vector3(0.30, 0.30, 0.14), 0.0, 0.0)   # shins
	_box(st, Vector3(0.0, 0.52, 0.0), Vector3(0.36, 0.46, 0.24), 1.0, 0.6)    # torso
	_box(st, Vector3(0.0, 0.83, 0.0), Vector3(0.20, 0.20, 0.20), 1.0, 1.0)    # head
	_box(st, Vector3(-0.24, 0.52, 0.0), Vector3(0.11, 0.40, 0.14), 2.0, 0.9)  # left arm
	_box(st, Vector3(0.24, 0.52, 0.0), Vector3(0.11, 0.40, 0.14), 2.0, 0.9)   # right arm

	st.generate_normals()
	return st.commit()

## Append an axis-aligned box, tagging every vertex with (part, height) in UV2.
func _box(st: SurfaceTool, center: Vector3, size: Vector3, part: float, up: float) -> void:
	var h := size * 0.5
	var corners := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7],
		[1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for f in faces:
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_uv2(Vector2(part, up))
				st.add_vertex(corners[f[k]])
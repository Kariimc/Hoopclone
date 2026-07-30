extends RefCounted
class_name HoopBuilder
## Turns each bare hoop anchor into a real basket: rim, net, backboard with its
## shooter square, gooseneck arm, stanchion and padded base.
##
## The scene ships LeftHoop / RightHoop as plain anchors whose ORIGIN is rim
## centre at rim height - the ball, the shot model and the contest model all read
## that position. This builder never moves them; it swaps the anchor own mesh for
## the rim torus and hangs the rest of the assembly off it, so everything that
## already targets a hoop keeps working untouched.
##
## Dimensions follow game/court/court.gd (rim radius 0.23, backboard 0.30 behind
## the rim, half-extents 0.90 x 0.525) so the geometry and the maths agree.

const RIM_RADIUS := 0.23
const RIM_TUBE := 0.018
const NET_DEPTH := 0.45
const NET_STRANDS := 12
const NET_RINGS := 5
const NET_PINCH := 0.62

const BOARD_OFFSET := 0.30
const BOARD_HALF_W := 0.90
const BOARD_HALF_H := 0.525
const BOARD_THICK := 0.04
const BOARD_LIFT := 0.20
const SQUARE_HALF_W := 0.30
const SQUARE_HALF_H := 0.225
const SQUARE_LINE := 0.035

const POLE_SETBACK := 2.25
const POLE_RADIUS := 0.085
const BASE_SIZE := Vector3(1.05, 0.42, 1.35)

const ORANGE := Color(0.93, 0.36, 0.06)
const NET_WHITE := Color(0.94, 0.94, 0.92)
const BOARD_GLASS := Color(0.88, 0.93, 0.97, 0.20)
const PAD_BLACK := Color(0.07, 0.07, 0.09)
const STANCHION_GREY := Color(0.26, 0.27, 0.31)

func build_all(root: Node3D, hoop_names: Array = ["LeftHoop", "RightHoop"]) -> void:
	for n in hoop_names:
		var anchor := root.get_node_or_null(String(n)) as MeshInstance3D
		if anchor == null:
			push_warning("HoopBuilder: no hoop anchor named '%s'" % n)
			continue
		_build_one(anchor)
	print("Hoops built: %s" % ", ".join(PackedStringArray(hoop_names)))

func _build_one(anchor: MeshInstance3D) -> void:
	if anchor.get_node_or_null("Rim_Assembly") != null:
		return

	var out := signf(anchor.position.x)
	if is_zero_approx(out):
		out = 1.0
	var rim_y := anchor.position.y

	var group := Node3D.new()
	group.name = "Rim_Assembly"
	anchor.add_child(group)

	var torus := TorusMesh.new()
	torus.inner_radius = RIM_RADIUS - RIM_TUBE
	torus.outer_radius = RIM_RADIUS + RIM_TUBE
	anchor.mesh = torus
	anchor.set_surface_override_material(0, _metal(ORANGE, 0.35))

	group.add_child(_net())
	group.add_child(_backboard(out))
	for piece in _square(out):
		group.add_child(piece)
	group.add_child(_arm(out))
	group.add_child(_stanchion(out, rim_y))
	group.add_child(_base(out, rim_y))

## Net as line strands plus rings, pinching toward the base. Lines cost almost
## nothing and read correctly at broadcast distance, where a modelled net would
## be a handful of pixels.
func _net() -> MeshInstance3D:
	var verts := PackedVector3Array()
	var ring_r: Array[float] = []
	var ring_y: Array[float] = []
	for r in range(NET_RINGS):
		var t := float(r) / float(NET_RINGS - 1)
		ring_r.append(lerpf(RIM_RADIUS, RIM_RADIUS * NET_PINCH, t))
		ring_y.append(-NET_DEPTH * t)

	for s in range(NET_STRANDS):
		var a := TAU * float(s) / float(NET_STRANDS)
		for r in range(NET_RINGS - 1):
			verts.push_back(Vector3(cos(a) * ring_r[r], ring_y[r], sin(a) * ring_r[r]))
			verts.push_back(Vector3(cos(a) * ring_r[r + 1], ring_y[r + 1], sin(a) * ring_r[r + 1]))
	for r in range(1, NET_RINGS):
		for s in range(NET_STRANDS):
			var a0 := TAU * float(s) / float(NET_STRANDS)
			var a1 := TAU * float(s + 1) / float(NET_STRANDS)
			verts.push_back(Vector3(cos(a0) * ring_r[r], ring_y[r], sin(a0) * ring_r[r]))
			verts.push_back(Vector3(cos(a1) * ring_r[r], ring_y[r], sin(a1) * ring_r[r]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Net"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = NET_WHITE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	return mi

func _backboard(out: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Backboard"
	var box := BoxMesh.new()
	box.size = Vector3(BOARD_THICK, BOARD_HALF_H * 2.0, BOARD_HALF_W * 2.0)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BOARD_GLASS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.0
	mat.roughness = 0.04
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Unshaded, or the glass just swallows the arena light and reads as a black
	# slab from the broadcast camera - which is exactly what it did.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(out * BOARD_OFFSET, BOARD_LIFT, 0.0)
	mi.add_child(_board_frame(out))
	return mi

## White padded border around the glass. Without it the board has no edge and
## disappears against the crowd behind it.
func _board_frame(out: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Board_Frame"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.93, 0.90)
	mat.roughness = 0.7
	var pad := 0.055
	var specs := [
		[Vector3(BOARD_THICK * 1.2, pad, BOARD_HALF_W * 2.0 + pad * 2.0), Vector3(0.0, BOARD_HALF_H, 0.0)],
		[Vector3(BOARD_THICK * 1.2, pad, BOARD_HALF_W * 2.0 + pad * 2.0), Vector3(0.0, -BOARD_HALF_H, 0.0)],
		[Vector3(BOARD_THICK * 1.2, BOARD_HALF_H * 2.0, pad), Vector3(0.0, 0.0, BOARD_HALF_W)],
		[Vector3(BOARD_THICK * 1.2, BOARD_HALF_H * 2.0, pad), Vector3(0.0, 0.0, -BOARD_HALF_W)],
	]
	for i in specs.size():
		var mi := MeshInstance3D.new()
		mi.name = "Frame_%d" % i
		var box := BoxMesh.new()
		box.size = specs[i][0]
		mi.mesh = box
		mi.material_override = mat
		mi.position = specs[i][1]
		holder.add_child(mi)
	return holder

func _square(out: float) -> Array[MeshInstance3D]:
	var x := out * (BOARD_OFFSET - BOARD_THICK * 0.5 - 0.005)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ORANGE
	mat.roughness = 0.5
	var bottom := BOARD_LIFT - BOARD_HALF_H + 0.09

	var specs := [
		[Vector3(0.008, SQUARE_LINE, SQUARE_HALF_W * 2.0), Vector3(x, bottom + SQUARE_HALF_H * 2.0, 0.0)],
		[Vector3(0.008, SQUARE_LINE, SQUARE_HALF_W * 2.0), Vector3(x, bottom, 0.0)],
		[Vector3(0.008, SQUARE_HALF_H * 2.0, SQUARE_LINE), Vector3(x, bottom + SQUARE_HALF_H, -SQUARE_HALF_W)],
		[Vector3(0.008, SQUARE_HALF_H * 2.0, SQUARE_LINE), Vector3(x, bottom + SQUARE_HALF_H, SQUARE_HALF_W)],
	]
	var bars: Array[MeshInstance3D] = []
	for i in specs.size():
		var mi := MeshInstance3D.new()
		mi.name = "Square_%d" % i
		var box := BoxMesh.new()
		box.size = specs[i][0]
		mi.mesh = box
		mi.material_override = mat
		mi.position = specs[i][1]
		bars.append(mi)
	return bars

func _arm(out: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Gooseneck"
	var span := POLE_SETBACK - BOARD_OFFSET
	var box := BoxMesh.new()
	box.size = Vector3(span, 0.16, 0.22)
	mi.mesh = box
	mi.material_override = _metal(STANCHION_GREY, 0.5)
	mi.position = Vector3(out * (BOARD_OFFSET + span * 0.5), BOARD_LIFT + BOARD_HALF_H - 0.10, 0.0)
	return mi

func _stanchion(out: float, rim_y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Stanchion"
	var top := rim_y + BOARD_LIFT + BOARD_HALF_H - 0.10
	var cyl := CylinderMesh.new()
	cyl.top_radius = POLE_RADIUS
	cyl.bottom_radius = POLE_RADIUS
	cyl.height = top
	mi.mesh = cyl
	mi.material_override = _metal(STANCHION_GREY, 0.5)
	# Local Y is measured from rim height, so the pole centre sits below it.
	mi.position = Vector3(out * POLE_SETBACK, top * 0.5 - rim_y, 0.0)
	return mi

func _base(out: float, rim_y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Padded_Base"
	var box := BoxMesh.new()
	box.size = BASE_SIZE
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PAD_BLACK
	mat.roughness = 0.85
	mi.material_override = mat
	mi.position = Vector3(out * POLE_SETBACK, BASE_SIZE.y * 0.5 - rim_y, 0.0)
	return mi

func _metal(col: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.6
	mat.roughness = rough
	return mat
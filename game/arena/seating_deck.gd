extends RefCounted
class_name SeatingDeck
## The concrete the crowd sits on: a stepped bowl of treads and risers under the
## modelled fans, a dark apron between the court and the first row, and the
## courtside chairs and scorer's table along the near sidelines.
##
## Before this existed the fans floated over a flat black void, which read as a
## hole in the arena rather than a stand. Every dimension is derived from
## CrowdFans so the steps land exactly under the rows - change the crowd layout
## and the concrete follows it.

const ARC_DEG := CrowdFans.ARC_DEG
const SEGMENTS := 72
const TREAD_OVERHANG := 0.55   ## how far each step reaches past its row of seats

const CONCRETE := Color(0.20, 0.20, 0.23)
const CONCRETE_EDGE := Color(0.28, 0.28, 0.32)
const APRON := Color(0.11, 0.11, 0.13)
const TABLE_TOP := Color(0.16, 0.17, 0.21)

func build(root: Node3D) -> void:
	root.add_child(_bowl())
	root.add_child(_apron())
	for chair_row in _courtside_chairs():
		root.add_child(chair_row)
	root.add_child(_scorers_table())
	print("Seating deck built: %d steps under the crowd" % CrowdFans.ROWS)

## Stepped bowl: a horizontal tread at each row height and a vertical riser
## climbing to it, swept over the same arc the crowd occupies.
func _bowl() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := ARC_DEG * 0.5

	for r in range(CrowdFans.ROWS):
		var rx := CrowdFans.INNER_X + r * CrowdFans.ROW_STEP
		var rz := CrowdFans.INNER_Z + r * CrowdFans.ROW_STEP
		var y := 0.30 + r * CrowdFans.ROW_RISE
		var y_below := 0.0 if r == 0 else 0.30 + (r - 1) * CrowdFans.ROW_RISE
		var in_x := rx - TREAD_OVERHANG
		var in_z := rz - TREAD_OVERHANG
		var out_x := rx + CrowdFans.ROW_STEP - TREAD_OVERHANG
		var out_z := rz + CrowdFans.ROW_STEP - TREAD_OVERHANG

		for i in range(SEGMENTS):
			var a0 := deg_to_rad(-half + ARC_DEG * float(i) / float(SEGMENTS))
			var a1 := deg_to_rad(-half + ARC_DEG * float(i + 1) / float(SEGMENTS))
			var i0 := Vector3(sin(a0) * in_x, y, -cos(a0) * in_z)
			var i1 := Vector3(sin(a1) * in_x, y, -cos(a1) * in_z)
			var o0 := Vector3(sin(a0) * out_x, y, -cos(a0) * out_z)
			var o1 := Vector3(sin(a1) * out_x, y, -cos(a1) * out_z)
			_quad(st, i0, o0, o1, i1)                       # tread
			_quad(st, Vector3(i0.x, y_below, i0.z), i0, i1, Vector3(i1.x, y_below, i1.z))  # riser

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Seating_Deck"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CONCRETE
	mat.roughness = 0.92
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi

## Flat dark apron filling the gap between the painted court and the first step,
## so the floor reads as continuous rather than ending in a void.
func _apron() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Courtside_Apron"
	var plane := PlaneMesh.new()
	plane.size = Vector2(CrowdFans.INNER_X * 2.2, CrowdFans.INNER_Z * 2.2)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = APRON
	mat.roughness = 0.75
	mi.material_override = mat
	mi.position = Vector3(0.0, -0.02, 0.0)
	return mi

## Two rows of courtside chairs along the sidelines, just off the painted floor.
func _courtside_chairs() -> Array[MultiMeshInstance3D]:
	var rows: Array[MultiMeshInstance3D] = []
	for side in [-1.0, 1.0]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _chair_mesh()
		var count := 26
		mm.instance_count = count
		for i in count:
			var t := float(i) / float(count - 1)
			var x := lerpf(-12.5, 12.5, t)
			var basis := Basis(Vector3.UP, 0.0 if side < 0.0 else PI)
			mm.set_instance_transform(i, Transform3D(basis, Vector3(x, 0.0, side * 9.1)))
			mm.set_instance_color(i, Color(0.12, 0.12, 0.15))
		var node := MultiMeshInstance3D.new()
		node.name = "Courtside_Chairs_%s" % ("near" if side > 0.0 else "far")
		node.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.14, 0.14, 0.17)
		mat.roughness = 0.7
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rows.append(node)
	return rows

func _chair_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0.0, 0.42, 0.0), Vector3(0.48, 0.06, 0.46))    # seat pan
	_box(st, Vector3(0.0, 0.66, -0.21), Vector3(0.48, 0.44, 0.06))  # back
	for sx in [-0.19, 0.19]:
		for sz in [-0.19, 0.19]:
			_box(st, Vector3(sx, 0.21, sz), Vector3(0.05, 0.42, 0.05))
	st.generate_normals()
	return st.commit()

## Scorer's table on the far sideline - the piece that tells the eye this is a
## televised game and not a practice court.
func _scorers_table() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(st, Vector3(0.0, 0.38, 0.0), Vector3(9.0, 0.76, 0.7))
	_box(st, Vector3(0.0, 0.79, 0.0), Vector3(9.2, 0.06, 0.86))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Scorers_Table"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TABLE_TOP
	mat.roughness = 0.55
	mat.metallic = 0.15
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.0, -8.9)
	return mi

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)

func _box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var c := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, h.y, -h.z), center + Vector3(-h.x, h.y, -h.z),
		center + Vector3(-h.x, -h.y, h.z), center + Vector3(h.x, -h.y, h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	for f in [[0,1,2,3],[5,4,7,6],[4,0,3,7],[1,5,6,2],[3,2,6,7],[4,5,1,0]]:
		_quad(st, c[f[0]], c[f[1]], c[f[2]], c[f[3]])
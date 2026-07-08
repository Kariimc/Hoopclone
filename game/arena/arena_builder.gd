extends RefCounted
class_name ArenaBuilder
## Underfloor + court-floor texture hydration. Split out of main.gd (audit
## §4.1) — pure cut/paste, zero behavior change. Not a scene node: instance
## with `ArenaBuilder.new()`, call the build methods once from `_ready()`.

const COURT_FLOOR_CANDIDATES := [
	"res://assets/textures/court_floor.jpeg",
	"res://assets/textures/court_floor.png",
	"res://assets/textures/court_floor.jpg",
]

const UNDERFLOOR_SIZE := 60.0
const UNDERFLOOR_Y := -0.05       # between court (Y0) and ArenaFloor (-0.10)

## Drops the hardwood photo onto `root`'s court plane if it's been placed (any
## of the accepted extensions); otherwise the scene's wood-brown fallback
## material stands in untouched.
func apply_court_floor(root: Node3D) -> void:
	var path := ""
	for candidate in COURT_FLOOR_CANDIDATES:
		if ResourceLoader.exists(candidate):
			path = candidate
			break
	if path.is_empty():
		print("Court floor texture not found — using fallback colour.")
		return
	var mesh_node := root.get_node_or_null("Floor/FloorMesh") as MeshInstance3D
	if mesh_node == null:
		return
	var prim := mesh_node.mesh as PrimitiveMesh
	var mat := (prim.material if prim != null else null) as StandardMaterial3D
	if mat == null:
		return
	var tex := load(path) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
		print("Court floor texture applied from %s" % path)

## One oversized dark plane under the whole arena; gaps reveal it, not void.
func build_courtside(root: Node3D) -> void:
	var floor_plane := MeshInstance3D.new()
	floor_plane.name = "Courtside_Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(UNDERFLOOR_SIZE, UNDERFLOOR_SIZE)
	floor_plane.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.08, 0.11)
	mat.roughness = 0.6
	mat.metallic = 0.0
	floor_plane.material_override = mat
	root.add_child(floor_plane)
	floor_plane.position = Vector3(0.0, UNDERFLOOR_Y, 0.0)
	print("Courtside underfloor built: %.0fx%.0f at Y %.2f" % [UNDERFLOOR_SIZE, UNDERFLOOR_SIZE, UNDERFLOOR_Y])

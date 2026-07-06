extends RefCounted
class_name ArenaBuilder
## Arena floor + underfloor builder, extracted from main.gd (Sprint 5 refactor).
## Pure helpers operating on a host Node3D: hydrate the hardwood court photo onto
## the floor plane when it's been hand-placed, and lay one oversized dark plane
## under everything so court-to-stands gaps read as floor, not void.

# The hardwood floor photo doesn't travel with the repo, so the scene must load
# WITHOUT it. When present it's hydrated at runtime; when absent the scene's
# wood-brown fallback colour stands in. Any common image extension.
const COURT_FLOOR_CANDIDATES := [
	"res://assets/textures/court_floor.jpeg",
	"res://assets/textures/court_floor.png",
	"res://assets/textures/court_floor.jpg",
]

# --- Dark underfloor (one big plane under everything; seamless by overshoot) ---
const UNDERFLOOR_SIZE := 60.0
const UNDERFLOOR_Y := -0.05       # between court (Y0) and ArenaFloor (-0.10)

## Drop the hardwood photo onto the court plane if it's been placed (any of the
## accepted extensions); otherwise the scene's wood-brown fallback stands in.
static func apply_court_floor(host: Node3D) -> void:
	var path := ""
	for candidate in COURT_FLOOR_CANDIDATES:
		if ResourceLoader.exists(candidate):
			path = candidate
			break
	if path.is_empty():
		print("Court floor texture not found — using fallback colour.")
		return
	var mesh_node := host.get_node_or_null("Floor/FloorMesh") as MeshInstance3D
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
static func build_courtside(host: Node3D) -> void:
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
	host.add_child(floor_plane)
	floor_plane.position = Vector3(0.0, UNDERFLOOR_Y, 0.0)
	print("Courtside underfloor built: %.0fx%.0f at Y %.2f" % [UNDERFLOOR_SIZE, UNDERFLOOR_SIZE, UNDERFLOOR_Y])

extends Node
class_name AssetLoader
## Apparel hot-swap pipeline. Per the locked art direction, swapping teams is a
## TEXTURE swap on one fixed base mesh — never a regeneration. This loads the
## base player GLB and overrides the jersey surface's albedo + normal maps from a
## team entry in team_manifest.json.
##
## The base mesh + textures are exported from Higgsfield once and live under
## res://assets/ (see assets/team_manifest.json for the Higgsfield job-id map).

const MANIFEST_PATH := "res://assets/team_manifest.json"

var _manifest: Dictionary = {}

func _ready() -> void:
	_manifest = _load_manifest()

func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("AssetLoader: no manifest at %s" % MANIFEST_PATH)
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	return data if typeof(data) == TYPE_DICTIONARY else {}

## Instance the base mesh and dress it in a team's kit. Returns the new node.
func spawn_player(team_id: String, jersey_surface: String = "Jersey") -> Node3D:
	var base_path: String = _manifest.get("base_mesh", "")
	if base_path == "" or not ResourceLoader.exists(base_path):
		push_warning("AssetLoader: base_mesh missing; spawn a placeholder.")
		return Node3D.new()
	var scene: PackedScene = load(base_path)
	var inst: Node3D = scene.instantiate()
	apply_team(inst, team_id, jersey_surface)
	return inst

## Override jersey albedo/normal on every matching MeshInstance3D in `root`.
func apply_team(root: Node, team_id: String, jersey_surface: String = "Jersey") -> void:
	var teams: Dictionary = _manifest.get("teams", {})
	var kit: Dictionary = teams.get(team_id, {})
	if kit.is_empty():
		push_warning("AssetLoader: no kit for team '%s'" % team_id)
		return
	for mi in _find_mesh_instances(root):
		var surf := _surface_index_named(mi, jersey_surface)
		if surf < 0:
			continue
		var mat := StandardMaterial3D.new()
		_assign_tex(mat, "albedo", kit.get("jersey_albedo", ""))
		if kit.has("jersey_normal"):
			mat.normal_enabled = true
			_assign_tex(mat, "normal", kit.get("jersey_normal", ""))
		mi.set_surface_override_material(surf, mat)

func _assign_tex(mat: StandardMaterial3D, slot: String, path: String) -> void:
	var resolved := _resolve(path)
	if resolved == "":
		return
	var tex: Texture2D = load(resolved)
	if slot == "albedo":
		mat.albedo_texture = tex
	elif slot == "normal":
		mat.normal_texture = tex

## Return `path` if it exists, else the same basename with a different common
## image extension (so a dropped .jpg still resolves a manifest .png entry), else "".
func _resolve(path: String) -> String:
	if path == "":
		return ""
	if ResourceLoader.exists(path):
		return path
	var base := path.get_basename()
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var candidate := "%s.%s" % [base, ext]
		if ResourceLoader.exists(candidate):
			return candidate
	return ""

func _find_mesh_instances(node: Node, out: Array = []) -> Array:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_find_mesh_instances(c, out)
	return out

func _surface_index_named(mi: MeshInstance3D, surface_name: String) -> int:
	var mesh := mi.mesh
	if mesh == null:
		return -1
	for s in mesh.get_surface_count():
		if mesh.surface_get_material(s) and mi.name.findn(surface_name) >= 0:
			return s
	# Fallback: if there's exactly one surface, dress it.
	return 0 if mesh.get_surface_count() == 1 else -1

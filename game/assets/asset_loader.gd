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
func spawn_player(team_id: String, jersey_surface: String = "Jersey", mesh_path: String = "") -> Node3D:
	var base_path: String = mesh_path if mesh_path != "" else String(_manifest.get("base_mesh", ""))
	if base_path == "" or not ResourceLoader.exists(base_path):
		push_warning("AssetLoader: base_mesh missing; spawn a placeholder.")
		return Node3D.new()
	var scene: PackedScene = load(base_path)
	var inst: Node3D = scene.instantiate()
	apply_team(inst, team_id, jersey_surface)
	return inst

## Dress `root` in a team's kit.
##
## IMPORTANT (measured 2026-07-29): the base model is a SINGLE mesh with a
## SINGLE surface carrying one baked full-body texture - face, arms, shorts and
## all. The kit files in the manifest are flat 2D garment layouts (front panel,
## back panel, shorts on a white sheet), NOT textures unwrapped to this model's
## UVs. Assigning one as the albedo therefore paints the garment artwork across
## the whole character, face included. That is exactly what it used to do.
##
## So a kit swap tints the existing baked texture toward the team's primary
## colour and leaves the artwork alone. A team entry may opt into a real texture
## swap by setting `"jersey_uv_matched": true`, which is only correct once
## somebody authors a kit unwrapped to this model.
func apply_team(root: Node, team_id: String, jersey_surface: String = "Jersey") -> void:
	var teams: Dictionary = _manifest.get("teams", {})
	var kit: Dictionary = teams.get(team_id, {})
	if kit.is_empty():
		push_warning("AssetLoader: no kit for team '%s'" % team_id)
		return

	var uv_matched: bool = bool(kit.get("jersey_uv_matched", false))
	var tint := _team_tint(kit)

	for mi in _find_mesh_instances(root):
		var surf := _surface_index_named(mi, jersey_surface)
		if surf < 0:
			continue
		var mat := StandardMaterial3D.new()
		var src := mi.mesh.surface_get_material(surf) as StandardMaterial3D
		if src != null:
			mat.albedo_texture = src.albedo_texture
			mat.normal_enabled = src.normal_enabled
			mat.normal_texture = src.normal_texture
			mat.roughness = src.roughness
			mat.metallic = src.metallic
		if uv_matched:
			_assign_tex(mat, "albedo", kit.get("jersey_albedo", ""))
			if kit.has("jersey_normal"):
				mat.normal_enabled = true
				_assign_tex(mat, "normal", kit.get("jersey_normal", ""))
		else:
			mat.albedo_color = tint
		mi.set_surface_override_material(surf, mat)

## A gentle wash of the team's primary colour - enough to tell the sides apart
## on a broadcast camera without turning the player into a solid silhouette.
func _team_tint(kit: Dictionary) -> Color:
	var hex: String = String(kit.get("primary", ""))
	if hex == "" or not hex.begins_with("#"):
		return Color.WHITE
	var team := Color(hex)
	return Color.WHITE.lerp(team, 0.45)

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

extends Node3D
## Sprint 1 bootstrap scene. Wires the broadcast camera to a ball stand-in,
## spawns one attribute-driven player from exported roster JSON (if present),
## and starts the UI pollers. This is the "engine spine" smoke scene — a
## playable confirmation that camera + player + data + UI all light up.

@export var roster_json: String = "res://data/rosters/crimson.json"

func _ready() -> void:
	var gs := GameState.new()
	add_child(gs)
	gs.set_phase(GameState.Phase.LIVE)

	var roster := _load_roster(roster_json)
	if roster.size() > 0:
		print("Loaded %d players from %s" % [roster.size(), roster_json])
	else:
		print("No roster JSON yet — run tools/data/export_roster.py first.")

	# Wire the broadcast camera to follow the player. Until the real ball lands
	# in Sprint 5, the player is the focus node; set_target() tracks its X with
	# easing lag and clamps to max_pan_x so the rig never overshoots a baseline.
	var cam := $BroadcastCamera as BroadcastCamera
	var player := $Player as Player
	if cam != null and player != null:
		cam.set_target(player)

	# Build the left/right crowd stands in code, reusing the back wall's
	# (Stands_Far) material so texture / unshaded / cull / tiling all carry.
	_build_side_stands()

func _build_side_stands() -> void:
	var back := get_node_or_null("Stands_Far") as MeshInstance3D
	if back == null:
		push_warning("Stands_Far not found — skipping side stands.")
		return
	var mat := back.get_active_material(0)
	if mat == null:
		push_warning("Stands_Far has no material — skipping side stands.")
		return
	# Left stand sits just outside the -X baseline, facing in (+X). Right stand
	# mirrors it. Walls are upright (no rake) so there is no Euler ambiguity.
	_spawn_stand("Stands_Left", Vector3(-19.0, 8.0, -2.0), 90.0, mat)
	_spawn_stand("Stands_Right", Vector3(19.0, 8.0, -2.0), -90.0, mat)

func _spawn_stand(stand_name: String, pos: Vector3, yaw_deg: float, src_mat: Material) -> void:
	var wall := MeshInstance3D.new()
	wall.name = stand_name
	var quad := QuadMesh.new()
	quad.size = Vector2(24.0, 16.0)
	wall.mesh = quad
	# Duplicate so each wall owns its material; narrow the tiling to keep the
	# crowd the same on-screen scale as the wider back wall (~half the width).
	var m := src_mat.duplicate()
	var sm := m as StandardMaterial3D
	if sm != null:
		sm.uv1_scale = Vector3(2.0, sm.uv1_scale.y, 1.0)
	wall.material_override = m
	add_child(wall)
	wall.position = pos
	wall.rotation_degrees = Vector3(0.0, yaw_deg, 0.0)

func _load_roster(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		return []
	var players: Array = []
	for team in data.get("teams", []):
		for p in team.get("players", []):
			players.append(p)
	return players

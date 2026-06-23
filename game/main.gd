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

extends Node3D
## Sprint 1 bootstrap scene. Broadcast camera + attribute-driven player from
## roster JSON + UI pollers. `_ready()` orchestrates; the actual work lives in
## dedicated modules (audit §4.1 split):
##   - game/arena/crowd_bowl.gd    — curved crowd wall + shader + intensity hook
##   - game/arena/arena_builder.gd — underfloor + court-floor texture hydration
##   - game/boot/spawner.gd        — player body, ball, defender spawning

@export var roster_json: String = "res://data/rosters/crimson.json"
## Team kit the boot player wears (key in assets/team_manifest.json: CRW/STM/BAY).
@export var player_team: String = "CRW"

## The shared phase tracker lives as the "GameState" autoload; this preload is
## only here so the Phase names resolve at parse time.
const GameStateScript := preload("res://game/core/game_state.gd")

var _crowd := CrowdBowl.new()
var _arena := ArenaBuilder.new()
var _spawner := Spawner.new()

func _ready() -> void:
	var gs := get_node("/root/GameState")
	gs.set_phase(GameStateScript.Phase.LIVE)

	var roster := _load_roster(roster_json)
	if roster.size() > 0:
		print("Loaded %d players from %s" % [roster.size(), roster_json])
	else:
		print("No roster JSON yet — run tools/data/export_roster.py first.")

	var cam := $BroadcastCamera as BroadcastCamera
	var player := $Player as Player
	if cam != null and player != null:
		cam.set_target(player)

	_spawner.apply_roster_to_player(player, roster)
	_arena.apply_court_floor(self)
	_spawner.ensure_player_body(self, player, player_team)
	_spawner.equip_player_shot(self, player, _on_basket_made)
	_spawner.spawn_defender(self, player)
	_crowd.build(self)
	_arena.build_courtside(self)

func _on_basket_made() -> void:
	# Crowd roars on a make, then eases back to idle.
	_crowd.set_intensity(1.0)
	var tw := create_tween()
	tw.tween_method(_crowd.set_intensity, 1.0, CrowdBowl.CROWD_IDLE_INTENSITY, 2.5)

## Gameplay hook (Sprint 5): call on a made basket / big play to spike the crowd,
## then ease the value back toward idle from the caller. 0 = idle, 1 = roaring.
func set_crowd_intensity(v: float) -> void:
	_crowd.set_intensity(v)

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

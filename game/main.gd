extends Node3D
## Sprint 1 bootstrap scene. Broadcast camera + attribute-driven player from
## roster JSON + UI pollers. `_ready()` orchestrates; the actual work lives in
## dedicated modules (audit §4.1 split):
##   - game/arena/crowd_bowl.gd    — curved crowd wall + shader + intensity hook
##   - game/arena/arena_builder.gd — underfloor + court-floor texture hydration
##   - game/boot/spawner.gd        — player body, ball, defender spawning

@export var roster_json: String = "res://data/rosters/league.json"
## Who is on the floor. Both must exist in the roster JSON and in
## assets/team_manifest.json, which supplies their colours.
@export var away_team: String = "STM"
## Team kit the boot player wears (key in assets/team_manifest.json: CRW/STM/BAY).
@export var player_team: String = "CRW"

## The shared phase tracker lives as the "GameState" autoload; this preload is
## only here so the Phase names resolve at parse time.
const GameStateScript := preload("res://game/core/game_state.gd")

var _crowd := CrowdBowl.new()
var _arena := ArenaBuilder.new()
var _spawner := Spawner.new()
var _hoops := HoopBuilder.new()
var _deck := SeatingDeck.new()

func _ready() -> void:
	var gs := get_node("/root/GameState")
	gs.set_phase(GameStateScript.Phase.LIVE)

	var teams := _load_teams(roster_json)
	var roster: Array = teams.get(player_team, [])
	var away_roster: Array = teams.get(away_team, [])
	if roster.size() > 0:
		print("Loaded %s (%d) and %s (%d) from %s"
			% [player_team, roster.size(), away_team, away_roster.size(), roster_json])
	else:
		print("No roster JSON yet — run tools/data/export_roster.py first.")

	var cam := $BroadcastCamera as BroadcastCamera
	var player := $Player as Player
	if cam != null and player != null:
		cam.set_target(player)

	_spawner.apply_roster_to_player(player, roster)
	_arena.apply_court_floor(self)
	_hoops.build_all(self)
	_spawner.ensure_player_body(self, player, player_team)
	_spawner.equip_player_shot(self, player, _on_basket_made)
	_spawner.spawn_defender(self, player, away_team)
	_spawner.spawn_team_mates(self, player, roster, away_roster, player_team, away_team)
	_crowd.build(self)
	_arena.build_courtside(self)
	_deck.build(self)
	add_child(BuildFeed.new())
	add_child(SessionRecorder.new())

func _on_basket_made() -> void:
	# Crowd roars on a make, then eases back to idle.
	_crowd.set_intensity(1.0)
	var tw := create_tween()
	tw.tween_method(_crowd.set_intensity, 1.0, CrowdBowl.CROWD_IDLE_INTENSITY, 2.5)

## Gameplay hook (Sprint 5): call on a made basket / big play to spike the crowd,
## then ease the value back toward idle from the caller. 0 = idle, 1 = roaring.
func set_crowd_intensity(v: float) -> void:
	_crowd.set_intensity(v)

## Roster JSON split by team abbreviation, so both sides can be fielded from one
## file. Previously every team was flattened into one list, which is why only the
## first player of the first team was ever used.
func _load_teams(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for team in data.get("teams", []):
		out[String(team.get("abbreviation", "?"))] = team.get("players", [])
	return out

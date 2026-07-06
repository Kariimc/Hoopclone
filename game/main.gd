extends Node3D
## Sprint 1 bootstrap scene. Broadcast camera + attribute-driven player from
## roster JSON + UI pollers. Crowd is one continuous curved arc (no corner seams)
## that wraps the far side and both baskets but stays OPEN behind the camera, so
## the broadcast cam never clips into a near wall when it pans toward a basket.
## Dark underfloor keeps court-to-stands gaps reading as floor, not void.
##
## This file is now just _ready() orchestration. The heavy lifting lives in
## extracted helpers (Sprint 5 refactor): CrowdBowl (game/arena/crowd_bowl.gd),
## ArenaBuilder (game/arena/arena_builder.gd), and Spawner (game/boot/spawner.gd).

@export var roster_json: String = "res://data/rosters/crimson.json"
## Team kit the boot player wears (key in assets/team_manifest.json: CRW/STM/BAY).
@export var player_team: String = "CRW"

# Optional hand-placed binaries (the rigged player GLB, the hardwood floor photo,
# the leather ball skin) are gitignored; see docs/ASSET_INDEX.md. The scene loads
# and runs WITHOUT them — the helpers fall back to placeholders — and lights up
# automatically when the real files are dropped in. No code change needed.

var _crowd_mat: ShaderMaterial    # held so gameplay can crank hype later

func _ready() -> void:
	var gs := GameState.new()
	add_child(gs)
	gs.set_phase(GameState.Phase.LIVE)

	var roster := _load_roster(roster_json)
	if roster.size() > 0:
		print("Loaded %d players from %s" % [roster.size(), roster_json])
	else:
		print("No roster JSON yet — run tools/data/export_roster.py first.")

	var cam := $BroadcastCamera as BroadcastCamera
	var player := $Player as Player
	if cam != null and player != null:
		cam.set_target(player)

	Spawner.apply_roster_to_player(player, roster)
	ArenaBuilder.apply_court_floor(self)
	Spawner.ensure_player_body(self, player, player_team)
	Spawner.equip_player_shot(self, player, _on_basket_made)
	Spawner.spawn_defender(self, player)
	_crowd_mat = CrowdBowl.build(self)
	ArenaBuilder.build_courtside(self)

func _on_basket_made() -> void:
	# Crowd roars on a make, then eases back to idle.
	_set_crowd_intensity(1.0)
	var tw := create_tween()
	tw.tween_method(_set_crowd_intensity, 1.0, CrowdBowl.IDLE_INTENSITY, 2.5)

## Thin wrapper so the tween has a bindable Callable; delegates to the crowd hook.
func _set_crowd_intensity(v: float) -> void:
	CrowdBowl.set_intensity(_crowd_mat, v)

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

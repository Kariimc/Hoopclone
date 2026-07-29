extends RefCounted
class_name Spawner
## Player body, ball, and defender spawning + roster hydration. Split out of
## main.gd (audit §4.1) — pure cut/paste, zero behavior change. Not a scene
## node: instance with `Spawner.new()`, call methods once from `_ready()`,
## passing the scene root to add children to.

## The animated build of the player. It is the SAME model with motion-capture
## clips baked onto its skeleton (see tools/mocap/retarget_bvh.py); the bare
## model is the fallback so the scene still runs before any clip is generated.
const PLAYER_MESH_GLB := "res://assets/models/player_animated.glb"
const PLAYER_MESH_FALLBACK := "res://assets/models/player_base.glb"

## Which clip a body idles on. Everyone stands and handles the ball until the
## state machine starts driving them properly.
const DEFAULT_CLIP := "dribble"

## The real ball. Generated at photoreal quality then cut down to a game budget
## (3k triangles, 2K colour/normal/ORM maps, 0.7 MB) - all the detail that reads
## at broadcast distance lives in the normal map, not in raw geometry.
const BALL_MESH := "res://assets/models/basketball.glb"

# Ball skin (the locked leather photo). Dropped in via ADD-ASSETS; orange fallback
# until then. Albedo + optional derived normal map, any common image extension.
const BALL_ALBEDO_CANDIDATES := [
	"res://assets/textures/ball_albedo.png",
	"res://assets/textures/ball_albedo.jpg",
	"res://assets/textures/ball_albedo.jpeg",
	"res://assets/textures/ball_albedo.webp",
]
const BALL_NORMAL_CANDIDATES := [
	"res://assets/textures/ball_normal.png",
	"res://assets/textures/ball_normal.jpg",
	"res://assets/textures/ball_normal.jpeg",
	"res://assets/textures/ball_normal.webp",
]

## First path in `candidates` that exists on disk, or "" if none are present.
static func _first_existing(candidates: Array) -> String:
	for path in candidates:
		if ResourceLoader.exists(path):
			return path
	return ""

## Make the boot player attribute-driven: hydrate it from the first roster
## entry so Speed / Shooting / defensive ratings reflect real data instead of
## the flat-50 defaults. Read at call-time by max_speed() and the shot model.
## NOTE (audit §3.4): only roster[0] is used; Sprint 5's box score needs the
## full 5-on-5 mapping — flagged here, not yet built.
func apply_roster_to_player(player: Node3D, roster: Array) -> void:
	if player == null or roster.is_empty() or not (player is Player):
		return
	(player as Player).attributes = Attributes.from_json(roster[0])
	print("Player attributes from roster: %s" % roster[0].get("name", "?"))

## Instance the rigged GLB if it's been placed; otherwise spawn a capsule
## placeholder so the player is visible and later sprints aren't blocked on art.
func ensure_player_body(root: Node3D, player: Node3D, player_team: String) -> void:
	if player == null:
		return
	if ResourceLoader.exists(PLAYER_MESH_GLB):
		# Dress the mesh in the team kit via the apparel pipeline (texture swap on
		# the fixed base mesh — the locked art-direction rule). Jersey textures
		# that aren't placed yet are simply skipped, so the bare mesh still shows.
		var loader := AssetLoader.new()
		root.add_child(loader)
		var inst := loader.spawn_player(player_team, "Jersey", PLAYER_MESH_GLB)
		inst.name = "player_base"
		player.add_child(inst)
		var driver := _play_clip(inst, player)
		if driver != null and player is Player:
			(player as Player).clip_driver = driver
		print("Player mesh instanced + dressed (%s) from %s" % [player_team, PLAYER_MESH_GLB])
		return
	print("Player mesh not found (%s) — using capsule placeholder." % PLAYER_MESH_GLB)
	var ph := MeshInstance3D.new()
	ph.name = "PlaceholderBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.9
	ph.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.20, 0.18)   # crimson, matches the team
	ph.material_override = mat
	ph.position = Vector3(0.0, 0.95, 0.0)   # stand the capsule on the floor
	player.add_child(ph)

## Sprint 5: actually wire the shot so the defender's contest can affect it.
## Without a ball + rim, ShotController.start_charge() no-ops and the whole
## contest chain is dead. Spawn a visible ball, equip it against the right hoop,
## and connect `on_made` (the documented Sprint 5 crowd hook) to the ball's
## `made` signal.
func equip_player_shot(root: Node3D, player: Node3D, on_made: Callable) -> void:
	if not (player is Player):
		return
	var rim := root.get_node_or_null("RightHoop") as Node3D
	if rim == null:
		return
	var ball := Ball.new()
	ball.name = "Ball"
	root.add_child(ball)
	ball.add_child(_ball_visual())
	ball.global_position = player.global_position + Vector3(0.0, 1.0, 0.0)
	(player as Player).equip(ball, rim)
	ball.made.connect(on_made)
	print("Player equipped: ball + RightHoop. Hold 'shoot' to fire.")

## Sprint 5: an on-ball defender that marks the player and protects the right
## basket, sliding to stay in the lane. Its positioning feeds ContestModel, so
## a contested shot's make % drops.
func spawn_defender(root: Node3D, player: Node3D, away_team: String = "STM") -> void:
	if player == null:
		return
	var rim := root.get_node_or_null("RightHoop") as Node3D
	if rim == null:
		return
	var defender := Defender.new()
	defender.name = "Defender"
	# Match the attacker's Speed so the only gap is the defender's lower base
	# speed (3.8 vs 4.0) — a touch slower, beatable with a first step, exactly as
	# decided. Defensive ratings stay high so the contest actually bites.
	var atk_speed := 50
	if player is Player:
		atk_speed = (player as Player).attributes.get_attr("speed")
	defender.attributes = Attributes.new({"perim_d": 74, "inside_d": 70, "speed": atk_speed})
	root.add_child(defender)
	defender.global_position = Vector3(3.0, 0.0, 0.0)   # between player and right hoop
	defender.assign(player, rim)

	# Give the body a collider + a visible capsule (contrasting colour vs the player).
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.9
	col.shape = shape
	col.position = Vector3(0.0, 0.95, 0.0)
	defender.add_child(col)
	_dress(root, defender, away_team)

	# Register the defender so a taken shot is contested. Safe even before the
	# shot is equipped with a ball/rim — set_defenders just stores the list.
	# audit §3.3: warn instead of silently no-op if the shot was never equipped
	# (e.g. a future reorder of the _ready() chain), since an unregistered
	# defender means every shot is uncontested with no visible symptom.
	if player is Player and (player as Player).shot != null:
		var marking: Array[Defender] = [defender]
		(player as Player).shot.set_defenders(marking)
		print("Defender spawned: marks the player, protects RightHoop.")
	else:
		push_warning("Defender spawned but shot is not equipped — shots will be uncontested.")


## Give a body the real player model in a team's colours, falling back to a
## coloured capsule only if the model is missing, so the scene never breaks.
func _dress(root: Node3D, body: Node3D, team_id: String) -> void:
	var mesh_path := PLAYER_MESH_GLB if ResourceLoader.exists(PLAYER_MESH_GLB) else PLAYER_MESH_FALLBACK
	if ResourceLoader.exists(mesh_path):
		var loader := AssetLoader.new()
		root.add_child(loader)
		var inst := loader.spawn_player(team_id, "Jersey", mesh_path)
		inst.name = "body_%s" % team_id
		body.add_child(inst)
		_play_clip(inst, body)
		return
	var ph := MeshInstance3D.new()
	ph.name = "PlaceholderBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.9
	ph.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.55)
	ph.material_override = mat
	ph.position = Vector3(0.0, 0.95, 0.0)
	body.add_child(ph)

## Half-court set: where the other four of each side stand. Offence attacks the
## right basket, so the defence sits between them and it.
const HOME_SPOTS := [
	Vector3(5.4, 0.0, -5.6), Vector3(5.4, 0.0, 5.6),
	Vector3(9.2, 0.0, -3.0), Vector3(9.2, 0.0, 3.0),
]
const AWAY_SPOTS := [
	Vector3(7.2, 0.0, -4.6), Vector3(7.2, 0.0, 4.6),
	Vector3(10.6, 0.0, -2.2), Vector3(10.6, 0.0, 2.2),
]

## Fill the floor out to five a side around the controlled player and the on-ball
## defender that already exist.
##
## The four extra defenders are real Defender bodies but are never `assign()`ed a
## man, so they hold their spot instead of all chasing the ball - that is the
## whole difference between a set defence and five players in a heap. They ARE
## registered on the shot, so the contest model sees every one of them and a shot
## taken into a crowd is properly punished.
func spawn_team_mates(root: Node3D, player: Node3D, home: Array, away: Array,
		home_team: String, away_team: String) -> void:
	for i in HOME_SPOTS.size():
		var mate := Defender.new()          # a body that holds position; no man assigned
		mate.name = "Home_%d" % i
		mate.attributes = _attrs_for(home, i + 1)
		root.add_child(mate)
		mate.global_position = HOME_SPOTS[i]
		_dress(root, mate, home_team)

	var opponents: Array[Defender] = []
	for i in AWAY_SPOTS.size():
		var opp := Defender.new()
		opp.name = "Away_%d" % i
		opp.attributes = _attrs_for(away, i + 1)
		root.add_child(opp)
		opp.global_position = AWAY_SPOTS[i]
		_dress(root, opp, away_team)
		opponents.append(opp)

	if player is Player and (player as Player).shot != null:
		var shot := (player as Player).shot
		var all: Array[Defender] = []
		all.append_array(shot.defenders)
		all.append_array(opponents)
		shot.set_defenders(all)
		print("Teams on the floor: 5 %s vs 5 %s (%d contesting)" % [home_team, away_team, all.size()])
	else:
		push_warning("Team mates spawned but the shot is not equipped - shots will be uncontested.")

## Attributes for the nth player of a roster, or league-average if the roster is
## short, so a thin roster still fields five bodies.
func _attrs_for(roster: Array, index: int) -> Attributes:
	if index < roster.size():
		return Attributes.from_json(roster[index])
	return Attributes.new({"perim_d": 60, "inside_d": 60, "speed": 55})

## Start a clip on a freshly instanced body, looping it. Silent if the model has
## no such clip, so a body without animation still spawns and stands.
## Hand the body to a ClipDriver, which picks its clip from how it is moving.
## Returns the driver so the caller can tell it about a shot.
func _play_clip(inst: Node, owner_body: Node3D) -> ClipDriver:
	var ap := _find_anim_player(inst)
	if ap == null:
		return null
	var driver := ClipDriver.new()
	driver.name = "ClipDriver"
	owner_body.add_child(driver)
	driver.setup(ap, owner_body)
	# Start everyone at a different point in the cycle, or ten players move in
	# perfect unison and the whole floor looks like a chorus line.
	if ap.current_animation != "":
		ap.seek(randf() * ap.current_animation_length, true)
	return driver

func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null

## The ball's body: the modelled basketball if it is present, otherwise the old
## textured sphere, so the scene never depends on the asset existing.
func _ball_visual() -> Node3D:
	if ResourceLoader.exists(BALL_MESH):
		var packed: PackedScene = load(BALL_MESH)
		var inst: Node3D = packed.instantiate()
		inst.name = "BallMesh"
		print("Ball: modelled basketball from %s" % BALL_MESH)
		return inst

	var mesh := MeshInstance3D.new()
	mesh.name = "BallMesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.40, 0.15)
	var albedo := _first_existing(BALL_ALBEDO_CANDIDATES)
	if albedo != "":
		mat.albedo_texture = load(albedo) as Texture2D
		mat.albedo_color = Color.WHITE
	var normal := _first_existing(BALL_NORMAL_CANDIDATES)
	if normal != "":
		mat.normal_enabled = true
		mat.normal_texture = load(normal) as Texture2D
	mesh.material_override = mat
	return mesh

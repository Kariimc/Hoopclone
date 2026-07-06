extends RefCounted
class_name Spawner
## Boot-time spawning, extracted from main.gd (Sprint 5 refactor). Pure helpers on
## a host Node3D: the player body (rigged GLB or capsule placeholder), roster
## hydration, the live ball + shot equip, and the on-ball defender. Order and node
## wiring are identical to the original main.gd so behaviour is unchanged.

const PLAYER_MESH_GLB := "res://assets/models/player_base.glb"

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

## Instance the rigged GLB if it's been placed; otherwise spawn a capsule
## placeholder so the player is visible and later sprints aren't blocked on art.
static func ensure_player_body(host: Node3D, player: Node3D, player_team: String) -> void:
	if player == null:
		return
	if ResourceLoader.exists(PLAYER_MESH_GLB):
		# Dress the mesh in the team kit via the apparel pipeline (texture swap on
		# the fixed base mesh — the locked art-direction rule). Jersey textures
		# that aren't placed yet are simply skipped, so the bare mesh still shows.
		var loader := AssetLoader.new()
		host.add_child(loader)
		var inst := loader.spawn_player(player_team)
		inst.name = "player_base"
		player.add_child(inst)
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

## Make the boot player attribute-driven: hydrate it from the first roster entry
## so Speed / Shooting / defensive ratings reflect real data instead of the
## flat-50 defaults. Read at call-time by max_speed() and the shot model.
static func apply_roster_to_player(player: Node3D, roster: Array) -> void:
	if player == null or roster.is_empty() or not (player is Player):
		return
	(player as Player).attributes = Attributes.from_json(roster[0])
	print("Player attributes from roster: %s" % roster[0].get("name", "?"))

## Sprint 5: actually wire the shot so the defender's contest can affect it.
## Without a ball + rim, ShotController.start_charge() no-ops and the whole
## contest chain is dead. Spawn a visible ball, equip it against the right hoop,
## and connect `on_made` (the crowd hook) to the ball's `made` signal.
static func equip_player_shot(host: Node3D, player: Node3D, on_made: Callable) -> void:
	if not (player is Player):
		return
	var rim := host.get_node_or_null("RightHoop") as Node3D
	if rim == null:
		return
	var ball := Ball.new()
	ball.name = "Ball"
	host.add_child(ball)
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.40, 0.15)   # orange fallback until the leather photo is dropped in
	var ball_albedo := _first_existing(BALL_ALBEDO_CANDIDATES)
	if ball_albedo != "":
		mat.albedo_texture = load(ball_albedo) as Texture2D
		mat.albedo_color = Color.WHITE   # let the texture show its true colour
		print("Ball albedo applied from %s" % ball_albedo)
	var ball_normal := _first_existing(BALL_NORMAL_CANDIDATES)
	if ball_normal != "":
		mat.normal_enabled = true
		mat.normal_texture = load(ball_normal) as Texture2D
	mesh.material_override = mat
	ball.add_child(mesh)
	ball.global_position = player.global_position + Vector3(0.0, 1.0, 0.0)
	(player as Player).equip(ball, rim)
	ball.made.connect(on_made)
	print("Player equipped: ball + RightHoop. Hold 'shoot' to fire.")

## Sprint 5: an on-ball defender that marks the player and protects the right
## basket, sliding to stay in the lane. Its positioning feeds ContestModel, so a
## contested shot's make % drops.
static func spawn_defender(host: Node3D, player: Node3D) -> void:
	if player == null:
		return
	var rim := host.get_node_or_null("RightHoop") as Node3D
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
	host.add_child(defender)
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
	var body := MeshInstance3D.new()
	body.name = "DefenderBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.9
	body.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.32, 0.62)   # blue, the opposing kit
	body.material_override = mat
	body.position = Vector3(0.0, 0.95, 0.0)
	defender.add_child(body)

	# Register the defender so a taken shot is contested. If the shot never got a
	# ShotController (player isn't a Player, or _ready hasn't run), registration
	# would silently no-op and EVERY shot would be uncontested with no error — so
	# make that failure loud instead of invisible.
	if player is Player and (player as Player).shot != null:
		var marking: Array[Defender] = [defender]
		(player as Player).shot.set_defenders(marking)
	else:
		push_warning("Defender NOT registered: player.shot is null (shot never equipped — RightHoop missing, or Player._ready hasn't run). Every shot will be uncontested.")
	print("Defender spawned: marks the player, protects RightHoop.")

extends CharacterBody3D
class_name Teammate
## An off-ball player on the attacking side.
##
## Real basketball off the ball is not standing still and it is not chasing the
## ball either - it is holding a shape and moving inside it. So each teammate
## keeps a HOME SPOT in the half-court set and drifts around it: short repositions
## most of the time, an occasional hard cut toward the basket and back out.
##
## Deliberately not an AI: no decisions, no awareness, no ball. Its whole job is
## to stop the floor looking like a photograph until the possession engine exists
## to give these bodies real intent. When that lands, this is what it replaces.

@export var base_speed: float = 3.6
@export var speed_per_point: float = 0.045
@export var accel: float = 22.0
@export var court_half_x: float = 13.0
@export var court_half_z: float = 7.0

## How far from its home spot this player will drift on a normal reposition.
@export var drift_radius: float = 2.6
## Seconds between repositions, randomised per player so nobody moves in step.
@export var settle_min: float = 1.4
@export var settle_max: float = 3.6
## Chance a reposition is a hard cut to the rim instead of a small adjustment.
@export var cut_chance: float = 0.22

var attributes: Attributes
var anim: AnimStateMachine

var home_spot: Vector3 = Vector3.ZERO
var basket: Node3D

var _target: Vector3 = Vector3.ZERO
var _wait := 0.0
var _cutting := false
var _rng := RandomNumberGenerator.new()
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

func _ready() -> void:
	# Same layer rule as everyone else: own layer, mask only the floor, so bodies
	# pass through each other instead of shoving one another down the court.
	collision_layer = 2
	collision_mask = 1
	if attributes == null:
		attributes = Attributes.new()
	anim = AnimStateMachine.new()
	add_child(anim)
	_rng.randomize()
	_target = home_spot
	_wait = _rng.randf_range(0.0, settle_max)

func setup(spot: Vector3, target_basket: Node3D) -> void:
	home_spot = spot
	basket = target_basket
	_target = spot

func max_speed() -> float:
	return base_speed + attributes.get_attr("speed") * speed_per_point

func _physics_process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_pick_target()

	var to_target := _target - global_position
	to_target.y = 0.0
	var gap := to_target.length()
	var move := Vector3.ZERO
	if gap > 0.12:
		# Same arrival braking the defender uses: run at speed until the last
		# stride, then ease in, or the body overshoots and jitters on the spot.
		var speed := max_speed() * (1.35 if _cutting else 1.0)
		move = to_target.normalized() * minf(speed, gap * 3.2)

	velocity.x = move_toward(velocity.x, move.x, accel * delta)
	velocity.z = move_toward(velocity.z, move.z, accel * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	_face_travel(delta)
	global_position.x = clampf(global_position.x, -court_half_x, court_half_x)
	global_position.z = clampf(global_position.z, -court_half_z, court_half_z)

	if anim != null:
		var speed_now := Vector2(velocity.x, velocity.z).length()
		anim.update_locomotion(speed_now)

func _pick_target() -> void:
	_wait = _rng.randf_range(settle_min, settle_max)

	if _cutting:
		# A cut always ends by returning to the shape, or the set collapses.
		_cutting = false
		_target = home_spot
		return

	if basket != null and _rng.randf() < cut_chance:
		_cutting = true
		_wait = _rng.randf_range(0.7, 1.2)
		var rim := basket.global_position
		rim.y = 0.0
		var here := home_spot
		here.y = 0.0
		_target = here.lerp(rim, _rng.randf_range(0.45, 0.75))
		return

	var angle := _rng.randf() * TAU
	var reach := _rng.randf_range(0.35, 1.0) * drift_radius
	_target = home_spot + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
	_target.x = clampf(_target.x, -court_half_x, court_half_x)
	_target.z = clampf(_target.z, -court_half_z, court_half_z)

## Turn to face where you are going.
##
## Without this a body slides in any direction while permanently facing the
## camera, which is the single most unnatural thing a 3D character can do - it
## reads as a cardboard cutout being dragged around. Yaw only: a basketball
## player never pitches or rolls.
const TURN_RATE := 9.0

func _face_travel(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < 0.35:
		return
	# The model's own forward is -Z, so aim that at the direction of travel.
	var want := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * TURN_RATE, 0.0, 1.0))

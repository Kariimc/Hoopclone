extends CharacterBody3D
class_name Defender
## Attribute-driven on-ball defender (Sprint 5). Stays between the player it is
## marking and the basket it protects, sliding to cut off the lane. Its position
## relative to the shooter feeds ContestModel, which feeds the shot's make
## probability — so good positioning + a high PerimD/InsideD actually lowers the
## attacker's percentage.
##
## Deliberately beatable: the slide speed is capped a touch under a typical
## attacker so a quick first step can create separation, like real on-ball D.

@export var base_speed: float = 3.8
@export var speed_per_point: float = 0.045
@export var accel: float = 26.0
## How far off the marked player the defender tries to sit, on the basket side.
@export var guard_gap: float = 1.4
## Court bounds (metres from centre), matching the player's clamp.
@export var court_half_x: float = 13.5
@export var court_half_z: float = 7.2

var attributes: Attributes
var anim: AnimStateMachine

## The player being guarded and the basket this defender protects.
var mark: Node3D
var basket: Node3D

## Gravity. Neither body ever leaves the ground in this build, but without it a
## body that slides into another capsule rides UP it and stays there - that is
## how the player ended up standing in mid-air at rim height (verified 2026-07-29).
## Requires a collision shape on the court floor, or everything simply falls.
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


## Collision layers. 1 = the court floor. Players and defenders each get their
## own layer and mask ONLY the floor, so bodies pass through each other.
##
## Why: body-to-body collision bought nothing here - the contest model reads
## POSITIONS, never contacts - but it cost a whole bug class. Measured
## 2026-07-29: the defender slid into the attacker, the attacker climbed onto
## the capsule and was carried at head height (Y 1.897) while the pair drifted
## down the floor together. Real jostling/screens are a later, deliberate
## feature; when that lands, give them a shared layer AND a way not to climb.
func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	if attributes == null:
		attributes = Attributes.new()
	anim = AnimStateMachine.new()
	add_child(anim)
	anim.transition(AnimStateMachine.State.DEF_STANCE)

## Wire the defender to whom it guards and which rim it protects (called by the scene).
func assign(p_mark: Node3D, p_basket: Node3D) -> void:
	mark = p_mark
	basket = p_basket

## Slide speed scales with Speed, like the player, but off a lower base so a
## fresh attacker can turn the corner.
func max_speed() -> float:
	return base_speed + attributes.get_attr("speed") * speed_per_point

## Defensive rating that matters for a given shot: PerimD contesting jumpers /
## threes, InsideD contesting close attempts (mirrors the shot model's
## Shooting-vs-ThreePT split).
func defensive_rating(is_three: bool) -> int:
	return attributes.get_attr("perim_d" if is_three else "inside_d")

func _physics_process(delta: float) -> void:
	var move := Vector3.ZERO
	if mark != null and basket != null:
		var target := _guard_spot()
		var to_target := target - global_position
		to_target.y = 0.0
		var gap := to_target.length()
		if gap > 0.05:
			# Ease off on the approach. Without this the slide runs at full speed
			# right up to the guard spot, overshoots it, body-checks the man being
			# guarded, and shoves him down the floor - the target then moves with
			# him, so the two lock together and never separate. Measured 2026-07-29:
			# attacker driven from X 0 to X 6.6 and riding up onto the defender's
			# capsule at Y 2.59. Proportional braking inside the last metre fixes it.
			move = to_target.normalized() * minf(max_speed(), gap * 4.0)
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

	var speed := Vector2(velocity.x, velocity.z).length()
	# Sliding while cutting off the lane; settle into a stance when matched up.
	if speed > 0.3:
		anim.transition(AnimStateMachine.State.DEF_SLIDE)
	else:
		anim.transition(AnimStateMachine.State.DEF_STANCE)

## The spot guard_gap metres off the mark, toward the basket being protected.
func _guard_spot() -> Vector3:
	var here := mark.global_position
	var to_basket := basket.global_position - here
	to_basket.y = 0.0
	if to_basket.length() < 0.01:
		return here
	return here + to_basket.normalized() * guard_gap

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

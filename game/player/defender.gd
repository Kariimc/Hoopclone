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

func _ready() -> void:
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
		if to_target.length() > 0.05:
			move = to_target.normalized() * max_speed()
	velocity.x = move_toward(velocity.x, move.x, accel * delta)
	velocity.z = move_toward(velocity.z, move.z, accel * delta)
	move_and_slide()
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

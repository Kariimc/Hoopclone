extends Node3D
class_name Ball
## Outcome-first ball flight. Real basketball sims don't trust rigid-body physics
## to decide makes — they roll the outcome, then fly the ball to match (swish,
## bank, or rim-out). This node does the flight + a simple miss bounce and emits
## made / missed when the ball resolves.
##
## launch(from, target, arc_height, flight_time): parabola from->target.
## A make targets the rim centre and drops through; a miss targets an offset
## point on/near the rim and bounces off.

signal made
## Fires when the ball settles after a miss (bounce has stopped, NOT when the
## bounce starts) — this is the "ball is now live for a rebound" moment. Audit
## §3.2: fixed before any consumer could lock in the wrong meaning.
signal missed

@export var gravity_visual: float = 9.8
@export var rim_radius: float = 0.23
@export var bounce_damping: float = 0.55

## How fast the ball pumps when the handler is dribbling, and how far off the
## floor the top of that pump sits relative to the hand.
@export var dribble_hz: float = 2.1
@export var dribble_run_hz: float = 2.9
@export var ball_radius: float = 0.12
## How far in front of the hand the ball rides, so it is not buried inside it.
@export var hand_offset: Vector3 = Vector3(0.0, -0.06, 0.10)

var _flying: bool = false
var _t: float = 0.0
var _dur: float = 1.0
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _arc: float = 2.0
var _will_make: bool = false
var _bounce_vel: Vector3 = Vector3.ZERO
var _bouncing: bool = false

## While held, the ball lives on the handler's hand instead of floating near him.
## This is what makes it read as basketball rather than a prop hanging in space:
## everyone has muscle memory for hand-on-ball contact and notices instantly when
## it is missing.
var _hand: Node3D
var _holder: Node3D
var _held: bool = false
var _dribble_phase: float = 0.0

## Put the ball in a hand. `hand` should be a BoneAttachment3D following the
## handler's hand bone; `holder` is the body itself, read for speed so the pump
## quickens when he moves.
func hold(hand: Node3D, holder: Node3D) -> void:
	_hand = hand
	_holder = holder
	_held = true
	_flying = false
	_bouncing = false

## Let go - called automatically the moment a shot launches.
func release() -> void:
	_held = false

func is_held() -> bool:
	return _held

func launch(from: Vector3, target: Vector3, will_make: bool,
		arc_height: float = 2.2, flight_time: float = 0.9) -> void:
	_from = from
	_to = target
	_arc = arc_height
	_dur = maxf(0.2, flight_time)
	_will_make = will_make
	_t = 0.0
	_flying = true
	_bouncing = false
	_held = false          # a shot always takes the ball out of the hand
	global_position = from

func _physics_process(delta: float) -> void:
	if _held:
		_step_hold(delta)
		return
	if _bouncing:
		_step_bounce(delta)
		return
	if not _flying:
		return
	_t += delta / _dur
	if _t >= 1.0:
		_t = 1.0
		_flying = false
		global_position = _arc_point(1.0)
		_resolve()
		return
	global_position = _arc_point(_t)

## Parabolic interpolation: linear base + sine hump for the arc apex.
func _arc_point(t: float) -> Vector3:
	var base := _from.lerp(_to, t)
	base.y += sin(t * PI) * _arc
	return base

func _resolve() -> void:
	if _will_make:
		made.emit()
	else:
		# Kick off a short bounce off the rim/backboard before the rebound.
		# `missed` fires once the bounce settles (below), not here — a rebound
		# system needs "the ball is now live," not "the animation started."
		_bouncing = true
		_bounce_vel = Vector3(
			randf_range(-1.5, 1.5), randf_range(1.5, 3.0), randf_range(-1.0, 1.0)
		)

func _step_bounce(delta: float) -> void:
	_bounce_vel.y -= gravity_visual * delta
	global_position += _bounce_vel * delta
	if global_position.y <= rim_radius:
		global_position.y = rim_radius
		_bounce_vel.y = -_bounce_vel.y * bounce_damping
		if absf(_bounce_vel.y) < 0.6:
			_bouncing = false  # ball settles -> live for rebound logic
			missed.emit()

## Ride the handler's hand, pumping to the floor and back while he moves.
##
## The pump is procedural rather than baked into the capture: the clip moves the
## hand, and the ball has to meet the FLOOR on every beat regardless of how fast
## the handler happens to be travelling. Standing still, the ball settles into
## the hand instead of bouncing, which is what a real handler does when he picks
## up his dribble.
func _step_hold(delta: float) -> void:
	if _hand == null or not is_instance_valid(_hand):
		_held = false
		return

	var hand_pos := _hand.global_position + _hand.global_transform.basis * hand_offset
	var speed := 0.0
	if _holder is CharacterBody3D:
		var v := (_holder as CharacterBody3D).velocity
		speed = Vector2(v.x, v.z).length()

	if speed < 0.15:
		# Picked up: the ball sits in the hand.
		_dribble_phase = 0.0
		global_position = global_position.lerp(hand_pos, clampf(delta * 18.0, 0.0, 1.0))
		return

	var hz: float = lerpf(dribble_hz, dribble_run_hz, clampf(speed / 5.0, 0.0, 1.0))
	_dribble_phase = fmod(_dribble_phase + delta * hz, 1.0)

	# abs(sin) gives a bounce that touches the floor once per beat with a sharp
	# turnaround, which reads much closer to a real dribble than a smooth wave.
	var lift: float = absf(sin(_dribble_phase * PI))
	var floor_y: float = ball_radius
	var top_y: float = maxf(hand_pos.y, floor_y + 0.25)
	global_position = Vector3(
		lerpf(global_position.x, hand_pos.x, clampf(delta * 14.0, 0.0, 1.0)),
		lerpf(floor_y, top_y, lift),
		lerpf(global_position.z, hand_pos.z, clampf(delta * 14.0, 0.0, 1.0)))

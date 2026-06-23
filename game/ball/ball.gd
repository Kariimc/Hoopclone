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
signal missed

@export var gravity_visual: float = 9.8
@export var rim_radius: float = 0.23
@export var bounce_damping: float = 0.55

var _flying: bool = false
var _t: float = 0.0
var _dur: float = 1.0
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _arc: float = 2.0
var _will_make: bool = false
var _bounce_vel: Vector3 = Vector3.ZERO
var _bouncing: bool = false

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
	global_position = from

func _physics_process(delta: float) -> void:
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
		_bouncing = true
		_bounce_vel = Vector3(
			randf_range(-1.5, 1.5), randf_range(1.5, 3.0), randf_range(-1.0, 1.0)
		)
		missed.emit()

func _step_bounce(delta: float) -> void:
	_bounce_vel.y -= gravity_visual * delta
	global_position += _bounce_vel * delta
	if global_position.y <= rim_radius:
		global_position.y = rim_radius
		_bounce_vel.y = -_bounce_vel.y * bounce_damping
		if absf(_bounce_vel.y) < 0.6:
			_bouncing = false  # ball settles -> live for rebound logic

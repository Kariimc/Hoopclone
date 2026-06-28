extends Node
class_name ShotController
## Ties the green-zone meter to the shot model and the ball. Charge fills a 0-1
## meter; release timing vs the perfect mark becomes a timing_error; distance to
## the rim + the shooter's rating set the make probability; we roll once, pick a
## target (rim centre for a make, an offset for a miss), and launch the ball.

signal shot_taken(made: bool, probability: float, is_three: bool)

## Meter sweeps 0 -> 1 -> 0 (ping-pong). Perfect release is at the top (1.0).
@export var meter_speed: float = 1.6      # full sweeps per second
@export var three_point_distance: float = 7.24
@export var perfect_mark: float = 1.0

var shooter: Player
var ball: Ball
var rim: Node3D
## On-ball defenders that can contest this shot (Sprint 5). Empty = uncontested.
var defenders: Array[Defender] = []

var _charging: bool = false
var _meter: float = 0.0
var _dir: float = 1.0

func setup(p_shooter: Player, p_ball: Ball, p_rim: Node3D) -> void:
	shooter = p_shooter
	ball = p_ball
	rim = p_rim

## Register the defenders whose positioning pressures this shot.
func set_defenders(p_defenders: Array[Defender]) -> void:
	defenders = p_defenders

func is_charging() -> bool:
	return _charging

func meter_value() -> float:
	return _meter

func start_charge() -> void:
	if shooter == null or ball == null or rim == null:
		return
	_charging = true
	_meter = 0.0
	_dir = 1.0

func _process(delta: float) -> void:
	if not _charging:
		return
	_meter += _dir * meter_speed * delta
	if _meter >= 1.0:
		_meter = 1.0
		_dir = -1.0
	elif _meter <= 0.0:
		_meter = 0.0
		_dir = 1.0

func release() -> void:
	if not _charging:
		return
	_charging = false

	var shooter_pos: Vector3 = shooter.global_position
	var rim_pos: Vector3 = rim.global_position
	var distance: float = shooter_pos.distance_to(rim_pos)
	var is_three: bool = distance >= three_point_distance

	var rating: int = shooter.attributes.get_attr(
		"three_pt" if is_three else "shooting"
	)
	var t_err: float = ShotModel.timing_error(_meter - perfect_mark, rating)
	var contest: float = _contest_at(shooter_pos, rim_pos, is_three)
	var prob: float = ShotModel.make_probability(distance, rating, contest, t_err)
	var made: bool = randf() < prob

	var target: Vector3 = rim_pos
	if not made:
		target += Vector3(
			randf_range(-0.35, 0.35), randf_range(-0.1, 0.1),
			randf_range(-0.35, 0.35)
		)

	var flight: float = clampf(0.7 + distance * 0.03, 0.7, 1.4)
	var arc: float = clampf(1.8 + distance * 0.12, 1.8, 3.6)
	ball.launch(shooter_pos + Vector3(0, 2.0, 0), target, made, arc, flight)
	shot_taken.emit(made, prob, is_three)

## Strongest contest from the registered defenders, in [0, 1]. Works in the
## horizontal plane and asks each defender for the rating that matters for this
## shot type (PerimD on threes, InsideD inside). Stale/freed defenders are skipped.
func _contest_at(shooter_pos: Vector3, rim_pos: Vector3, is_three: bool) -> float:
	if defenders.is_empty():
		return 0.0
	var shooter_xz := Vector2(shooter_pos.x, shooter_pos.z)
	var basket_xz := Vector2(rim_pos.x, rim_pos.z)
	var marks: Array = []
	for d in defenders:
		if d == null or not is_instance_valid(d):
			continue
		marks.append({
			"pos": Vector2(d.global_position.x, d.global_position.z),
			"rating": d.defensive_rating(is_three),
		})
	return ContestModel.contest_from_defenders(shooter_xz, basket_xz, marks)

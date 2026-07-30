extends Node
class_name ClipDriver
## Picks which motion-capture clip a body should be playing, every frame.
##
## The clips come from real basketball capture (see tools/mocap/build_moveset.py)
## and are named idle / dribble / run / crossover / jumpshot. This watches how the
## body is actually moving and blends between them, so nobody has to hand-drive
## animation state from gameplay code.
##
## Deliberately tolerant: a missing clip is skipped rather than fatal, so a body
## whose model has no animation still spawns and stands.

const BLEND := 0.22
const SHOT_HOLD := 0.85         ## seconds a shot clip owns the body before it lets go

## Hysteresis on the locomotion thresholds. A single threshold makes the clip
## flicker whenever the player hovers on it, which reads far worse than either
## clip alone: he has to be clearly running before the run starts, and clearly
## slower before it stops.
const RUN_ENTER := 1.6
const RUN_EXIT := 1.1
const MOVE_ENTER := 0.25
const MOVE_EXIT := 0.12

## How fast the capture's own performer was travelling in each locomotion clip.
## Playback is scaled by actual speed over this, so the feet keep up with the
## ground instead of skating - the single biggest thing that makes retargeted
## motion read as natural rather than as animation playing on top of movement.
const CLIP_SPEED := {"dribble": 1.5, "run": 3.2}
const SPEED_SMOOTHING := 8.0

var _anim: AnimationPlayer
var _body: Node3D
var _names: Dictionary = {}     ## logical clip -> the name glTF actually gave it
var _current := ""
var _shot_until := 0.0
var _speed := 0.0

func setup(anim: AnimationPlayer, body: Node3D) -> void:
	_anim = anim
	_body = body
	for logical in ["idle", "dribble", "run", "crossover", "jumpshot"]:
		var resolved := _resolve(logical)
		if resolved != "":
			_names[logical] = resolved
			var a := _anim.get_animation(resolved)
			# Everything loops except the shot, which must finish and hand back.
			a.loop_mode = Animation.LOOP_NONE if logical == "jumpshot" else Animation.LOOP_LINEAR
	if _names.is_empty():
		push_warning("ClipDriver: this body has no known clips (%s)"
			% ", ".join(_anim.get_animation_list()))

## glTF usually prefixes a clip with the armature it belongs to.
func _resolve(logical: String) -> String:
	if _anim.has_animation(logical):
		return logical
	for candidate in _anim.get_animation_list():
		if candidate.ends_with(logical):
			return candidate
	return ""

## Called when the body takes a shot, so the shot clip wins for its duration.
func fire_shot() -> void:
	if not _names.has("jumpshot"):
		return
	_shot_until = _now() + SHOT_HOLD
	_play("jumpshot")

func _process(_delta: float) -> void:
	if _anim == null or _names.is_empty():
		return
	if _now() < _shot_until:
		return

	var raw := 0.0
	if _body is CharacterBody3D:
		var v := (_body as CharacterBody3D).velocity
		raw = Vector2(v.x, v.z).length()
	# Smooth the speed before it decides anything: a single frame of jitter should
	# never change which clip is playing.
	_speed = lerpf(_speed, raw, clampf(_delta * SPEED_SMOOTHING, 0.0, 1.0))

	var want := _current
	match _current:
		"run":
			want = "run" if _speed > RUN_EXIT else ("dribble" if _speed > MOVE_EXIT else "idle")
		"dribble":
			want = "run" if _speed > RUN_ENTER else ("dribble" if _speed > MOVE_EXIT else "idle")
		_:
			want = "run" if _speed > RUN_ENTER else ("dribble" if _speed > MOVE_ENTER else "idle")
	_play(want)

	# Match the clip's tempo to how fast he is actually travelling.
	if CLIP_SPEED.has(_current):
		var reference: float = float(CLIP_SPEED[_current])
		_anim.speed_scale = clampf(_speed / maxf(0.1, reference), 0.55, 1.85)
	else:
		_anim.speed_scale = 1.0

func _play(logical: String) -> void:
	if _current == logical:
		return
	var name := String(_names.get(logical, ""))
	if name == "":
		return
	_current = logical
	_anim.play(name, BLEND)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
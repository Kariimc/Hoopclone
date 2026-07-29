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
const RUN_SPEED := 1.2          ## m/s above which running reads better than handling
const SHOT_HOLD := 0.85         ## seconds a shot clip owns the body before it lets go

var _anim: AnimationPlayer
var _body: Node3D
var _names: Dictionary = {}     ## logical clip -> the name glTF actually gave it
var _current := ""
var _shot_until := 0.0

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

	var speed := 0.0
	if _body is CharacterBody3D:
		var v := (_body as CharacterBody3D).velocity
		speed = Vector2(v.x, v.z).length()

	if speed > RUN_SPEED:
		_play("run")
	elif speed > 0.15:
		_play("dribble")
	else:
		_play("idle")

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
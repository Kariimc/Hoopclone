extends Node
class_name PlayerAnimator
## Bridges AnimStateMachine (logic) to an AnimationTree (visuals). The state
## machine decides WHICH move; this drives the tree's StateMachine playback and
## feeds the locomotion blend space from velocity. Build the tree in-editor (see
## docs/SPRINT4_INEDITOR.md) or generate it with tools/godot/build_animation_tree.gd.
##
## Expected tree shape (parameter paths must match):
##   root = AnimationNodeStateMachine
##     "Locomotion" : AnimationNodeBlendSpace1D  (Idle..Walk..Run..Sprint by speed)
##     one state per action (JUMPSHOT, LAYUP, DUNK, ... ) playing its clip
##   playback param: "parameters/playback"
##   locomotion blend: "parameters/Locomotion/blend_position"

@export var animation_tree_path: NodePath
@export var max_speed_for_blend: float = 7.0

var _tree: AnimationTree
var _playback  # AnimationNodeStateMachinePlayback
var _anim: AnimStateMachine

func setup(anim_state: AnimStateMachine) -> void:
	_anim = anim_state
	_tree = get_node_or_null(animation_tree_path) as AnimationTree
	if _tree == null:
		push_warning("PlayerAnimator: AnimationTree not found at %s" % animation_tree_path)
		return
	_tree.active = true
	_playback = _tree.get("parameters/playback")
	_anim.state_changed.connect(_on_state_changed)

## Call each frame with the player's planar speed (m/s).
func update_locomotion_blend(speed: float) -> void:
	if _tree == null:
		return
	var t: float = clampf(speed / max_speed_for_blend, 0.0, 1.0)
	_tree.set("parameters/Locomotion/blend_position", t)

func _on_state_changed(_from: int, to: int) -> void:
	if _playback == null or _tree == null:
		return
	var state_name := AnimStateMachine.State.keys()[to]
	# Locomotion states all live inside the "Locomotion" blend node.
	if to in [
		AnimStateMachine.State.IDLE, AnimStateMachine.State.WALK,
		AnimStateMachine.State.RUN, AnimStateMachine.State.SPRINT,
	]:
		_travel("Locomotion")
	else:
		_travel(state_name)

func _travel(state_name: String) -> void:
	# Only travel if the tree actually has that state, so a missing clip during
	# bring-up doesn't spam errors.
	if _playback != null:
		_playback.travel(state_name)

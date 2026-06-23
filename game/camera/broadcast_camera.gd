extends Camera3D
class_name BroadcastCamera
## Elevated near-sideline broadcast rig — the locked HoopClone camera.
##
## Court runs left<->right with baskets at the left/right baselines. The camera
## sits high on the near sideline, tilts down moderately, uses a narrow FOV for
## the compressed broadcast look, and tracks the ball's X with easing lag so it
## pans the length of the floor without jitter.

## Height above the floor (metres).
@export var rig_height: float = 7.0
## Distance back from the near sideline (metres).
@export var rig_distance: float = 14.0
## Downward tilt in degrees (negative pitches the lens down).
@export var tilt_degrees: float = -22.0
## Narrow FOV gives the long-lens broadcast compression.
@export var broadcast_fov: float = 30.0
## How far along Z (sideline depth) the rig is centred.
@export var sideline_z: float = 0.0
## Easing factor for horizontal follow (higher = snappier).
@export var follow_lag: float = 2.5
## Clamp horizontal travel so the rig never overshoots the baselines.
@export var max_pan_x: float = 5.0

var _target: Node3D = null
var _current_x: float = 0.0

func _ready() -> void:
	fov = broadcast_fov
	position = Vector3(0.0, rig_height, sideline_z + rig_distance)
	rotation_degrees = Vector3(tilt_degrees, 0.0, 0.0)
	_current_x = position.x

## Assign the ball (or live-action focus) for the rig to track.
func set_target(node: Node3D) -> void:
	_target = node

func _process(delta: float) -> void:
	if _target == null:
		return
	var goal_x: float = clampf(_target.global_position.x, -max_pan_x, max_pan_x)
	_current_x = lerpf(_current_x, goal_x, clampf(follow_lag * delta, 0.0, 1.0))
	position.x = _current_x

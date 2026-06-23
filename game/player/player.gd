extends CharacterBody3D
class_name Player
## Attribute-driven player controller. Movement caps, acceleration, and (later)
## shot/dribble parameters are all scaled by the 13 rated attributes so a 90
## Speed guard genuinely outruns a 58 Speed centre. Sprint 2 layers shot/ball
## physics on top; this is the locomotion + state-machine spine.

@export var base_speed: float = 4.0       # m/s at Speed 0
@export var speed_per_point: float = 0.045 # extra m/s per Speed point
@export var accel: float = 28.0

var attributes: Attributes
var anim: AnimStateMachine

func _ready() -> void:
	if attributes == null:
		attributes = Attributes.new()
	anim = AnimStateMachine.new()
	add_child(anim)

func max_speed() -> float:
	return base_speed + attributes.get_attr("speed") * speed_per_point

func _physics_process(delta: float) -> void:
	var dir := Vector3(
		Input.get_axis("move_left", "move_right"),
		0.0,
		Input.get_axis("move_up", "move_down"),
	)
	var target := dir.normalized() * max_speed() if dir.length() > 0.01 else Vector3.ZERO
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	move_and_slide()
	anim.update_locomotion(Vector2(velocity.x, velocity.z).length())

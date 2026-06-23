extends CharacterBody3D
class_name Player
## Attribute-driven player controller + shooting. Movement caps scale with Speed;
## holding "shoot" charges the green-zone meter and releasing takes the shot via
## ShotController. Sprint 2 makes the shot real; defenders/contest arrive Sprint 5.

@export var base_speed: float = 4.0
@export var speed_per_point: float = 0.045
@export var accel: float = 28.0

var attributes: Attributes
var anim: AnimStateMachine
var shot: ShotController

func _ready() -> void:
	if attributes == null:
		attributes = Attributes.new()
	anim = AnimStateMachine.new()
	add_child(anim)
	shot = ShotController.new()
	add_child(shot)

## Wire the shooter to the live ball + target rim (called by the scene).
func equip(ball: Ball, rim: Node3D) -> void:
	shot.setup(self, ball, rim)

func max_speed() -> float:
	return base_speed + attributes.get_attr("speed") * speed_per_point

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		shot.start_charge()
		anim.transition(AnimStateMachine.State.JUMPSHOT)
	elif event.is_action_released("shoot"):
		shot.release()

func _physics_process(delta: float) -> void:
	# Lock movement while charging a shot (set feet, like a real jumper).
	var move := Vector3.ZERO
	if not shot.is_charging():
		var dir := Vector3(
			Input.get_axis("move_left", "move_right"),
			0.0,
			Input.get_axis("move_up", "move_down"),
		)
		if dir.length() > 0.01:
			move = dir.normalized() * max_speed()
	velocity.x = move_toward(velocity.x, move.x, accel * delta)
	velocity.z = move_toward(velocity.z, move.z, accel * delta)
	move_and_slide()
	anim.update_locomotion(Vector2(velocity.x, velocity.z).length())

extends CharacterBody3D
class_name Player
## Attribute-driven player controller + shooting. Movement caps scale with Speed;
## holding "shoot" charges the green-zone meter and releasing takes the shot via
## ShotController. Sprint 2 makes the shot real; defenders/contest arrive Sprint 5.

@export var base_speed: float = 4.0
@export var speed_per_point: float = 0.045
@export var accel: float = 28.0
## Court bounds (metres from centre). Keeps the player on the visible floor
## so the sideline-panning camera never loses him off an edge of the frame.
@export var court_half_x: float = 11.0
@export var court_half_z: float = 7.0

var attributes: Attributes
var anim: AnimStateMachine
var shot: ShotController
## Set by the spawner; drives which capture clip the body plays.
var clip_driver: ClipDriver
## Set by the scene so a hard cut can squeak. Optional - no audio, no squeak.
var audio: AudioDirector
var _last_dir: Vector3 = Vector3.ZERO
var _squeak_cooldown: float = 0.0

## Gravity. Neither body ever leaves the ground in this build, but without it a
## body that slides into another capsule rides UP it and stays there - that is
## how the player ended up standing in mid-air at rim height (verified 2026-07-29).
## Requires a collision shape on the court floor, or everything simply falls.
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


## Collision layers. 1 = the court floor. Players and defenders each get their
## own layer and mask ONLY the floor, so bodies pass through each other.
##
## Why: body-to-body collision bought nothing here - the contest model reads
## POSITIONS, never contacts - but it cost a whole bug class. Measured
## 2026-07-29: the defender slid into the attacker, the attacker climbed onto
## the capsule and was carried at head height (Y 1.897) while the pair drifted
## down the floor together. Real jostling/screens are a later, deliberate
## feature; when that lands, give them a shared layer AND a way not to climb.
func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
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
		if clip_driver != null:
			clip_driver.fire_shot()

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
	# A sneaker squeaks when a moving foot changes direction hard, not simply when
	# it moves - so this watches the ANGLE between where he was going and where he
	# is going now, and only above a real speed.
	_squeak_cooldown = maxf(0.0, _squeak_cooldown - delta)
	var here := Vector3(velocity.x, 0.0, velocity.z)
	if audio != null and _squeak_cooldown <= 0.0 and here.length() > 1.6 and _last_dir.length() > 1.6:
		var turn := _last_dir.normalized().angle_to(here.normalized())
		if turn > 0.7:
			audio.on_squeak(clampf(turn / PI, 0.35, 1.0))
			_squeak_cooldown = 0.22
	if here.length() > 0.3:
		_last_dir = here

	velocity.x = move_toward(velocity.x, move.x, accel * delta)
	velocity.z = move_toward(velocity.z, move.z, accel * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	global_position.x = clampf(global_position.x, -court_half_x, court_half_x)
	global_position.z = clampf(global_position.z, -court_half_z, court_half_z)
	anim.update_locomotion(Vector2(velocity.x, velocity.z).length())

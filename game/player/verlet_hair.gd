@tool
extends SkeletonModifier3D
class_name VerletHair
## Verlet hair / dread physics — Sprint 4 write-back version.
##
## Sprint 1 shipped the solver as a plain Node3D with a stubbed write-back. This
## supersedes it as a Godot 4 SkeletonModifier3D: it runs inside the skeleton's
## modification phase (after the AnimationTree poses the skeleton), solves the
## strand with Verlet integration, then rotates each chain bone to follow the
## solved points. Because it's a modifier it stays decoupled from the animation
## state machine — the hair swings no matter what the body is doing.
##
## Attach as a child of the Skeleton3D. Set `bone_chain` to the strand's bone
## indices (root -> tip). `bone_forward_axis` MUST match how the rig's bones
## point (most Mixamo/Meshy rigs run bones down +Y); flip it if the hair kinks.

## Strand bone indices, root first.
@export var bone_chain: Array[int] = []
## Which local axis the bones point down (rig-dependent — tune in-editor).
@export var bone_forward_axis: Vector3 = Vector3.UP
## Rest length between consecutive bones (metres).
@export var segment_length: float = 0.06
## Gravity on each free point.
@export var gravity: Vector3 = Vector3(0, -9.8, 0)
## 0..1 velocity retention per step (lower = stiffer / more damped).
@export_range(0.0, 1.0) var damping: float = 0.92
## Constraint solver iterations (more = stiffer, costlier).
@export var iterations: int = 6
## Capsule radius around the head/neck so strands don't clip inward.
@export var collide_radius: float = 0.11

var _points: PackedVector3Array = PackedVector3Array()
var _prev: PackedVector3Array = PackedVector3Array()
var _initialised: bool = false

func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or bone_chain.size() < 2:
		return
	if Engine.is_editor_hint():
		return  # don't simulate in the editor viewport

	var delta := get_physics_process_delta_time()
	if delta <= 0.0:
		delta = 1.0 / 60.0

	if not _initialised:
		_seed_points(skel)

	# Root is pinned to the animated bone.
	var root := _bone_world(skel, bone_chain[0])
	_points[0] = root
	_prev[0] = root

	# Verlet integrate the free points (world space).
	for i in range(1, _points.size()):
		var cur := _points[i]
		var vel := (cur - _prev[i]) * damping
		_prev[i] = cur
		_points[i] = cur + vel + gravity * delta * delta

	_solve(root)
	_write_back(skel)

func _seed_points(skel: Skeleton3D) -> void:
	_points.clear()
	_prev.clear()
	for idx in bone_chain:
		var p := _bone_world(skel, idx)
		_points.append(p)
		_prev.append(p)
	_initialised = true

func _solve(root: Vector3) -> void:
	for _it in iterations:
		_points[0] = root
		for i in range(1, _points.size()):
			var a := _points[i - 1]
			var b := _points[i]
			var dir := b - a
			var dist := dir.length()
			if dist > 0.0001:
				var diff := (dist - segment_length) / dist
				_points[i] = b - dir * diff
			# keep strands outside the head/neck capsule
			var off := _points[i] - root
			if off.length() < collide_radius:
				_points[i] = root + off.normalized() * collide_radius

## Rotate each chain bone so its forward axis points at the next solved point.
func _write_back(skel: Skeleton3D) -> void:
	var skel_inv := skel.global_transform.affine_inverse()
	for i in range(bone_chain.size() - 1):
		var idx := bone_chain[i]
		var dir_world := _points[i + 1] - _points[i]
		if dir_world.length() < 0.0001:
			continue
		var dir_skel := (skel_inv.basis * dir_world).normalized()

		var gpose := skel.get_bone_global_pose(idx)
		var cur_forward := (gpose.basis * bone_forward_axis).normalized()

		var swing := Quaternion(cur_forward, dir_skel)
		var new_basis := Basis(swing) * gpose.basis

		var parent := skel.get_bone_parent(idx)
		var parent_basis := (
			skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
		)
		var local_basis := parent_basis.inverse() * new_basis
		skel.set_bone_pose_rotation(idx, local_basis.get_rotation_quaternion())

func _bone_world(skel: Skeleton3D, idx: int) -> Vector3:
	return skel.global_transform * skel.get_bone_global_pose(idx).origin

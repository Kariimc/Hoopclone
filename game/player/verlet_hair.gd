extends Node3D
class_name VerletHair
## Verlet hair / dread physics — a self-contained bone-chain solver, decoupled
## from the animation state machine so it keeps swinging regardless of what the
## player is doing. Attach under a Skeleton3D, point it at a chain of bone
## indices (root -> tip), and it integrates each segment with gravity, a
## stiffness constraint, and capsule (head/shoulder) collision.
##
## Per-archetype tunables let a tight fade barely move while long dreads swing
## freely. ~Verlet integration: x' = x + (x - x_prev) * damping + accel * dt^2,
## then distance-constraint each segment to preserve strand length.

## Skeleton this hair is parented to. If null, uses the parent if it is one.
@export var skeleton_path: NodePath
## Bone indices forming the strand, root first.
@export var bone_chain: Array[int] = []
## Rest length between consecutive bones (metres).
@export var segment_length: float = 0.06
## Gravity applied to each free point.
@export var gravity: Vector3 = Vector3(0, -9.8, 0)
## 0..1 velocity retention per step (lower = stiffer/more damped).
@export var damping: float = 0.92
## Constraint solver iterations (more = stiffer, costlier).
@export var iterations: int = 6
## Collision capsule radius around the head/neck so strands don't clip.
@export var collide_radius: float = 0.11

var _skel: Skeleton3D
var _points: PackedVector3Array = PackedVector3Array()
var _prev: PackedVector3Array = PackedVector3Array()
var _ready_ok: bool = false

func _ready() -> void:
	_skel = get_node_or_null(skeleton_path) as Skeleton3D
	if _skel == null:
		_skel = get_parent() as Skeleton3D
	if _skel == null or bone_chain.is_empty():
		push_warning("VerletHair: missing skeleton or empty bone_chain; disabled.")
		return
	for idx in bone_chain.size():
		var p := _bone_global_pos(bone_chain[idx])
		_points.append(p)
		_prev.append(p)
	_ready_ok = true

func _physics_process(delta: float) -> void:
	if not _ready_ok:
		return
	# Root point is pinned to the actual bone (driven by animation).
	var root_pos := _bone_global_pos(bone_chain[0])
	_points[0] = root_pos
	_prev[0] = root_pos

	# Verlet integrate the free points.
	for i in range(1, _points.size()):
		var cur := _points[i]
		var vel := (cur - _prev[i]) * damping
		_prev[i] = cur
		_points[i] = cur + vel + gravity * delta * delta

	_solve_constraints(root_pos)
	_write_back_to_bones()

func _solve_constraints(root_pos: Vector3) -> void:
	for _it in iterations:
		_points[0] = root_pos
		for i in range(1, _points.size()):
			var a := _points[i - 1]
			var b := _points[i]
			var dir := b - a
			var dist := dir.length()
			if dist > 0.0001:
				var diff := (dist - segment_length) / dist
				# Root side is heavier (pinned), so move the tip side more.
				_points[i] = b - dir * diff
			# Keep strands outside the head/neck capsule.
			var to_pt := _points[i] - root_pos
			if to_pt.length() < collide_radius:
				_points[i] = root_pos + to_pt.normalized() * collide_radius

func _write_back_to_bones() -> void:
	# Orient each bone to look at the next solved point. Sprint 4 refines this
	# into proper local-pose rotations against the bind pose; for now we expose
	# the solved world points for the rig to consume.
	for i in range(0, bone_chain.size() - 1):
		var from := _points[i]
		var to := _points[i + 1]
		var dir := (to - from)
		if dir.length() < 0.0001:
			continue
		# Placeholder hook: a bone-pose writer lands with the rigged mesh.
		pass

func solved_points() -> PackedVector3Array:
	return _points

func _bone_global_pos(bone_idx: int) -> Vector3:
	var local := _skel.get_bone_global_pose(bone_idx).origin
	return _skel.global_transform * local

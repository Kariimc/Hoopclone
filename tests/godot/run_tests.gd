extends SceneTree
## Headless engine self-test. Runs the REAL GDScript sim (ContestModel + ShotModel)
## inside Godot, so the engine-side behaviour — not just the Python mirror — is
## verified automatically in CI. The Python pytest locks the math and the
## constant-parity test locks the constants; this proves the GDScript actually
## *runs* and behaves, catching anything the language boundary could hide.
##
## Run:  godot --headless --path . --script res://tests/godot/run_tests.gd
## Exit code 0 = all passed, 1 = a failure (so CI turns red).

const ContestModel := preload("res://game/core/contest_model.gd")
const ShotModel := preload("res://game/core/shot_model.gd")
const GameStateScript := preload("res://game/core/game_state.gd")

var _fails := 0

func _initialize() -> void:
	print("== HoopClone Godot self-test ==")
	var origin := Vector2(0, 0)
	var basket := Vector2(8, 0)

	_check("contest: closer defender contests more",
		ContestModel.contest(origin, Vector2(1, 0), basket, 70)
		> ContestModel.contest(origin, Vector2(3, 0), basket, 70))

	_check("contest: zero beyond radius",
		ContestModel.contest(origin, Vector2(ContestModel.CONTEST_RADIUS, 0), basket, 99) == 0.0)

	_check("contest: in-lane beats beside",
		ContestModel.contest(origin, Vector2(1.5, 0), basket, 70)
		> ContestModel.contest(origin, Vector2(0, 1.5), basket, 70))

	_check("contest: better defender contests more",
		ContestModel.contest(origin, Vector2(1, 0), basket, 90)
		> ContestModel.contest(origin, Vector2(1, 0), basket, 30))

	_check("contest: strongest defender wins the group",
		ContestModel.contest_from_defenders(origin, basket, [
			{"pos": Vector2(1, 0), "rating": 70},
			{"pos": Vector2(3.2, 0), "rating": 70},
		]) == ContestModel.contest(origin, Vector2(1, 0), basket, 70))

	# End-to-end: an in-lane defender actually lowers the make probability.
	var shot_basket := Vector2(5, 0)
	var c := ContestModel.contest(origin, Vector2(1, 0), shot_basket, 75)
	var open_p := ShotModel.make_probability(5.0, 70, 0.0, 0.0)
	var contested_p := ShotModel.make_probability(5.0, 70, c, 0.0)
	_check("shot: contested make pct < open make pct", contested_p < open_p)
	_check("shot: probability within [P_MIN, P_MAX]",
		open_p >= ShotModel.P_MIN and open_p <= ShotModel.P_MAX)

	# --- GameState (Sprint 5 step 1f): the shared phase every consumer reads ---
	var gs := GameStateScript.new()
	_check("gamestate: starts in BOOT", gs.phase == GameStateScript.Phase.BOOT)
	_check("gamestate: phase_name matches phase", gs.phase_name() == "BOOT")

	var seen: Array = []
	gs.phase_changed.connect(func(from, to): seen.append([from, to]))

	gs.set_phase(GameStateScript.Phase.LIVE)
	_check("gamestate: set_phase moves the phase", gs.phase == GameStateScript.Phase.LIVE)
	_check("gamestate: set_phase announces the change",
		seen.size() == 1
		and seen[0][0] == GameStateScript.Phase.BOOT
		and seen[0][1] == GameStateScript.Phase.LIVE)

	gs.set_phase(GameStateScript.Phase.LIVE)
	_check("gamestate: re-setting the same phase announces nothing", seen.size() == 1)
	gs.free()
	await _scene_smoke()

	if _fails == 0:
		print("ALL GODOT TESTS PASSED")
	else:
		printerr("%d GODOT TEST(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)

## Boots the REAL main scene and asserts the _ready() wiring chain actually
## produced a playable court (audit §6 - the gap where bugs 3.3/3.4 lived).
##
## The height assertions are not cosmetic. With no collision shape on the court
## floor and no gravity on either body, a body that slid into another capsule
## rode up it and stayed airborne: the player was measured standing at Y 2.59 -
## rim height - while the defender had sunk to Y -0.31. Both looked fine in code
## and were only visible in a screenshot. These two checks are the guard.
func _scene_smoke() -> void:
	var packed: PackedScene = load("res://game/main.tscn")
	if packed == null:
		_check("scene: main.tscn loads", false)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for i in 90:
		await process_frame

	var player := scene.get_node_or_null("Player") as Player
	var defender := scene.get_node_or_null("Defender") as Defender
	_check("scene: player exists", player != null)
	_check("scene: defender exists", defender != null)
	_check("scene: ball exists", scene.get_node_or_null("Ball") != null)
	_check("scene: right hoop exists", scene.get_node_or_null("RightHoop") != null)
	_check("scene: court floor has a collision shape",
		scene.get_node_or_null("Floor/FloorCollision") != null)

	if player != null:
		_check("scene: player is equipped with a shot", player.shot != null)
		_check("scene: player stands on the floor (Y ~ 0), not in mid-air [measured Y=%.3f, on_floor=%s]"
			% [player.global_position.y, str(player.is_on_floor())],
			absf(player.global_position.y) < 0.05)
		if player.shot != null:
			_check("scene: at least one defender is registered on the shot",
				player.shot.defenders.size() >= 1)
	if defender != null:
		_check("scene: defender stands on the floor (Y ~ 0), not sunk through it",
			absf(defender.global_position.y) < 0.05)

	scene.queue_free()

func _check(label: String, cond: bool) -> void:
	if cond:
		print("  ok   ", label)
	else:
		printerr("  FAIL ", label)
		_fails += 1

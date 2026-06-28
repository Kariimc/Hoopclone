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

	if _fails == 0:
		print("ALL GODOT TESTS PASSED")
	else:
		printerr("%d GODOT TEST(S) FAILED" % _fails)
	quit(1 if _fails > 0 else 0)

func _check(label: String, cond: bool) -> void:
	if cond:
		print("  ok   ", label)
	else:
		printerr("  FAIL ", label)
		_fails += 1

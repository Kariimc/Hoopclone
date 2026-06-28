extends RefCounted
class_name ContestModel
## Runtime mirror of tools/sim/contest_model.py. Same constants, same formula, so
## a played contest and a simulated contest agree. If you change one, change both
## (the Python pytest is the spec lock).
##
## How hard a defender pressures a shot, as a 0-1 scalar fed to
## ShotModel.make_probability(...) as `contest`. Works in the horizontal (XZ)
## plane — pass Vector2(pos.x, pos.z) for shooter / defender / basket. The ball
## arcs up to the rim, but "is the defender between me and the basket" is a
## floor-plane question, so the basket's height is intentionally ignored.
##
##     contest = proximity(d) * lane(geometry) * defender_skill(rating)

const CONTEST_RADIUS := 3.5     # metres; past this a defender applies no pressure
const LANE_FLOOR := 0.40        # contest kept for a defender beside/behind the shooter
const DEF_SKILL_FLOOR := 0.60   # contest multiplier from a rating-0 defender in your face
const DEF_SKILL_RANGE := 0.40   # added at rating 99 -> 1.0 for an elite defender
const EPS := 1e-4               # degenerate-geometry guard (defender on top of shooter)

## 1 when the defender is on the shooter, fading linearly to 0 at CONTEST_RADIUS.
static func proximity_factor(distance_m: float) -> float:
	return clampf(1.0 - distance_m / CONTEST_RADIUS, 0.0, 1.0)

## 0-99 defensive rating -> contest multiplier in [FLOOR, FLOOR+RANGE].
static func defender_skill(rating: float) -> float:
	var r := clampf(rating, 0.0, 99.0)
	return DEF_SKILL_FLOOR + DEF_SKILL_RANGE * (r / 99.0)

## How much the defender sits in the shooter->basket lane. 1.0 directly between
## shooter and basket; fades to LANE_FLOOR as the defender moves beside/behind.
static func lane_factor(shooter: Vector2, defender: Vector2, basket: Vector2) -> float:
	var to_basket := basket - shooter
	var to_def := defender - shooter
	var db := to_basket.length()
	var dd := to_def.length()
	if dd < EPS or db < EPS:
		# Defender on top of the shooter (or shooter at the rim): full lane contest.
		return 1.0
	var cos := to_basket.dot(to_def) / (db * dd)
	cos = maxf(0.0, cos)
	return LANE_FLOOR + (1.0 - LANE_FLOOR) * cos

## Pressure in [0, 1] a single defender applies to a shot. defender_rating is
## 0-99 (PerimD for jumpers, InsideD for close — the caller picks, mirroring how
## the shot model picks Shooting vs ThreePT).
static func contest(shooter: Vector2, defender: Vector2, basket: Vector2,
		defender_rating: float) -> float:
	var dist := shooter.distance_to(defender)
	var c := proximity_factor(dist) \
		* lane_factor(shooter, defender, basket) \
		* defender_skill(defender_rating)
	return clampf(c, 0.0, 1.0)

## Strongest contest among several defenders. `defenders` is an Array of
## { "pos": Vector2, "rating": float }. Returns the single largest contest; an
## empty array -> 0.0 (a wide-open shot).
static func contest_from_defenders(shooter: Vector2, basket: Vector2,
		defenders: Array) -> float:
	var best := 0.0
	for d in defenders:
		best = maxf(best, contest(shooter, d["pos"], basket, d["rating"]))
	return best

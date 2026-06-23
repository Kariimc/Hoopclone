extends RefCounted
class_name ShotModel
## Runtime mirror of tools/sim/shot_model.py. Same constants, same curve, so a
## played shot and a simulated shot agree. If you change one, change both (the
## Python pytest is the spec lock).

const SKILL_FLOOR := 0.30
const SKILL_RANGE := 0.45
const DIST_FALLOFF := 0.06
const DIST_FACTOR_FLOOR := 0.12
const CONTEST_WEIGHT := 0.55
const TIMING_WEIGHT := 0.60
const P_MIN := 0.02
const P_MAX := 0.98
const GREEN_FLOOR := 0.06
const GREEN_RANGE := 0.12

static func skill(rating: float) -> float:
	var r := clampf(rating, 0.0, 99.0)
	return SKILL_FLOOR + SKILL_RANGE * (r / 99.0)

static func distance_factor(distance_m: float) -> float:
	var beyond := maxf(0.0, distance_m - 1.0)
	return clampf(1.0 - DIST_FALLOFF * beyond, DIST_FACTOR_FLOOR, 1.0)

static func make_probability(distance_m: float, rating: float,
		contest: float = 0.0, timing_error: float = 0.0) -> float:
	var p := skill(rating) \
		* distance_factor(distance_m) \
		* (1.0 - CONTEST_WEIGHT * clampf(contest, 0.0, 1.0)) \
		* (1.0 - TIMING_WEIGHT * clampf(timing_error, 0.0, 1.0))
	return clampf(p, P_MIN, P_MAX)

static func green_half_width(rating: float) -> float:
	var r := clampf(rating, 0.0, 99.0)
	return GREEN_FLOOR + GREEN_RANGE * (r / 99.0)

static func timing_error(release_offset: float, rating: float) -> float:
	var offset := absf(release_offset)
	var half := green_half_width(rating)
	if offset <= half:
		return 0.0
	return clampf((offset - half) / (1.0 - half), 0.0, 1.0)

extends Node3D
class_name Court
## Court geometry + hoop placement. Horizontal broadcast orientation: court runs
## along X, baskets at the left/right baselines facing inward. Sprint 1 shipped
## the logical dims + hoop anchors; Sprint 2 adds rim/backboard constants the
## ball resolves against. The photoreal arena mesh + PBR floor import later.

## Court length along X and width along Z (metres, NBA-ish scaled).
@export var court_length: float = 28.0
@export var court_width: float = 15.0
## Rim height and radius (metres).
@export var rim_height: float = 3.05
@export var rim_radius: float = 0.23
## Backboard: how far behind the rim, and its half-extents.
@export var backboard_offset: float = 0.30
@export var backboard_half_width: float = 0.90
@export var backboard_half_height: float = 0.525

func left_basket() -> Vector3:
	return Vector3(-court_length * 0.5 + 1.2, rim_height, 0.0)

func right_basket() -> Vector3:
	return Vector3(court_length * 0.5 - 1.2, rim_height, 0.0)

## Backboard plane centre behind a given rim (x sign points outward to baseline).
func backboard_center(rim_pos: Vector3) -> Vector3:
	var sign_x := signf(rim_pos.x)
	return rim_pos + Vector3(sign_x * backboard_offset, 0.20, 0.0)

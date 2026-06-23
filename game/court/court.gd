extends Node3D
class_name Court
## Court geometry + hoop placement. Horizontal broadcast orientation: court runs
## along X, baskets at the left/right baselines facing inward. Sprint 1 ships the
## logical dimensions + hoop anchor points; the photoreal arena mesh and PBR
## floor (locked Higgsfield assets) are imported in the asset-pipeline sprint.

## Court length along X and width along Z (metres, NBA-ish scaled).
@export var court_length: float = 28.0
@export var court_width: float = 15.0
## Rim height (metres).
@export var rim_height: float = 3.05

func left_basket() -> Vector3:
	return Vector3(-court_length * 0.5 + 1.2, rim_height, 0.0)

func right_basket() -> Vector3:
	return Vector3(court_length * 0.5 - 1.2, rim_height, 0.0)

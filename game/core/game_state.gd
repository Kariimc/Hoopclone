extends Node
class_name GameState
## Top-level phase tracker (mirrors the IDP lifecycle the project is built under,
## scoped to runtime game flow). Kept deliberately small in Sprint 1 — Season,
## Franchise, Commissioner, and CEO layers register their own sub-states later.

enum Phase { BOOT, MENU, TIPOFF, LIVE, TIMEOUT, QUARTER_BREAK, FINAL }

signal phase_changed(from: Phase, to: Phase)

var phase: Phase = Phase.BOOT

func set_phase(p: Phase) -> void:
	if p == phase:
		return
	var prev := phase
	phase = p
	phase_changed.emit(prev, p)

func phase_name() -> String:
	return Phase.keys()[phase]

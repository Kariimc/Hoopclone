extends Node
## QUIET WHEN AWAY - the game goes silent the moment it is not the window you are using.
##
## KARIIM'S WORDS, 2026-08-25:
##   "I only closed the debug window because the sound is weird right now and it was
##    annoying me I would have minimized it if the sound stopped when I did that"
##
## It sits under his standing rule from the same day: a game being built must not take
## the focus off whatever else he is doing. A window that keeps playing audio from behind
## everything else is taking his attention even when it is not taking his keyboard, and
## the only way out of that was to close the game, which is exactly what happened.
##
## WHAT IT DOES. Master volume off when the window loses focus, including when it is
## minimised, and back on when he returns to it. Nothing else changes: no bus is added,
## no volume is remembered or overwritten, and the game keeps running underneath so a
## reload is not needed when he comes back.
##
## WHY MUTE AND NOT PAUSE. Pausing a game that agents are working on hides whether their
## change actually works. He asked for the sound to stop, not for the game to stop.

## The master bus is index 0 in every Godot project and cannot be removed, so this needs
## no configuration and cannot be broken by a later audio change.
const MASTER_BUS := 0

## Public so a headless test can drive this without a window to focus. Nothing else calls
## it: the engine's own notifications do, below.
func set_away(away: bool) -> void:
	AudioServer.set_bus_mute(MASTER_BUS, away)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			set_away(true)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			set_away(false)

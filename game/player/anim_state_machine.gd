extends Node
class_name AnimStateMachine
## Player animation state machine — Sprint 4 owns the actual AnimationTree blend
## trees and mocap retargets; this is the control layer that decides WHICH state
## is active and exposes it for the visual layer to blend toward.
##
## The full offense/defense moveset is enumerated here so gameplay code, the
## simulator, and the animation graph all reference one shared vocabulary. Each
## state maps to an AnimationTree node/blendspace (noted in comments) once art
## lands. Locomotion states drive a 1D/2D blendspace by speed; action states are
## one-shots that return to the prior locomotion state on finish.

enum State {
	# --- Locomotion (blendspace by speed; shared offense/defense) ---
	IDLE,
	WALK,
	RUN,
	SPRINT,

	# --- Offense: ball handling ---
	DRIBBLE,          # 2D blendspace by move dir while ball-handling
	CROSSOVER,        # one-shot
	HESITATION,       # one-shot
	STEPBACK,         # one-shot, into jumper
	# --- Offense: drives & finishes ---
	DRIVE,
	LAYUP,
	DUNK,
	FLOATER,
	# --- Offense: jumpers & post ---
	JUMPSHOT,
	CATCH_AND_SHOOT,
	POST_UP,
	POST_MOVE,
	# --- Offense: support ---
	PASS,
	SCREEN,

	# --- Defense ---
	DEF_STANCE,
	DEF_SLIDE,        # 1D blendspace L/R
	CLOSEOUT,
	CONTEST,
	BLOCK,
	STEAL,
	BOXOUT,
	REBOUND,
}

## Action (one-shot) states return to locomotion when done; locomotion states
## persist. Used to know what to fall back to after an action completes.
const ONE_SHOT: Array = [
	State.CROSSOVER, State.HESITATION, State.STEPBACK, State.LAYUP, State.DUNK,
	State.FLOATER, State.JUMPSHOT, State.CATCH_AND_SHOOT, State.POST_MOVE,
	State.PASS, State.SCREEN, State.CLOSEOUT, State.CONTEST, State.BLOCK,
	State.STEAL, State.BOXOUT, State.REBOUND,
]

signal state_changed(from: State, to: State)

var state: State = State.IDLE
var _return_to: State = State.IDLE

## Request a transition. Returns true if the state actually changed.
func transition(to: State) -> bool:
	if to == state:
		return false
	var prev := state
	if not _is_one_shot(prev):
		_return_to = prev          # remember locomotion to resume after actions
	state = to
	state_changed.emit(prev, to)
	return true

## Call when a one-shot animation finishes (hook from AnimationTree signal).
func on_action_finished() -> void:
	if _is_one_shot(state):
		transition(_return_to)

## Map current speed (m/s) to the right locomotion state. Action states are
## untouched so a dunk-in-progress isn't interrupted by speed changes.
func update_locomotion(speed: float) -> void:
	if _is_one_shot(state):
		return
	if speed < 0.1:
		transition(State.IDLE)
	elif speed < 2.0:
		transition(State.WALK)
	elif speed < 5.5:
		transition(State.RUN)
	else:
		transition(State.SPRINT)

func state_name() -> String:
	return State.keys()[state]

func _is_one_shot(s: State) -> bool:
	return ONE_SHOT.has(s)

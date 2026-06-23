@tool
extends EditorScript
## Convenience: generate the player AnimationTree state machine so you don't
## hand-wire every node. Open this script in the editor and run it
## (File > Run, or Ctrl/Cmd+Shift+X). It writes:
##     res://game/player/player_tree.tres
## Then assign that resource as your AnimationTree's "Tree Root", point the tree
## at your AnimationPlayer, and map each state's `animation` to a real clip in
## your AnimationLibrary.
##
## Targets Godot 4.3/4.4. If an API name differs in your build, the manual
## checklist in docs/SPRINT4_INEDITOR.md builds the same graph by hand.

const OUT_PATH := "res://game/player/player_tree.tres"

# Action states -> the clip name each should play (rename to match your library).
const ACTION_CLIPS := {
	"DRIBBLE": "Dribble", "CROSSOVER": "Crossover", "HESITATION": "Hesitation",
	"STEPBACK": "Stepback", "DRIVE": "Drive", "LAYUP": "Layup", "DUNK": "Dunk",
	"FLOATER": "Floater", "JUMPSHOT": "JumpShot", "CATCH_AND_SHOOT": "CatchShoot",
	"POST_UP": "PostUp", "POST_MOVE": "PostMove", "PASS": "Pass", "SCREEN": "Screen",
	"DEF_STANCE": "DefStance", "DEF_SLIDE": "DefSlide", "CLOSEOUT": "Closeout",
	"CONTEST": "Contest", "BLOCK": "Block", "STEAL": "Steal", "BOXOUT": "Boxout",
	"REBOUND": "Rebound",
}

func _run() -> void:
	var sm := AnimationNodeStateMachine.new()

	# Locomotion blend space: Idle -> Walk -> Run -> Sprint by normalised speed.
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(_anim_node("Idle"), 0.0)
	loco.add_blend_point(_anim_node("Walk"), 0.33)
	loco.add_blend_point(_anim_node("Run"), 0.66)
	loco.add_blend_point(_anim_node("Sprint"), 1.0)
	sm.add_node("Locomotion", loco, Vector2(280, 120))
	sm.add_transition("Start", "Locomotion", AnimationNodeStateMachineTransition.new())

	# One state per action; auto-advance back to Locomotion when the clip ends.
	var y := 40
	for state_name in ACTION_CLIPS.keys():
		sm.add_node(state_name, _anim_node(ACTION_CLIPS[state_name]), Vector2(620, y))
		sm.add_transition("Locomotion", state_name, AnimationNodeStateMachineTransition.new())
		var back := AnimationNodeStateMachineTransition.new()
		back.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		sm.add_transition(state_name, "Locomotion", back)
		y += 60

	var err := ResourceSaver.save(sm, OUT_PATH)
	if err == OK:
		print("[build_animation_tree] wrote ", OUT_PATH,
			" — assign as AnimationTree Tree Root, then map clips.")
	else:
		push_error("[build_animation_tree] save failed: %s" % err)

func _anim_node(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = clip
	return n

extends CanvasLayer
class_name Scorebug3D
## The broadcast scorebug: team marks, score, quarter, game clock, shot clock.
##
## Ranked first by the review council as the thing that makes a basketball game
## read as a real broadcast rather than a tech demo - a player clocks a missing
## scoreboard in a second, long before they judge any model. It is built entirely
## in code so it needs no scene file and cannot drift out of sync with one.
##
## It owns the clocks. Anything that needs to know whether play is live asks it,
## rather than each system running its own timer and slowly disagreeing.

signal period_ended(period: int)
signal shot_clock_expired

const PERIOD_SECONDS := 12.0 * 60.0
const SHOT_SECONDS := 24.0
const PERIODS := 4

@export var home_abbr: String = "CRW"
@export var away_abbr: String = "STM"
@export var home_color: Color = Color("#7a0019")
@export var away_color: Color = Color("#1f6feb")

var home_score := 0
var away_score := 0
var period := 1
var clock := PERIOD_SECONDS
var shot_clock := SHOT_SECONDS
var running := true

var _home_label: Label
var _away_label: Label
var _clock_label: Label
var _period_label: Label
var _shot_label: Label
var _shot_panel: PanelContainer

func _ready() -> void:
	layer = 90
	# Fill the screen, then push the bug to the bottom centre. Anchoring the
	# container itself to the bottom left it collapsed to nothing and the whole
	# scorebug rendered off-screen.
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_END
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stack)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_bottom", 20)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(pad)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	row.add_child(_team_block(home_abbr, home_color, true))
	row.add_child(_centre_block())
	row.add_child(_team_block(away_abbr, away_color, false))
	row.add_child(_shot_block())
	_refresh()

## One side of the bug: a colour flash with the team's mark, then its score.
func _team_block(abbr: String, tint: Color, is_home: bool) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)

	var mark := PanelContainer.new()
	mark.add_theme_stylebox_override("panel", _panel(tint.darkened(0.15)))
	var mark_label := Label.new()
	mark_label.text = abbr
	mark_label.add_theme_font_size_override("font_size", 22)
	mark_label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	mark_label.custom_minimum_size = Vector2(74, 0)
	mark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.add_child(_pad(mark_label))
	box.add_child(mark)

	var score := PanelContainer.new()
	score.add_theme_stylebox_override("panel", _panel(Color(0.05, 0.06, 0.09, 0.94)))
	var score_label := Label.new()
	score_label.text = "0"
	score_label.add_theme_font_size_override("font_size", 30)
	score_label.add_theme_color_override("font_color", Color(1, 1, 1))
	score_label.custom_minimum_size = Vector2(64, 0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_child(_pad(score_label))
	box.add_child(score)

	if is_home:
		_home_label = score_label
	else:
		_away_label = score_label
	return box

## The middle: quarter above, game clock below.
func _centre_block() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel(Color(0.09, 0.10, 0.14, 0.96)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	_period_label = Label.new()
	_period_label.text = "1ST"
	_period_label.add_theme_font_size_override("font_size", 13)
	_period_label.add_theme_color_override("font_color", Color(0.65, 0.68, 0.76))
	_period_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_period_label)

	_clock_label = Label.new()
	_clock_label.text = "12:00"
	_clock_label.add_theme_font_size_override("font_size", 27)
	_clock_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_clock_label.custom_minimum_size = Vector2(108, 0)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_clock_label)

	panel.add_child(_pad(col))
	return panel

## The shot clock sits apart and turns red under five seconds, which is the one
## piece of a scorebug players actually watch while they play.
func _shot_block() -> Control:
	_shot_panel = PanelContainer.new()
	_shot_panel.add_theme_stylebox_override("panel", _panel(Color(0.05, 0.06, 0.09, 0.94)))
	_shot_label = Label.new()
	_shot_label.text = "24"
	_shot_label.add_theme_font_size_override("font_size", 28)
	_shot_label.add_theme_color_override("font_color", Color(0.98, 0.72, 0.18))
	_shot_label.custom_minimum_size = Vector2(58, 0)
	_shot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shot_panel.add_child(_pad(_shot_label))
	return _shot_panel

func _pad(inner: Control) -> Control:
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(side, 12)
	for side in ["margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, 6)
	m.add_child(inner)
	return m

func _panel(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(3)
	return s

func _process(delta: float) -> void:
	if not running:
		return
	clock = maxf(0.0, clock - delta)
	shot_clock = maxf(0.0, shot_clock - delta)

	if shot_clock <= 0.0:
		shot_clock_expired.emit()
		reset_shot_clock()
	if clock <= 0.0:
		period_ended.emit(period)
		if period < PERIODS:
			period += 1
			clock = PERIOD_SECONDS
			reset_shot_clock()
		else:
			running = false
	_refresh()

## Award a basket. Worth is 2 or 3; the caller knows which because the shot model
## already decided whether it was behind the line.
func score(is_home: bool, worth: int) -> void:
	if is_home:
		home_score += worth
	else:
		away_score += worth
	reset_shot_clock()
	_refresh()

func reset_shot_clock() -> void:
	shot_clock = SHOT_SECONDS

func _refresh() -> void:
	if _home_label == null:
		return
	_home_label.text = str(home_score)
	_away_label.text = str(away_score)
	_period_label.text = ["1ST", "2ND", "3RD", "4TH"][clampi(period - 1, 0, 3)]

	var mins := int(clock) / 60
	var secs := int(clock) % 60
	# Under a minute a real broadcast switches to tenths, which is the detail that
	# makes the last possession feel like the last possession.
	if clock < 60.0:
		_clock_label.text = "%d.%d" % [secs, int(fmod(clock, 1.0) * 10.0)]
	else:
		_clock_label.text = "%d:%02d" % [mins, secs]

	_shot_label.text = str(int(ceil(shot_clock)))
	var urgent := shot_clock <= 5.0
	_shot_label.add_theme_color_override("font_color",
		Color(1.0, 0.32, 0.28) if urgent else Color(0.98, 0.72, 0.18))
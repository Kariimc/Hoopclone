extends CanvasLayer
class_name BuildFeed
## A live build feed drawn over the game, so whoever is holding the controller can
## see what just changed without reading a terminal.
##
## The game window is restarted automatically whenever a project file changes, so
## every edit lands in front of the player within a few seconds. This panel reads
## a plain text file that the person (or agent) doing the work keeps updated, and
## shows it top-left along with how long ago this build started.
##
## Deliberately reads from res:// so it works when the game is run straight from
## the project folder, which is how it is played during development. The file is
## gitignored; if it is missing the panel simply says so and nothing breaks.

const STATUS_PATH := "res://.build_status.txt"
const POLL_SECONDS := 1.0
const MARGIN := 14.0
const WIDTH := 430.0

var _label: RichTextLabel
var _panel: PanelContainer
var _clock: Label
var _timer := 0.0
var _elapsed := 0.0
var _last_text := ""

func _ready() -> void:
	layer = 100
	_panel = PanelContainer.new()
	_panel.position = Vector2(MARGIN, MARGIN)
	_panel.custom_minimum_size = Vector2(WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.82)
	style.border_color = Color(0.85, 0.42, 0.12, 0.9)
	style.set_border_width(SIDE_LEFT, 3)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	_panel.add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "LIVE BUILD"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.95, 0.55, 0.2))
	col.add_child(title)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = false
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(WIDTH - 24.0, 0)
	_label.add_theme_font_size_override("normal_font_size", 13)
	_label.add_theme_color_override("default_color", Color(0.90, 0.91, 0.94))
	col.add_child(_label)

	_clock = Label.new()
	_clock.add_theme_font_size_override("font_size", 11)
	_clock.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	col.add_child(_clock)

	_panel.add_child(col)
	add_child(_panel)
	_refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	_timer += delta
	if _timer >= POLL_SECONDS:
		_timer = 0.0
		_refresh()
	_clock.text = "this build has been running %s" % _pretty(_elapsed)

func _refresh() -> void:
	var text := "No build notes yet.\nThis window restarts itself whenever the game changes."
	if FileAccess.file_exists(STATUS_PATH):
		var raw := FileAccess.get_file_as_string(STATUS_PATH).strip_edges()
		if raw != "":
			text = raw
	if text != _last_text:
		_last_text = text
		_label.text = text

func _pretty(seconds: float) -> String:
	if seconds < 60.0:
		return "%d seconds" % int(seconds)
	return "%d min %d sec" % [int(seconds / 60.0), int(fmod(seconds, 60.0))]
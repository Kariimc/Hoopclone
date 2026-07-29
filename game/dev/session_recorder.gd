extends Node
class_name SessionRecorder
## Lets whoever is building the game watch a session they are not sitting at.
##
## While someone plays, this writes a rolling plain-text log of what the game is
## actually doing - where the player is, how fast, whether the feet are down,
## how many defenders are contesting, the frame rate - and drops a periodic
## screenshot beside it. That turns "it felt wrong when I drove right" into
## something readable and fixable without anyone describing it.
##
## Everything lands in dev_session/ next to the project and is gitignored. It only
## runs when the game is launched from the project folder, never in an export.

const DIR := "res://dev_session"
const LOG := DIR + "/session.log"
const SHOT_EVERY := 3.0
const LOG_EVERY := 0.5
const KEEP_SHOTS := 40

var _log_timer := 0.0
var _shot_timer := 0.0
var _shot_index := 0
var _lines: Array[String] = []
var _player: Node3D
var _ball: Node3D

func _ready() -> void:
	if not OS.has_feature("editor") and not OS.is_debug_build():
		queue_free()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	# Read off our own parent, not get_tree().current_scene: the headless test
	# instances the scene by hand, so current_scene is null there and this
	# crashed the whole boot.
	var host := get_parent()
	if host != null:
		_player = host.get_node_or_null("Player")
		_ball = host.get_node_or_null("Ball")
	_write_header()

func _process(delta: float) -> void:
	_log_timer += delta
	_shot_timer += delta
	if _log_timer >= LOG_EVERY:
		_log_timer = 0.0
		_sample()
	if _shot_timer >= SHOT_EVERY:
		_shot_timer = 0.0
		_grab()

func _write_header() -> void:
	var f := FileAccess.open(LOG, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("# HoopClone session log - newest lines at the bottom")
	f.store_line("# time | player x,y,z | speed | feet down | defenders contesting | fps")
	f.close()

func _sample() -> void:
	if _player == null:
		return
	var speed := 0.0
	var grounded := "?"
	if _player is CharacterBody3D:
		var body := _player as CharacterBody3D
		speed = Vector2(body.velocity.x, body.velocity.z).length()
		grounded = "yes" if body.is_on_floor() else "NO"
	var contesting := 0
	if _player is Player and (_player as Player).shot != null:
		contesting = (_player as Player).shot.defenders.size()
	var p := _player.global_position
	var line := "%6.1fs | %6.2f,%5.2f,%6.2f | %4.2f m/s | feet:%s | D:%d | %d fps" % [
		Time.get_ticks_msec() / 1000.0, p.x, p.y, p.z, speed, grounded, contesting,
		Engine.get_frames_per_second()]

	# Anything genuinely wrong gets shouted, so it is greppable in one pass.
	if absf(p.y) > 0.25:
		line += "   <-- OFF THE FLOOR"
	if p.x != p.x or p.z != p.z:
		line += "   <-- POSITION IS NOT A NUMBER"

	_lines.append(line)
	if _lines.size() >= 8:
		_flush()

func _flush() -> void:
	if _lines.is_empty():
		return
	var f := FileAccess.open(LOG, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	for l in _lines:
		f.store_line(l)
	f.close()
	_lines.clear()

func _grab() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
	_shot_index = (_shot_index + 1) % KEEP_SHOTS
	img.save_png("%s/play_%02d.png" % [DIR, _shot_index])

func _exit_tree() -> void:
	_flush()
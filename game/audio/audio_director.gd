extends Node
class_name AudioDirector
## Everything the arena sounds like.
##
## The review council ranked audio second only to the scoreboard, and for a blunt
## reason: silence is not read as a small budget, it is read as a broken game.
## Real basketball is sonically dense, and its absence is instantly wrong even to
## someone who could not tell you why.
##
## Every sound here is synthesised by tools/audio/make_sfx.py - no licence, no
## account, and exact control over length and level. Sounds are indexed by name
## and a missing file is skipped rather than fatal, so the game never fails to
## start because a sound is absent.
##
## Voices are pooled: a dribble can fire every third of a second and would cut
## itself off with a single player.

const DIR := "res://assets/audio"
const POOL := 8

## name -> how many numbered variants exist, so a repeated sound never plays the
## identical file twice in a row.
const VARIANTS := {"dribble": 3, "squeak": 3}
const SINGLES := ["rim", "backboard", "swish", "whistle", "buzzer", "crowd_roar"]

@export var master_db: float = 0.0
@export var crowd_db: float = -14.0
@export var dribble_db: float = -7.0
@export var squeak_db: float = -15.0

var _clips: Dictionary = {}          ## key -> Array[AudioStream]
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _crowd: AudioStreamPlayer
var _last_variant: Dictionary = {}

func _ready() -> void:
	for base in VARIANTS:
		var list: Array[AudioStream] = []
		for i in range(1, int(VARIANTS[base]) + 1):
			var s := _load("%s_%d" % [base, i])
			if s != null:
				list.append(s)
		if not list.is_empty():
			_clips[base] = list
	for name in SINGLES:
		var s := _load(name)
		if s != null:
			_clips[name] = [s] as Array[AudioStream]

	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)

	var bed := _load("crowd_bed")
	if bed != null:
		if bed is AudioStreamWAV:
			# Loop the bed end-to-end; make_sfx.py already cross-faded the seam.
			(bed as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(bed as AudioStreamWAV).loop_end = (bed as AudioStreamWAV).data.size() / 4
		_crowd = AudioStreamPlayer.new()
		_crowd.stream = bed
		_crowd.volume_db = crowd_db
		_crowd.bus = "Master"
		add_child(_crowd)
		_crowd.play()
	else:
		push_warning("AudioDirector: no crowd bed at %s" % DIR)

	print("Audio ready: %d sound groups%s" % [_clips.size(),
		"" if _crowd != null else " (no crowd bed)"])

func _load(name: String) -> AudioStream:
	var path := "%s/%s.wav" % [DIR, name]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

## Play a sound by name. `level` scales volume 0-1, `pitch` varies it so repeats
## do not sound mechanical.
func play(name: String, level: float = 1.0, db: float = 0.0) -> void:
	if not _clips.has(name):
		return
	var list: Array = _clips[name]
	var idx := 0
	if list.size() > 1:
		# Never the same variant twice running.
		idx = randi() % list.size()
		if idx == int(_last_variant.get(name, -1)):
			idx = (idx + 1) % list.size()
	_last_variant[name] = idx

	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = list[idx]
	p.pitch_scale = randf_range(0.94, 1.07)
	p.volume_db = master_db + db + linear_to_db(clampf(level, 0.05, 1.0))
	p.play()

func on_dribble(level: float) -> void:
	play("dribble", level, dribble_db)

func on_squeak(level: float) -> void:
	play("squeak", level, squeak_db)

## A made basket: net first, then the crowd surging under it.
func on_made() -> void:
	play("swish", 1.0, -4.0)
	play("crowd_roar", 1.0, -6.0)

## A miss: iron, sometimes glass first.
func on_missed() -> void:
	if randf() < 0.35:
		play("backboard", 1.0, -6.0)
	play("rim", 1.0, -5.0)

func on_buzzer() -> void:
	play("buzzer", 1.0, -3.0)

func on_whistle() -> void:
	play("whistle", 1.0, -6.0)

## Lift the crowd bed with the same 0-1 dial that drives the visible crowd, so
## what you hear and what you see agree.
func set_crowd_intensity(v: float) -> void:
	if _crowd == null:
		return
	_crowd.volume_db = crowd_db + lerpf(0.0, 9.0, clampf(v, 0.0, 1.0))
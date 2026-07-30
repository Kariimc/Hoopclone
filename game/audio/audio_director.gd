extends Node
class_name AudioDirector
## Everything the arena sounds like.
##
## The review council ranked audio second only to the scoreboard, and for a blunt
## reason: silence is not read as a small budget, it is read as a broken game.
## Real basketball is sonically dense, and its absence is instantly wrong even to
## someone who could not tell you why.
##
## Every sound is synthesised by tools/audio/make_sfx.py - no licence, no
## account, exact control over length and level - and tools/audio/verify_sfx.py
## is the gate that says whether the set is any good. A missing file is skipped
## rather than fatal, so the game never fails to start because a sound is absent.
##
## THREE THINGS MAKE THIS SOUND LIKE A BUILDING RATHER THAN A SOUNDBOARD.
##
## POSITION. A bounce comes from where the ball is, a squeak from where the feet
## are, iron from the rim that was hit. Anything that happens somewhere is played
## by an AudioStreamPlayer3D at that spot, so it pans and fades as the camera
## moves. Flat playback was the single biggest thing making the mix read as a
## menu rather than a court.
##
## BUSES. Crowd and effects run on their own buses so one can duck under the
## other, and the master carries a limiter - a roar and a buzzer landing together
## used to clip, and clipping is the exact sound of cheapness.
##
## VOICES. Pooled, because a dribble can fire three times a second and would cut
## itself off with a single player.

const DIR := "res://assets/audio"
const POOL_2D := 6
const POOL_3D := 12

## name -> how many numbered variants exist, so a repeated sound never plays the
## identical file twice in a row.
const VARIANTS := {"dribble": 3, "squeak": 3}
const SINGLES := ["rim", "backboard", "swish", "whistle", "buzzer", "crowd_roar"]

## How far a sound carries. A bounce is loud at the ball and gone in the stands;
## a horn is heard everywhere.
const RANGE := {
	"dribble": 26.0, "squeak": 18.0, "rim": 40.0, "backboard": 40.0,
	"swish": 30.0, "whistle": 60.0, "buzzer": 90.0, "crowd_roar": 120.0,
}

@export var master_db: float = 0.0
@export var crowd_db: float = -14.0
@export var dribble_db: float = -7.0
@export var squeak_db: float = -15.0

## Where things happen. Set by the scene; any left null simply plays flat.
var ball: Node3D
var player: Node3D
var rim_node: Node3D

var _clips: Dictionary = {}          ## key -> Array[AudioStream]
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next3d := 0
var _crowd: AudioStreamPlayer
var _last_variant: Dictionary = {}
var _sfx_bus := "Master"
var _crowd_bus := "Master"

func _ready() -> void:
	_build_buses()
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

	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = _sfx_bus
		add_child(p)
		_pool.append(p)
	for i in POOL_3D:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = _sfx_bus
		# Inverse-distance rolloff is what real air does. The default unit size
		# is tuned for a room, not a 28-metre court, so it is widened per sound.
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.panning_strength = 1.4
		add_child(p3)
		_pool3d.append(p3)

	var bed := _load("crowd_bed")
	if bed != null:
		if bed is AudioStreamWAV:
			# Loop the bed end-to-end; make_sfx.py already cross-faded the seam.
			(bed as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(bed as AudioStreamWAV).loop_end = (bed as AudioStreamWAV).data.size() / 4
		_crowd = AudioStreamPlayer.new()
		_crowd.stream = bed
		_crowd.volume_db = crowd_db
		_crowd.bus = _crowd_bus
		add_child(_crowd)
		_crowd.play()
	else:
		push_warning("AudioDirector: no crowd bed at %s" % DIR)

	print("Audio ready: %d sound groups%s" % [_clips.size(),
		"" if _crowd != null else " (no crowd bed)"])

## Two buses under a limited master.
##
## Built in code rather than shipped as a bus layout resource so there is one
## place to read the mix from, and so a project opened without the layout file
## still sounds right. Idempotent: a bus that already exists is reused.
func _build_buses() -> void:
	_sfx_bus = _ensure_bus("SFX", -1.0)
	_crowd_bus = _ensure_bus("Crowd", -3.0)
	var master := AudioServer.get_bus_index("Master")
	if master >= 0 and not _has_effect(master, "AudioEffectLimiter"):
		var lim := AudioEffectLimiter.new()
		# Catch peaks only. A hard ceiling here is a safety net, not a sound.
		lim.ceiling_db = -0.8
		lim.threshold_db = -1.5
		lim.soft_clip_db = 2.0
		AudioServer.add_bus_effect(master, lim)

func _ensure_bus(name: String, volume_db: float) -> String:
	var idx := AudioServer.get_bus_index(name)
	if idx < 0:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, volume_db)
	return name

func _has_effect(bus: int, cls: String) -> bool:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).get_class() == cls:
			return true
	return false

func _load(name: String) -> AudioStream:
	var path := "%s/%s.wav" % [DIR, name]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream

func _pick(name: String) -> AudioStream:
	var list: Array = _clips[name]
	var idx := 0
	if list.size() > 1:
		# Never the same variant twice running.
		idx = randi() % list.size()
		if idx == int(_last_variant.get(name, -1)):
			idx = (idx + 1) % list.size()
	_last_variant[name] = idx
	return list[idx]

## Play a sound flat, with no place in the world. Use `play_at` for anything that
## actually happens somewhere.
func play(name: String, level: float = 1.0, db: float = 0.0) -> void:
	if not _clips.has(name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _pick(name)
	p.pitch_scale = randf_range(0.94, 1.07)
	p.volume_db = master_db + db + linear_to_db(clampf(level, 0.05, 1.0))
	p.play()

## Play a sound at a point on the court. Falls back to flat playback if the
## caller has no position to give, so no call site has to check.
func play_at(name: String, where: Node3D, level: float = 1.0, db: float = 0.0) -> void:
	if not _clips.has(name):
		return
	if where == null or not where.is_inside_tree():
		play(name, level, db)
		return
	var p := _pool3d[_next3d]
	_next3d = (_next3d + 1) % _pool3d.size()
	p.global_position = where.global_position
	p.stream = _pick(name)
	p.pitch_scale = randf_range(0.94, 1.07)
	p.max_distance = float(RANGE.get(name, 40.0))
	p.unit_size = p.max_distance * 0.35
	p.volume_db = master_db + db + linear_to_db(clampf(level, 0.05, 1.0))
	p.play()

func on_dribble(level: float) -> void:
	play_at("dribble", ball, level, dribble_db)

func on_squeak(level: float) -> void:
	play_at("squeak", player, level, squeak_db)

## A made basket: net first, then the crowd surging under it. The net comes from
## the rim; the crowd comes from everywhere, so it stays flat.
func on_made() -> void:
	play_at("swish", rim_node, 1.0, -4.0)
	play("crowd_roar", 1.0, -6.0)

## A miss: iron, sometimes glass first.
func on_missed() -> void:
	if randf() < 0.35:
		play_at("backboard", rim_node, 1.0, -6.0)
	play_at("rim", rim_node, 1.0, -5.0)

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

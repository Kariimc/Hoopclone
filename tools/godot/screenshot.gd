extends SceneTree
## Headless screenshot / smoke driver for the running GAME (not the test suite).
##
## Boots the real main scene (res://game/main.tscn) — broadcast camera, roster
## load, player/defender/ball, court + animated crowd — lets it render for a few
## frames so everything settles, grabs the framebuffer, writes a PNG, and exits.
## This is the programmatic handle an agent uses to SEE the game on a headless
## box. It lives here (not in .claude/skills/) because Godot's resource system
## ignores dotfile directories, so a driver under .claude/ can't be loaded.
##
## Run (needs a display + a working rasterizer — see the run-hoopclone skill):
##   xvfb-run -a godot --path . \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --script res://tools/godot/screenshot.gd
##
## Tunables via env:
##   HOOP_SHOT_OUT  absolute output path (default: <cwd>/hoopclone_shot.png)
##   HOOP_WARMUP    frames to render before capture (default: 120)
##   HOOP_HOLD      comma-separated input actions held the whole warmup, so the
##                  driver actually plays the game instead of snapshotting the
##                  boot frame. Valid: move_left, move_right, move_up,
##                  move_down, shoot. e.g. HOOP_HOLD=move_right,shoot
##
## Exit 0 = a PNG was written; exit 1 = boot/render/capture failed.

func _initialize() -> void:
	var warmup := 120
	if OS.has_environment("HOOP_WARMUP"):
		warmup = int(OS.get_environment("HOOP_WARMUP"))
	var out := OS.get_environment("HOOP_SHOT_OUT")
	if out.is_empty():
		out = ProjectSettings.globalize_path("res://hoopclone_shot.png")
	var hold := PackedStringArray()
	if OS.has_environment("HOOP_HOLD"):
		for a in OS.get_environment("HOOP_HOLD").split(",", false):
			hold.append(a.strip_edges())

	var packed := load("res://game/main.tscn") as PackedScene
	if packed == null:
		printerr("DRIVER: failed to load res://game/main.tscn")
		quit(1)
		return
	root.add_child(packed.instantiate())
	print("DRIVER: main scene instanced; warming up %d frames (hold: %s)"
		% [warmup, ", ".join(hold) if hold.size() > 0 else "none"])
	_capture(warmup, out, hold)

func _capture(warmup: int, out: String, hold: PackedStringArray) -> void:
	# Press-and-hold the requested actions so the player moves / shoots while the
	# scene renders. Skip any action the project's input map doesn't define.
	for a in hold:
		if InputMap.has_action(a):
			Input.action_press(a)
		else:
			printerr("DRIVER: ignoring unknown input action '%s'" % a)
	for i in range(warmup):
		await process_frame
	# Make sure the GPU has actually drawn the frame we're about to read back.
	await RenderingServer.frame_post_draw
	for a in hold:
		if InputMap.has_action(a):
			Input.action_release(a)

	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		printerr("DRIVER: framebuffer readback was empty (no rasterizer?)")
		quit(1)
		return
	var err := img.save_png(out)
	if err != OK:
		printerr("DRIVER: save_png failed (err %d) -> %s" % [err, out])
		quit(1)
		return
	print("DRIVER: SHOT SAVED -> %s  (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit(0)

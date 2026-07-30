extends RefCounted
class_name ArenaLighting
## The lighting, materials and grading that decide whether this reads as a
## televised arena or as a flat diorama.
##
## Judged against a full-resolution frame, the models were never the problem. The
## problems were: nothing cast a shadow, so every player floated; the court was
## matte when a real one is close to a mirror; the stands were brighter than the
## floor, which is backwards for a broadcast; and there was no tone mapping,
## bloom or occlusion at all, so the whole image sat flat and washed.
##
## Everything here is engine-side. No new art, no new assets - the same models
## look completely different once they are lit and graded like a real broadcast.

## Arena rigs are bright pools over the floor with the stands falling away into
## the dark. That contrast IS the look; an evenly lit arena reads as a gym.
const KEY_ENERGY := 1.35
const FILL_ENERGY := 0.42
const CATWALK_ENERGY := 11.0
const CATWALK_HEIGHT := 15.5
## Eight rigs in two rows. More lights at LOWER energy each is what removes the
## hard cone edges a few bright spots leave on the floor.
const CATWALK_POSITIONS := [
	Vector3(-11.0, CATWALK_HEIGHT, -4.5), Vector3(-3.7, CATWALK_HEIGHT, -4.5),
	Vector3(3.7, CATWALK_HEIGHT, -4.5), Vector3(11.0, CATWALK_HEIGHT, -4.5),
	Vector3(-11.0, CATWALK_HEIGHT, 4.5), Vector3(-3.7, CATWALK_HEIGHT, 4.5),
	Vector3(3.7, CATWALK_HEIGHT, 4.5), Vector3(11.0, CATWALK_HEIGHT, 4.5),
]

func build(root: Node3D) -> void:
	_upgrade_environment(root)
	_upgrade_key_light(root)
	_add_fill(root)
	_add_catwalk(root)
	_polish_floor(root)
	_add_court_probe(root)
	_dim_the_stands(root)
	print("Arena lighting: shadowed key + %d catwalk rigs, polished floor, graded" % CATWALK_POSITIONS.size())

## Tone mapping, bloom and occlusion. Without these the render is a flat
## screenshot of geometry; with them it is a photograph of a room.
func _upgrade_environment(root: Node3D) -> void:
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		root.add_child(we)
	var env := we.environment
	if env == null:
		env = Environment.new()
		we.environment = env

	# A dark room with a faint cool bounce, not a grey void.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.014, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.37, 0.46)
	env.ambient_light_energy = 0.50

	# Filmic tone mapping is the single biggest step away from a flat look: it
	# rolls highlights off instead of clipping them white.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.82
	env.tonemap_white = 8.0

	# Bloom on the bright pools and the scoreboard, kept restrained.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.12
	env.glow_strength = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.0

	# Contact darkening. This is what stops bodies, chairs and seats looking like
	# stickers pasted onto the floor.
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssil_enabled = true
	env.ssil_intensity = 0.7

	# Screen-space reflections, which is how the polished floor picks up players.
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 3.0

	# A gentle grade: slightly cool shadows, warm highlights, a touch more
	# contrast and saturation than raw output.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.16
	env.adjustment_saturation = 1.04

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.06, 0.07, 0.10)
	env.fog_density = 0.006
	env.fog_depth_begin = 26.0
	env.fog_depth_end = 70.0

## The existing key light gets real shadows - the change that stops players
## floating above the floor.
func _upgrade_key_light(root: Node3D) -> void:
	var key := root.get_node_or_null("KeyLight") as DirectionalLight3D
	if key == null:
		return
	key.light_energy = KEY_ENERGY
	key.light_color = Color(1.0, 0.96, 0.90)
	key.shadow_enabled = true
	key.shadow_bias = 0.03
	key.shadow_normal_bias = 1.4
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key.directional_shadow_max_distance = 45.0
	key.directional_shadow_blend_splits = true

## A cool counter-light so the shadow side of a player is not solid black.
func _add_fill(root: Node3D) -> void:
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = FILL_ENERGY
	fill.light_color = Color(0.72, 0.80, 1.0)
	fill.shadow_enabled = false
	root.add_child(fill)
	fill.look_at_from_position(Vector3(-10.0, 9.0, 12.0), Vector3(2.0, 1.0, 0.0), Vector3.UP)

## Overhead rigs. These are what actually make a court look like a court: bright
## overlapping pools with hard-ish shadows straight down.
func _add_catwalk(root: Node3D) -> void:
	for i in CATWALK_POSITIONS.size():
		var lamp := SpotLight3D.new()
		lamp.name = "Catwalk_%d" % i
		lamp.light_energy = CATWALK_ENERGY
		lamp.light_color = Color(1.0, 0.97, 0.92)
		lamp.spot_range = 40.0
		lamp.spot_angle = 62.0
		lamp.spot_angle_attenuation = 2.2
		lamp.spot_attenuation = 1.4
		lamp.shadow_enabled = true
		lamp.shadow_bias = 0.04
		lamp.shadow_normal_bias = 1.6
		root.add_child(lamp)
		lamp.position = CATWALK_POSITIONS[i]
		lamp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

## A match-day floor is sealed and buffed to nearly a mirror. Matte hardwood is
## the difference between "a wooden plane" and "a basketball court".
func _polish_floor(root: Node3D) -> void:
	var mesh_node := root.get_node_or_null("Floor/FloorMesh") as MeshInstance3D
	if mesh_node == null:
		return
	var prim := mesh_node.mesh as PrimitiveMesh
	var mat := (prim.material if prim != null else null) as StandardMaterial3D
	if mat == null:
		return
	# The source hardwood photo is heavily orange-red. Pulling it toward neutral
	# maple is the difference between a genuine floor and a lurid one - it reads
	# as the wrong material long before anyone questions the geometry.
	mat.albedo_color = Color(0.80, 0.755, 0.70)
	mat.roughness = 0.13
	mat.metallic = 0.0
	mat.metallic_specular = 1.0
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.85
	mat.clearcoat_roughness = 0.04
	# Keep the wood reading as wood rather than a lit plastic sheet.
	mat.rim_enabled = true
	mat.rim = 0.15

## Broadcast arenas light the floor and let the stands fall away. Left as bright
## as the court, the crowd competes with the game for attention - which is
## exactly how the frame looked before this.
func _dim_the_stands(root: Node3D) -> void:
	var bowl := root.get_node_or_null("Crowd_Bowl") as MeshInstance3D
	if bowl != null and bowl.material_override is ShaderMaterial:
		(bowl.material_override as ShaderMaterial).set_shader_parameter("dim", 0.40)
	var fans := root.get_node_or_null("Crowd_Fans") as MultiMeshInstance3D
	if fans != null and fans.material_override is ShaderMaterial:
		(fans.material_override as ShaderMaterial).set_shader_parameter("dim", 0.44)

## A reflection probe covering the whole court.
##
## Screen-space reflections alone only mirror what is already on screen, so the
## floor stays dull wherever there is nothing above it. A probe captures the
## arena around it, which is what lets the boards, the rigs and the stands appear
## in the wood - and that sheen is most of what separates a match floor from a
## brown plane.
func _add_court_probe(root: Node3D) -> void:
	var probe := ReflectionProbe.new()
	probe.name = "Court_Probe"
	probe.size = Vector3(60.0, 24.0, 40.0)
	probe.origin_offset = Vector3(0.0, 2.0, 0.0)
	probe.intensity = 1.0
	probe.max_distance = 60.0
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	# Baked once: the arena around the court does not move, and re-capturing every
	# frame would cost far more than the reflection is worth.
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	root.add_child(probe)
	probe.position = Vector3(0.0, 8.0, 0.0)

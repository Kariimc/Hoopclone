# build_fan.py - seated spectator for HoopClone's instanced crowd.
# run: blender --background --factory-startup --python build_fan.py -- --out fan.png
#
# Budget: this mesh is drawn ~700 times through one MultiMesh, so it is built to
# a hard low-poly budget and carries NO textures - the game shader colours each
# instance. What it must carry is UV2 tagging, which the game's vertex shader
# reads to know which part of the body to move:
#   UV2.x  0 = seated legs (never move)  1 = torso  2 = arms  3 = head
#   UV2.y  how far up that part a vertex sits, so bends pivot correctly
import bpy, bmesh, math, sys, os
from mathutils import Matrix

def cli(name, default):
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return a[a.index(name) + 1] if name in a else default

OUT = os.path.abspath(cli("--out", "fan.png"))
GLB = os.path.splitext(OUT)[0] + ".glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'

LEGS, TORSO, ARMS, HEAD = 0.0, 1.0, 2.0, 3.0

def tag(bm, faces, part, up):
    uv = bm.loops.layers.uv.verify()
    uv2 = bm.loops.layers.uv.get("UV2") or bm.loops.layers.uv.new("UV2")
    # Blender moved this type twice: older builds hand back a BMLoopUV (write
    # through .uv), newer ones hand back a plain Vector (write through a slice).
    def put(item, value):
        if hasattr(item, "uv"):
            item.uv = value
        else:
            item[:] = value
    for f in faces:
        for l in f.loops:
            put(l[uv], (0.0, 0.0))
            put(l[uv2], (part, up))

def add(bm, op, part, up, **kw):
    before = set(bm.faces)
    op(bm, **kw)
    new = [f for f in bm.faces if f not in before]
    tag(bm, new, part, up)
    return new

def box(bm, part, up, center, size, rot=None):
    m = Matrix.Translation(center)
    if rot is not None:
        m = m @ rot
    m = m @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    add(bm, bmesh.ops.create_cube, part, up, size=1.0, matrix=m)

def cone(bm, part, up, center, r1, r2, depth, segs=10):
    add(bm, bmesh.ops.create_cone, part, up,
        cap_ends=True, cap_tris=False, segments=segs,
        radius1=r1, radius2=r2, depth=depth,
        matrix=Matrix.Translation(center))

def ball(bm, part, up, center, r, segs=10, rings=6):
    add(bm, bmesh.ops.create_uvsphere, part, up,
        u_segments=segs, v_segments=rings, radius=r,
        matrix=Matrix.Translation(center))

# ---------------- seated spectator ----------------
# Seated: ~1.13 m from the seat deck to the crown, knees forward, feet down.
# Two corrections from earlier passes:
#   1. Volumes OVERLAP their neighbours - butted edge to edge they read as a pile
#      of floating blocks rather than a body.
#   2. The figure faces -Y, which is forward in Blender and what the camera and
#      the game both expect. Built facing +Y it was rendered from behind.
bm = bmesh.new()

# hips: the anchor everything else grows out of
box(bm, LEGS, 0.0, (0.00, -0.03, 0.46), (0.38, 0.30, 0.24))
# thighs run forward out of the hips, shins drop, feet flat on the deck
box(bm, LEGS, 0.0, (-0.105, -0.22, 0.44), (0.18, 0.42, 0.19))
box(bm, LEGS, 0.0, ( 0.105, -0.22, 0.44), (0.18, 0.42, 0.19))
box(bm, LEGS, 0.0, (-0.105, -0.38, 0.23), (0.16, 0.17, 0.46))
box(bm, LEGS, 0.0, ( 0.105, -0.38, 0.23), (0.16, 0.17, 0.46))
box(bm, LEGS, 0.0, (-0.105, -0.33, 0.045), (0.15, 0.29, 0.09))
box(bm, LEGS, 0.0, ( 0.105, -0.33, 0.045), (0.15, 0.29, 0.09))

# torso: one continuous taper from waist to chest, sunk into the hips below and
# the shoulders above
cone(bm, TORSO, 0.35, (0.0, -0.01, 0.64), 0.175, 0.195, 0.42, segs=14)
box(bm, TORSO, 0.90, (0.0, -0.01, 0.795), (0.40, 0.22, 0.13))

# arms: upper arm hangs from inside the shoulder box, forearm folds into the lap
box(bm, ARMS, 0.80, (-0.235, -0.01, 0.685), (0.115, 0.15, 0.27))
box(bm, ARMS, 0.80, ( 0.235, -0.01, 0.685), (0.115, 0.15, 0.27))
box(bm, ARMS, 0.95, (-0.225, -0.17, 0.575), (0.105, 0.32, 0.115))
box(bm, ARMS, 0.95, ( 0.225, -0.17, 0.575), (0.105, 0.32, 0.115))

# neck clear of the shoulders, head resting on it
cone(bm, HEAD, 1.0, (0.0, -0.01, 0.885), 0.060, 0.066, 0.11, segs=10)
ball(bm, HEAD, 1.0, (0.0, -0.005, 1.020), 0.102, segs=14, rings=9)

mesh = bpy.data.meshes.new("Fan")
bm.to_mesh(mesh)
bm.free()

obj = bpy.data.objects.new("Fan", mesh)
scene.collection.objects.link(obj)
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
bpy.ops.object.shade_auto_smooth(angle=math.radians(38))

# ---------------- audit ----------------
bm = bmesh.new(); bm.from_mesh(mesh)
tris = sum(1 for f in bm.faces if len(f.verts) == 3)
quads = sum(1 for f in bm.faces if len(f.verts) == 4)
ngons = sum(1 for f in bm.faces if len(f.verts) > 4)
nonman = sum(1 for e in bm.edges if not e.is_manifold)
loose = sum(1 for v in bm.verts if not v.link_edges)
bm.free()
tri_total = sum((len(p.vertices) - 2) for p in mesh.polygons)
d = obj.dimensions
print(f"AUDIT: Fan faces_tris={tris} quads={quads} ngons={ngons} "
      f"triangulated={tri_total} non_manifold_edges={nonman} loose_verts={loose} "
      f"dims={d.x:.3f}x{d.y:.3f}x{d.z:.3f}m")
uv_names = [l.name for l in mesh.uv_layers]
print(f"AUDIT: uv_layers={uv_names}")

# ---------------- material (proof render only; the game recolours per fan) ----------------
mat = bpy.data.materials.new("FanProof")
if mat.node_tree is None:
    mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.42, 0.45, 0.52, 1.0)
bsdf.inputs["Roughness"].default_value = 0.82
mesh.materials.append(mat)

bpy.ops.mesh.primitive_plane_add(size=6)
ground = bpy.context.active_object
gm = bpy.data.materials.new("Ground")
if gm.node_tree is None:
    gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.14, 0.14, 0.16, 1.0)
ground.data.materials.append(gm)

# ---------------- lighting + camera ----------------
def light(name, loc, energy, color, size=2.0):
    ld = bpy.data.lights.new(name, 'AREA'); ld.energy = energy; ld.color = color; ld.size = size
    ob = bpy.data.objects.new(name, ld); ob.location = loc
    scene.collection.objects.link(ob); return ob

target = bpy.data.objects.new("CamTarget", None)
target.location = (0, 0, 0.62)
scene.collection.objects.link(target)

def aim(ob):
    c = ob.constraints.new('TRACK_TO'); c.target = target
    c.track_axis, c.up_axis = 'TRACK_NEGATIVE_Z', 'UP_Y'

for L in (light("Key", (-1.8, -1.8, 2.0), 220, (1.0, 0.95, 0.85), 2.2),
          light("Fill", (1.8, -1.4, 1.1), 60, (0.75, 0.85, 1.0), 3.0),
          light("Rim", (0.4, 2.2, 1.8), 180, (1.0, 1.0, 1.0), 1.2)):
    aim(L)

world = bpy.data.worlds.new("World"); scene.world = world
if world.node_tree is None:
    world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.03, 0.03, 0.035, 1.0)

cam_data = bpy.data.cameras.new("Camera"); cam_data.lens = 50
cam = bpy.data.objects.new("Camera", cam_data)
scene.collection.objects.link(cam); scene.camera = cam
aim(cam)

for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES'):
    try:
        scene.render.engine = eng; break
    except TypeError:
        continue
if scene.render.engine == 'CYCLES':
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = 900
scene.render.image_settings.file_format = 'PNG'

base, ext = os.path.splitext(OUT)
for tagname, loc in {"front34": (-1.6, -1.9, 1.35), "side": (2.2, 0.1, 1.0), "top": (0.01, 0.01, 3.0)}.items():
    cam.location = loc
    scene.render.filepath = f"{base}_{tagname}{ext}"
    try:
        bpy.ops.render.render(write_still=True)
    except Exception as e:
        print(f"AUDIT: render failed on {scene.render.engine} ({e}); falling back to CYCLES")
        scene.render.engine = 'CYCLES'; scene.cycles.samples = 48
        bpy.ops.render.render(write_still=True)
    print(f"AUDIT: rendered {scene.render.filepath}")

# ---------------- export ----------------
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', use_selection=True,
                          export_apply=True, export_image_format='AUTO')
print(f"AUDIT: exported {GLB} ({os.path.getsize(GLB)} bytes)")
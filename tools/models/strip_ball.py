"""Cut the welded basketball out of the player mesh.

The shipped model has a ball modelled AND textured into the right hand as part of
the same surface, so it can never bounce - it just follows the hand. The mesh is
one surface of ~28k verts in ~2.5k disconnected scraps, so selecting the ball as a
"loose part" does not work.

Two signals together identify it, and either alone would be wrong:
  colour  - sample the albedo texture at each face's UV; basketball leather is a
            saturated orange, the kit is blue, but SKIN is also brownish, so
            colour alone would shave his arms.
  place   - the ball only exists near the right hand, so gate on distance from
            the RightHand bone.
Run with --dry 1 first: it reports what it WOULD delete without touching anything.
"""
import bpy, bmesh, math, os, sys, colorsys
from mathutils import Vector

def cli(n, d=None):
    a = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return a[a.index(n)+1] if n in a else d

SRC   = cli("--src", r"C:\Users\Kariim\Dev\hoopclone\assets\models\player_base.glb")
OUT   = cli("--out", r"C:\Users\Kariim\Dev\hoopclone\assets\models\player_noball.glb")
DRY   = cli("--dry", "1") == "1"
RADIUS = float(cli("--radius", "0.30"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
obj = next(o for o in bpy.data.objects if o.type == 'MESH')
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

# Which hand actually holds it: the first attempt assumed RightHand and bit a
# hole in the empty hand instead. Pick the hand with more ball-coloured faces
# around it rather than trusting the name.
HAND = cli("--hand", "auto")
hand_names = ["LeftHand", "RightHand"] if HAND == "auto" else [HAND]
hands = {}
for hn in hand_names:
    b = arm.data.bones.get(hn)
    if b is not None:
        hands[hn] = arm.matrix_world @ b.head_local
if not hands:
    raise SystemExit("no hand bones found")
for hn, hp in hands.items():
    print("BALL: %s at %.3f,%.3f,%.3f" % (hn, hp.x, hp.y, hp.z))

img = None
for mat in obj.data.materials:
    if mat and mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image:
                img = n.image
                break
if img is None:
    raise SystemExit("no albedo texture found")
W, H = img.size
px = list(img.pixels)
print("BALL: texture %s %dx%d" % (img.name, W, H))

def sample(u, v):
    x = min(W - 1, max(0, int(u % 1.0 * W)))
    y = min(H - 1, max(0, int(v % 1.0 * H)))
    i = (y * W + x) * 4
    return px[i], px[i+1], px[i+2]

me = obj.data
uvs = me.uv_layers.active.data
mw = obj.matrix_world

def scan(hand_pos):
    found = []
    skin = 0
    for poly in me.polygons:
        centre = mw @ Vector(poly.center)
        if (centre - hand_pos).length > RADIUS:
            continue
        u = v = 0.0
        for li in poly.loop_indices:
            uv = uvs[li].uv
            u += uv[0]; v += uv[1]
        u /= poly.loop_total; v /= poly.loop_total
        r, g, b = sample(u, v)
        h, s, val = colorsys.rgb_to_hsv(r, g, b)
        hue_deg = h * 360.0
        if 12.0 <= hue_deg <= 42.0 and s >= 0.55 and val >= 0.30:
            found.append(poly.index)
        elif 12.0 <= hue_deg <= 42.0:
            skin += 1
    return found, skin

scans = {hn: scan(hp) for hn, hp in hands.items()}
for hn, (f, s) in scans.items():
    print("BALL: %s -> %d ball-coloured faces nearby (%d skin-like)" % (hn, len(f), s))
best = max(scans.items(), key=lambda kv: len(kv[1][0]))
hand_name = best[0]
hand_pos = hands[hand_name]
hits, skin_like = best[1]
print("BALL: the ball is held in %s" % hand_name)

for poly in []:
    centre = mw @ Vector(poly.center)
    if (centre - hand_pos).length > RADIUS:
        continue
    u = v = 0.0
    for li in poly.loop_indices:
        uv = uvs[li].uv
        u += uv[0]; v += uv[1]
    u /= poly.loop_total; v /= poly.loop_total
    r, g, b = sample(u, v)
    h, s, val = colorsys.rgb_to_hsv(r, g, b)
    hue_deg = h * 360.0
    # Basketball leather: orange, strongly saturated and reasonably bright.
    # Skin sits at a similar hue but much lower saturation, so saturation is
    # what actually separates them.
    if 12.0 <= hue_deg <= 42.0 and s >= 0.55 and val >= 0.30:
        hits.append(poly.index)
    elif 12.0 <= hue_deg <= 42.0:
        skin_like += 1

print("BALL: %d faces near the hand match ball colour; %d nearby faces are skin-like and KEPT"
      % (len(hits), skin_like))

# Colour alone also catches orange trim on the kit and shoes, which is why the
# first pass spanned 0.47 m vertically - far too tall for a ball. Settle on the
# densest blob: take the median of the matches, then keep only what sits inside
# one ball radius of it, and repeat so the centre converges onto the ball itself.
BALL_RADIUS = float(cli("--ball-radius", "0.135"))
if hits:
    def centre_of(idxs):
        pts = [mw @ Vector(me.polygons[i].center) for i in idxs]
        n = float(len(pts))
        return Vector((sum(p.x for p in pts)/n, sum(p.y for p in pts)/n, sum(p.z for p in pts)/n))
    c = centre_of(hits)
    for _ in range(6):
        near = [i for i in hits if ((mw @ Vector(me.polygons[i].center)) - c).length <= BALL_RADIUS]
        if not near:
            break
        nc = centre_of(near)
        if (nc - c).length < 1e-4:
            c = nc
            break
        c = nc
    hits = [i for i in hits if ((mw @ Vector(me.polygons[i].center)) - c).length <= BALL_RADIUS]
    print("BALL: settled on centre %.3f,%.3f,%.3f -> %d faces inside one ball radius"
          % (c.x, c.y, c.z, len(hits)))

    # Colour finds the leather but misses the dark seam lines and the shaded
    # underside, which is why a shattered orange fringe survived the first cut.
    # Now that the centre is known, take the whole sphere GEOMETRICALLY - but
    # spare anything close to the hand bone itself, so the fingers gripping it
    # are not taken with it.
    # The sweep radius is deliberately wider than the radius used to FIND the
    # centre: a stray shard of leather hung just outside the tighter ball and
    # survived the first sweep.
    SWEEP = float(cli("--sweep", "0.175"))
    SPARE = float(cli("--spare", "0.062"))
    # Faces the colour test already flagged as leather are deleted even inside the
    # spare zone, otherwise a fleck of ball survives between the fingers.
    leather = set(hits)
    sphere = []
    spared = 0
    for poly in me.polygons:
        pc = mw @ Vector(poly.center)
        if (pc - c).length > SWEEP:
            continue
        if (pc - hand_pos).length <= SPARE and poly.index not in leather:
            spared += 1
            continue
        sphere.append(poly.index)
    print("BALL: geometric sweep -> %d faces in the ball sphere (%d spared as hand)"
          % (len(sphere), spared))
    hits = sphere

if hits:
    pts = [mw @ Vector(me.polygons[i].center) for i in hits]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = hi - lo
    print("BALL: matched cluster spans %.3f x %.3f x %.3f m (a real ball is ~0.24)"
          % (size.x, size.y, size.z))

# --- stray geometry ---
# The mesh ships with a few faces whose vertices sit nowhere near each other.
# Standing still they are invisible; the moment the rig moves, one end follows a
# bone and the face stretches into a long shard across the body. A real human
# mesh at this scale has no face longer than a hand span, so anything above the
# threshold is broken geometry, not anatomy.
LONG_EDGE = float(cli("--max-edge", "0.22"))
strays = []
for poly in me.polygons:
    vs = [mw @ me.vertices[i].co for i in poly.vertices]
    longest = 0.0
    for i in range(len(vs)):
        longest = max(longest, (vs[i] - vs[(i + 1) % len(vs)]).length)
    if longest > LONG_EDGE:
        strays.append(poly.index)
print("BALL: %d stray faces with an edge longer than %.2f m" % (len(strays), LONG_EDGE))

if DRY:
    print("BALL: dry run - nothing deleted")
else:
    bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    doomed = [bm.faces[i] for i in sorted(set(hits) | set(strays))]
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    bm.to_mesh(me); bm.free()
    print("BALL: deleted %d faces; mesh now %d polys" % (len(hits), len(me.polygons)))
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_apply=False,
                              export_animations=True, export_animation_mode='ACTIONS',
                              export_image_format='AUTO')
    print("BALL: exported %s (%d bytes)" % (OUT, os.path.getsize(OUT)))
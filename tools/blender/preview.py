"""Quick Workbench render of built .blend files, for checking models without Godot.
    blender -b -P tools/blender/preview.py -- <out.png> <a.blend> [<b.blend> ...]
"""
import sys, math, bpy
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
heads = "--heads" in argv
argv = [a for a in argv if a != "--heads"]
out, files = argv[0], argv[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
x = -(len(files) - 1) * 0.6
for f in files:
    with bpy.data.libraries.load(f) as (src, dst):
        dst.objects = src.objects
    for o in dst.objects:
        bpy.context.scene.collection.objects.link(o)
        if o.parent is None:
            o.location.x += x
        if o.name.startswith(("Blood_",)):
            o.hide_render = True
    x += 1.2
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
bpy.context.scene.collection.objects.link(cam)
n = len(files)
cam.location = (2.2 + n * 0.3, 3.5 + n * 0.9, 1.6)
cam.rotation_euler = (math.radians(84), 0, math.radians(148))
cam.data.lens = 50
if heads:
    cam.location = (0.0, 1.2 + n * 0.75, 1.68)
    cam.rotation_euler = (math.radians(90), 0, math.radians(180))
    cam.data.lens = 70
bpy.context.scene.camera = cam
s = bpy.context.scene
s.render.engine = "CYCLES"
s.cycles.device = "CPU"
s.cycles.samples = 24
s.cycles.use_denoising = False
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.55, 0.5, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
s.world = world
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(40), 0, math.radians(160))
s.collection.objects.link(sun)
s.render.resolution_x, s.render.resolution_y = 900, 900
s.render.filepath = out
bpy.ops.render.render(write_still=True)

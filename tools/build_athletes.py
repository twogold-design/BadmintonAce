"""Build the replacement athletes from a coherent CC0 humanoid mesh and rig.

Blender 4.4+: --background --factory-startup --python tools/build_athletes.py
Keep original anatomical proportions and skin weights. Never force the new
model into the dimensions of the discarded procedural characters.
"""
import bpy,bmesh,math,json
from pathlib import Path
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/athletes';SOURCE=OUT/'source'
bpy.context.preferences.filepaths.save_version=0

def mat(name,color):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.8
 return m
def apply(obj,mod):
 bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=mod.name)
def bind(obj,rig):
 mod=obj.modifiers.new('Athlete skin','ARMATURE');mod.object=rig;obj.parent=rig
def shoe(body,rig,side,white,rubber):
 sx=1 if side=='l' else -1
 points=[v.co.copy() for v in body.data.vertices if v.co.z<.10 and v.co.x*sx>0]
 center=rig.data.bones['foot_'+side].head_local
 bm=bmesh.new()
 for p in points:
  p.x=center.x+(p.x-center.x)*1.08;p.y-=.005;p.z=max(.005,p.z+.006)
  bm.verts.new(p)
 bmesh.ops.convex_hull(bm,input=list(bm.verts))
 bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
 mesh=bpy.data.meshes.new('CourtShoe_'+side);bm.to_mesh(mesh);bm.free();mesh.update()
 obj=bpy.data.objects.new('CourtShoe_'+side,mesh);bpy.context.collection.objects.link(obj)
 mesh.materials.append(white);mesh.materials.append(rubber)
 for p in mesh.polygons:p.use_smooth=True;p.material_index=1 if p.center.z<.026 else 0
 bevel=obj.modifiers.new('Shoe edge','BEVEL');bevel.width=.008;bevel.segments=3;apply(obj,bevel)
 obj.vertex_groups.new(name='foot_'+side).add(list(range(len(obj.data.vertices))),1,'REPLACE');bind(obj,rig)
 return obj

def ponytail(rig,objects):
 # Retain the fitted scalp and small swept fringe; discard buns and loose locks.
 for obj in objects:
  if obj.type!='MESH' or not obj.modifiers:continue
  bm=bmesh.new();bm.from_mesh(obj.data)
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00002)
  unseen=set(bm.verts);components=[]
  while unseen:
   stack=[unseen.pop()];component=set(stack)
   while stack:
    for edge in stack.pop().link_edges:
     for vertex in edge.verts:
      if vertex in unseen:unseen.remove(vertex);component.add(vertex);stack.append(vertex)
   components.append(component)
  scalp=max(components,key=len)
  remove=[v for c in components if c is not scalp and not (len(c)<80 and min(v.co.z for v in c)>1.67) for v in c]
  bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(obj.data);bm.free()
 bpy.context.view_layer.objects.active=rig;rig.select_set(True)
 bpy.ops.object.mode_set(mode='EDIT')
 bone=rig.data.edit_bones.new('ponytail');bone.head=(0,.109,1.707);bone.tail=(0,.19,1.51);bone.parent=rig.data.edit_bones['Head']
 bpy.ops.object.mode_set(mode='OBJECT')
 hair=mat('Ace_Ponytail',(.035,.025,.025))
 vertices=[];faces=[];rings=26;sides=20
 for k in range(rings):
  t=k/(rings-1)
  center=Vector((0,.108+.105*math.sin(t*math.pi*.62),1.708-.305*t+.045*math.sin(math.pi*t)))
  tangent=Vector((0,.105*math.pi*.62*math.cos(t*math.pi*.62),-.305+.045*math.pi*math.cos(math.pi*t))).normalized()
  across=Vector((1,0,0));other=tangent.cross(across).normalized()
  radius=(.025+.014*math.sin(math.pi*t))*(1-t**3)*.98+.0015
  for j in range(sides):
   a=j*math.tau/sides;r=radius*(1+.045*math.cos(a*7))
   vertices.append(center+across*(math.cos(a)*r)+other*(math.sin(a)*r*.85))
  if k:
   for j in range(sides):faces.append(((k-1)*sides+j,(k-1)*sides+(j+1)%sides,k*sides+(j+1)%sides,k*sides+j))
 faces.extend([tuple(reversed(range(sides))),tuple((rings-1)*sides+j for j in range(sides))])
 mesh=bpy.data.meshes.new('SweptPonytail');mesh.from_pydata(vertices,[],faces);mesh.update()
 obj=bpy.data.objects.new('SweptPonytail',mesh);bpy.context.collection.objects.link(obj);mesh.materials.append(hair)
 for p in mesh.polygons:p.use_smooth=True
 head=obj.vertex_groups.new(name='Head');tail=obj.vertex_groups.new(name='ponytail')
 for v in mesh.vertices:
  weight=min(1,(v.index//sides)/5);head.add([v.index],1-weight,'REPLACE');tail.add([v.index],weight,'REPLACE')
 bind(obj,rig)
 bpy.ops.mesh.primitive_torus_add(major_radius=.025,minor_radius=.004,major_segments=24,minor_segments=8,location=(0,.111,1.702))
 tie=bpy.context.object;tie.name='PonytailTie';tie.rotation_euler.x=.42
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 tie.data.materials.append(mat('HairTie',(.10,.14,.17)));tie.vertex_groups.new(name='Head').add(list(range(len(tie.data.vertices))),1,'REPLACE');bind(tie,rig)

def build(gender):
 for obj in list(bpy.data.objects):bpy.data.objects.remove(obj,do_unlink=True)
 female=gender=='female'
 bpy.ops.import_scene.gltf(filepath=str(SOURCE/'base'/('Superhero_'+gender.title()+'_FullBody.gltf')))
 rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
 body=max((o for o in bpy.context.scene.objects if o.type=='MESH' and o.modifiers),key=lambda o:len(o.data.vertices))
 # Athlete silhouette: retain skeletal landmarks and reduce superhero bulk.
 for v in body.data.vertices:
  x,y,z=v.co
  shoulder=rig.data.bones['upperarm_l' if x>0 else 'upperarm_r'].head_local
  if abs(x)>abs(shoulder.x)+.02 and abs(z-shoulder.z)<.15:
   v.co.y=shoulder.y+(y-shoulder.y)*.84;v.co.z=shoulder.z+(z-shoulder.z)*.84
  if female and 1.18<z<1.43 and abs(x)<.18 and y<-.045:
   amount=.30*math.sin(math.pi*(z-1.18)/.25)
   v.co.y=-.045+(y+.045)*(1-amount)
  if .80<z<1.04 and y>.065:v.co.y=.065+(y-.065)*.8
 body.data.update()
 for obj in list(bpy.context.scene.objects):
  if obj.type=='MESH' and not obj.modifiers:bpy.data.objects.remove(obj,do_unlink=True)
 before=set(bpy.context.scene.objects)
 bpy.ops.import_scene.gltf(filepath=str(SOURCE/'hair'/('Hair_Buns.gltf' if female else 'Hair_SimpleParted.gltf')))
 extras=set(bpy.context.scene.objects)-before
 hair_objects=[obj for obj in extras if obj.type=='MESH' and obj.modifiers]
 for obj in extras:
  if obj.type=='MESH' and obj.modifiers:
   obj.parent=rig
   for mod in obj.modifiers:
    if mod.type=='ARMATURE':mod.object=rig
  elif obj.type!='MESH' or not obj.modifiers:bpy.data.objects.remove(obj,do_unlink=True)
 if female:ponytail(rig,hair_objects)
 for material in bpy.data.materials:
  if 'Hair' in material.name:
   material.diffuse_color=(.035,.025,.025,1)
   if material.use_nodes:
    p=material.node_tree.nodes.get('Principled BSDF')
    if p:
     for link in list(p.inputs['Base Color'].links):material.node_tree.links.remove(link)
     p.inputs['Base Color'].default_value=(.035,.025,.025,1)
 # Professional base rig and original topology remain intact. Use flat sports
 # fabrics over the existing skinned anatomy, with ordinary garment seams.
 cloth=mat('Ace_Jersey',(.47,.65,.23));dark=mat('Ace_Shorts',(.022,.046,.066));white=mat('Ace_Shoes',(.78,.82,.80));rubber=mat('Ace_Sole',(.055,.075,.085))
 # Fitted sports kit shares the body's continuous topology and exact skin weights.
 # No disconnected sleeves, floating collar or separately stretched waist pieces.
 # Continuous rest-space garment coordinates give clean collar/cuff/hem edges
 # independently of the body's triangle layout, even while the body bends.
 while len(body.data.uv_layers)>1:body.data.uv_layers.remove(body.data.uv_layers[-1])
 garment_uv=body.data.uv_layers.new(name='GarmentCoordinates')
 for loop in body.data.loops:
  co=body.data.vertices[loop.vertex_index].co
  garment_uv.data[loop.index].uv=(co.x,1-co.z)
 for side in ['l','r']:shoe(body,rig,side,white,rubber)
 reference=body.copy();reference.data=body.data.copy();reference.name='EditableFullBody'
 bpy.context.collection.objects.link(reference);reference.hide_render=True;reference.hide_viewport=True
 # Runtime sports kit uses the base colour only; unused normal/roughness maps
 # would be duplicated in both the web PCK and local-file fallback bundle.
 for material in bpy.data.materials:
  if material.use_nodes:
   shader=material.node_tree.nodes.get('Principled BSDF')
   if shader:
    for socket in ['Normal','Roughness','Metallic']:
     for link in list(shader.inputs[socket].links):material.node_tree.links.remove(link)
 # Pack compact textures; these are game assets, not network requests.
 for image in bpy.data.images:
  if image.source=='FILE' and max(image.size)>512:
   ratio=512/max(image.size);image.scale(round(image.size[0]*ratio),round(image.size[1]*ratio))
  if image.source=='FILE':image.pack()
 # Face the net (-Z after glTF import) and preserve proportions, including neck.
 rotation=Matrix.Rotation(math.pi,4,'Z')
 for obj in [rig]+[o for o in bpy.context.scene.objects if o.type=='MESH']:
  obj.data.transform(rotation)
 # Write rig measurements for animation from this model, not from old constants.
 measures={b.name:{'head':[round(v,7) for v in (b.head_local.x,b.head_local.z,-b.head_local.y)],'tail':[round(v,7) for v in (b.tail_local.x,b.tail_local.z,-b.tail_local.y)],'parent':b.parent.name if b.parent else None} for b in rig.data.bones}
 (OUT/(gender+'-rig.json')).write_text(json.dumps(measures,indent=2),encoding='utf-8')
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
 for obj in bpy.context.scene.objects:
  if obj.type=='MESH' and not obj.hide_viewport:obj.select_set(True)
 bpy.context.view_layer.objects.active=rig
 bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(gender+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/(gender+'.glb')),export_format='GLB',use_selection=True,export_animations=False,export_skins=True)
 print('FRESH ATHLETE',gender,'GLB bytes',(OUT/(gender+'.glb')).stat().st_size)

for gender in ['male','female']:build(gender)

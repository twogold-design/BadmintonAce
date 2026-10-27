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

def smoothstep(a,b,value):
 t=max(0,min(1,(value-a)/(b-a)));return t*t*(3-2*t)

def regular_jersey(body,rig,female,cloth):
 # Cut a single connected garment from the original weighted topology, then
 # tailor a regular sports fit. The underlying anatomy and rig are unchanged.
 shirt=body.copy();shirt.data=body.data.copy();shirt.name='MatchTShirt'
 bpy.context.collection.objects.link(shirt)
 shoulder=rig.data.bones['upperarm_l'].head_local.copy()
 neck=rig.data.bones['neck_01'].head_local.z
 hem=.950 if female else .970
 cuff=abs(shoulder.x)+.125
 def collar(x):return neck-.018+.070*smoothstep(.025,.110,abs(x))
 # Tailor each height to the actual athlete: the previous almost-constant
 # ellipse added too much depth and made the shirt look inflated.
 sections=([
  (hem,.196,.103,.165),(1.06,.173,.108,.139),(1.17,.149,.114,.104),
  (1.28,.157,.119,.113),(1.37,.164,.120,.132)
 ] if female else [
  (hem,.183,.115,.158),(1.08,.174,.116,.135),(1.18,.177,.123,.117),
  (1.30,.193,.139,.146),(1.40,.211,.130,.161)
 ])
 def section(z):
  if z<=sections[0][0]:return sections[0][1:]
  for a,b in zip(sections,sections[1:]):
   if z<=b[0]:
    t=smoothstep(a[0],b[0],z)
    return tuple(a[k]+(b[k]-a[k])*t for k in range(1,4))
  return sections[-1][1:]
 bm=bmesh.new();bm.from_mesh(shirt.data)
 bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00002)
 def cut(point,normal):
  bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,plane_co=point,plane_no=normal,clear_outer=True,clear_inner=False)
 # Start above the hip topology. A shirt has one open hem, unlike the two
 # branching leg loops in the anatomical mesh below the pelvis.
 lower_seam=1.10
 cut((0,0,lower_seam),(0,0,-1))
 cut((cuff,0,0),(1,0,0));cut((-cuff,0,0),(-1,0,0))
 # Flatten the curved neckline only for cutting; retain all interpolated weights.
 for v in bm.verts:v.co.z-=collar(v.co.x)
 cut((0,0,0),(0,0,1))
 for v in bm.verts:v.co.z+=collar(v.co.x)
 bm.normal_update()
 for v in bm.verts:
  original=v.co.copy();x,y,z=original
  base=original+v.normal*.004
  torso=(1-smoothstep(shoulder.z-.035,shoulder.z+.060,z))*(1-smoothstep(abs(shoulder.x)-.015,abs(shoulder.x)+.065,abs(x)))
  angle=math.atan2(y+.012,x)
  # Mildly tapered side seams and a smooth front: enough ease to move without
  # tracing individual muscles or making an oversized, flared garment.
  width,front,back=section(z)
  depth=back if y>-.012 else front
  drape=Vector((width*math.cos(angle),-.012+depth*math.sin(angle),z))
  base=base.lerp(drape,torso)
  sleeve=smoothstep(abs(shoulder.x)-.005,abs(shoulder.x)+.075,abs(x))
  radial=Vector((0,y-shoulder.y,z-shoulder.z))
  if radial.length>.0001:
   sleeve_point=original+radial.normalized()*.006
   base=base.lerp(sleeve_point,sleeve)
  v.co=base
 # Extend the waist as complete fabric rings. This makes a clean, continuous
 # bottom edge and avoids inheriting the pelvis/buttock cleft in the garment.
 lower_edges=[edge for edge in bm.edges if edge.is_boundary and all(abs(v.co.z-lower_seam)<.012 for v in edge.verts)]
 assert lower_edges, 'T-shirt waist boundary missing'
 for ring in range(1,7):
  z=lower_seam+(hem-lower_seam)*ring/6
  result=bmesh.ops.extrude_edge_only(bm,edges=lower_edges)
  new_vertices=[item for item in result['geom'] if isinstance(item,bmesh.types.BMVert)]
  width,front,back=section(z)
  for v in new_vertices:
   # Preserve the angle on an ellipse, rather than accumulating radial drift.
   previous_width,previous_front,previous_back=section(v.co.z)
   previous_depth=previous_back if v.co.y>-.012 else previous_front
   angle=math.atan2((v.co.y+.012)/previous_depth,v.co.x/previous_width)
   depth=back if math.sin(angle)>0 else front
   v.co=Vector((width*math.cos(angle),-.012+depth*math.sin(angle),z))
  new_set=set(new_vertices)
  lower_edges=[edge for edge in bm.edges if edge.is_boundary and all(v in new_set for v in edge.verts)]
 # A hem belongs to the pelvis, not to independently moving thigh bones.
 # Uniform cuff weights likewise keep its edge clean as the arm rotates.
 weights=bm.verts.layers.deform.verify()
 pelvis=shirt.vertex_groups['pelvis'].index
 for v in bm.verts:
  low=1-smoothstep(hem+.025,hem+.115,v.co.z)
  arm=smoothstep(cuff-.055,cuff-.020,abs(v.co.x))
  target=shirt.vertex_groups['upperarm_l' if v.co.x>0 else 'upperarm_r'].index if arm>low else pelvis
  amount=max(low,arm)
  if amount>0:
   deform=v[weights]
   for group in list(deform.keys()):deform[group]*=1-amount
   deform[target]=deform.get(target,0)+amount
 # Relax transitions around the axilla without shrinking the open hems/cuffs.
 inner=[v for v in bm.verts if not v.is_boundary]
 for _ in range(4):bmesh.ops.smooth_vert(bm,verts=inner,factor=.35,use_axis_x=True,use_axis_y=True,use_axis_z=True)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(shirt.data);bm.free()
 shirt.data.materials.clear();shirt.data.materials.append(cloth)
 for polygon in shirt.data.polygons:polygon.material_index=0;polygon.use_smooth=True
 # Four times the surface faces, smoothly interpolated weights and clean
 # collar/cuff silhouettes. Subdivide before fabric thickness, not after it.
 subdivision=shirt.modifiers.new('Fine garment surface','SUBSURF')
 subdivision.subdivision_type='CATMULL_CLARK';subdivision.levels=1;subdivision.render_levels=1
 apply(shirt,subdivision)
 for v in shirt.data.vertices:
  x,y,z=v.co
  if z<1.28 and abs(x)<.23:
   # Small vertical fabric folds near the side seams; no large radial bulges.
   edge=smoothstep(.04,.16,abs(x));fade=1-smoothstep(1.12,1.28,z)
   v.co.y+=(1 if y>-.012 else -1)*.0018*edge*fade*math.sin(x*110+z*7)
 uv=shirt.data.uv_layers.get('GarmentCoordinates')
 for loop in shirt.data.loops:
  co=shirt.data.vertices[loop.vertex_index].co
  uv.data[loop.index].uv=(co.x,1-co.z)
 # Real fabric thickness leaves open collar/cuffs/hem rather than painted edges.
 solid=shirt.modifiers.new('Fabric thickness','SOLIDIFY');solid.thickness=.0015;solid.offset=-1
 apply(shirt,solid)
 # Omit covered body triangles to prevent skin poking through on overhead shots.
 # Keep a small overlap at every opening; EditableFullBody retains the anatomy.
 bm=bmesh.new();bm.from_mesh(body.data)
 def split(point,normal):
  bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,plane_co=point,plane_no=normal,clear_outer=False,clear_inner=False)
 # Split crossing triangles at the openings, so a large retained hip/neck
 # triangle cannot poke through the cloth merely because one corner is outside.
 split((0,0,hem-.004),(0,0,1))
 split((cuff-.008,0,0),(1,0,0));split((-cuff+.008,0,0),(1,0,0))
 for v in bm.verts:v.co.z-=collar(v.co.x)-.004
 split((0,0,0),(0,0,1))
 for v in bm.verts:v.co.z+=collar(v.co.x)-.004
 covered=[]
 for f in bm.faces:
  co=f.calc_center_median()
  if co.z>hem-.003 and co.z<collar(co.x)-.004 and abs(co.x)<cuff-.008:covered.append(f)
 bmesh.ops.delete(bm,geom=covered,context='FACES');bm.to_mesh(body.data);bm.free()
 print('REGULAR JERSEY', 'female' if female else 'male',len(shirt.data.vertices),'vertices; hem',hem,'cuff',round(cuff,3))
 return shirt
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
 # Keep anatomical proportions and use a separate, continuous regular T-shirt.
 cloth=mat('Ace_Jersey',(.47,.65,.23));dark=mat('Ace_Shorts',(.022,.046,.066));white=mat('Ace_Shoes',(.78,.82,.80));rubber=mat('Ace_Sole',(.055,.075,.085))
 # Rest-space garment coordinates keep the remaining shorts/sock edges clean.
 while len(body.data.uv_layers)>1:body.data.uv_layers.remove(body.data.uv_layers[-1])
 garment_uv=body.data.uv_layers.new(name='GarmentCoordinates')
 for loop in body.data.loops:
  co=body.data.vertices[loop.vertex_index].co
  garment_uv.data[loop.index].uv=(co.x,1-co.z)
 for side in ['l','r']:shoe(body,rig,side,white,rubber)
 reference=body.copy();reference.data=body.data.copy();reference.name='EditableFullBody'
 bpy.context.collection.objects.link(reference);reference.hide_render=True;reference.hide_viewport=True
 regular_jersey(body,rig,female,cloth)
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

extends SceneTree
## Rebuild compact audience meshes and six anatomically posed GPU keyframes.
## Source characters and their licenses remain in assets/athletes.
const ATHLETE = preload("res://scripts/athlete_3d.gd")
const SOURCE = preload("res://tools/crowd_mesh_source.gd")
const PROPS = preload("res://tools/crowd_props_source.gd")
const WIDTH = 512
var prop_transform = Transform3D.IDENTITY

func _initialize(): call_deferred("run")

func hand_rotation(person, side: String, forward: Vector3, clapping: bool) -> Basis:
	var finger: Vector3 = (person.rest_at("middle_01_"+side)-person.rest_at("hand_"+side)).normalized()
	var thumb: Vector3 = person.rest_at("thumb_01_"+side)-person.rest_at("hand_"+side)
	thumb = (thumb-finger*thumb.dot(finger)).normalized()
	var thumb_direction = Vector3.UP if clapping else Vector3(1 if side=="l" else -1,0,0)
	var up = (thumb_direction-forward*thumb_direction.dot(forward)).normalized()
	return Basis(forward,up,forward.cross(up))*Basis(finger,thumb,finger.cross(thumb)).transposed()

func set_pose(person, frame: int, kind: String) -> void:
	person.desired.clear()
	var standing = frame>=4
	var clapping = frame>=2
	var closed = frame%2==1
	var pelvis = Vector3(0,.56,.04) if not standing else Vector3(0,person.rest_at("pelvis").y,-.30)
	var torso = Basis(Vector3.RIGHT,-.14 if frame==1 else -.035)
	person.pose("pelvis",pelvis,Basis.IDENTITY)
	for bone in ["spine_01","spine_02","spine_03","neck_01","Head"]:
		var p: Vector3 = pelvis+torso*(person.rest_at(bone)-person.rest_at("pelvis"))
		person.pose(bone,p,torso*Basis(Vector3.UP,-.10 if frame==1 else .04) if bone=="Head" else torso)
	for side in ["l","r"]:
		var sx = -1.0 if side=="l" else 1.0
		var hip: Vector3 = pelvis+person.rest_at("thigh_"+side)-person.rest_at("pelvis")
		# Foot targets remain identical through sitting and standing transitions.
		var ankle = Vector3(sx*.155,person.rest_at("foot_"+side).y,-.40)
		person.limb("thigh_"+side,"calf_"+side,"foot_"+side,hip,ankle,hip+Vector3(sx*.03,0,-1),person.length_between("thigh_"+side,"calf_"+side),person.length_between("calf_"+side,"foot_"+side),Basis.IDENTITY)
		var shoulder: Vector3 = pelvis+torso*(person.rest_at("upperarm_"+side)-person.rest_at("pelvis"))
		var wrist: Vector3
		if clapping:
			wrist = Vector3(sx*(.052 if closed else .17),shoulder.y-.19,shoulder.z-.34)
		else:
			wrist = Vector3(sx*.16,.58,-.27)
		var forward = Vector3(0,.65,-.76).normalized() if clapping else Vector3(0,-.25,-.97).normalized()
		var holding = side=="r" and kind!="plain"
		var palm_clapping = clapping
		if kind!="plain":
			# The free hand stays on the thigh; a prop holder never claps through it.
			wrist = Vector3(sx*.16,.58+(pelvis.y-.56),-.27+(pelvis.z-.04))
			forward = Vector3(0,-.25,-.97).normalized()
			palm_clapping = false
		if holding:
			var axis: Vector3
			if kind=="flag":
				wrist = shoulder+Vector3(.10,.10 if clapping else -.28,-.27)
				axis = Vector3(.12 if not closed else -.08,1,-.12).normalized()
				forward = Vector3(0,.1,-1).normalized()
			else:
				var head: Vector3 = pelvis+torso*(person.rest_at("Head")-person.rest_at("pelvis"))
				axis = Vector3(.30,.10,-1).normalized() if clapping else Vector3(.15,.9,-.4).normalized()
				wrist = head+Vector3(.04,-.10,-.20)+axis*.13 if clapping else shoulder+Vector3(.08,-.28,-.27)
				forward = Vector3(-.05,-.3,-1).normalized()
			palm_clapping = true
			prop_transform = Transform3D(Basis(Quaternion(Vector3.UP,axis)),wrist+forward*.065)
		person.limb("upperarm_"+side,"lowerarm_"+side,"hand_"+side,shoulder,wrist,shoulder+Vector3(sx*.18,-.48,.03),person.length_between("upperarm_"+side,"lowerarm_"+side),person.length_between("lowerarm_"+side,"hand_"+side),hand_rotation(person,side,forward,palm_clapping))
	# Propagate the hand pose without the athlete's automatic racket-finger curl.
	for id in range(person.skeleton.get_bone_count()):
		var parent = person.skeleton.get_bone_parent(id)
		var rest = person.skeleton.get_bone_rest(id)
		var bone_name: String = person.skeleton.get_bone_name(id)
		if kind!="plain" and bone_name.ends_with("_r") and not "leaf" in bone_name and (bone_name.begins_with("index_") or bone_name.begins_with("middle_") or bone_name.begins_with("ring_") or bone_name.begins_with("pinky_")):
			var axis: Vector3 = (person.rests[id].basis.inverse()*Vector3(0,0,-1)).normalized()
			rest.basis *= Basis(axis,.85 if "_01_" in bone_name else .95)
		person.poses[id] = person.desired.get(id,person.poses[parent]*rest if parent>=0 else rest)

func add_chair(data: Dictionary) -> void:
	for item in [
		[Vector3(0,.48,.08),Vector3(.46,.065,.43),Color("34434a")],
		[Vector3(0,.72,.28),Vector3(.46,.43,.055),Color("34434a")],
		[Vector3(-.19,.24,-.08),Vector3(.035,.48,.035),Color("3b4145")],
		[Vector3(.19,.24,-.08),Vector3(.035,.48,.035),Color("3b4145")],
		[Vector3(-.19,.24,.24),Vector3(.035,.48,.035),Color("3b4145")],
		[Vector3(.19,.24,.24),Vector3(.035,.48,.035),Color("3b4145")]]:
		var box = BoxMesh.new()
		box.size = item[1]
		var arrays = box.get_mesh_arrays()
		var offset: int = data.vertices.size()
		for i in range(arrays[Mesh.ARRAY_VERTEX].size()):
			data.vertices.append({"position":arrays[Mesh.ARRAY_VERTEX][i]+item[0],"normal":arrays[Mesh.ARRAY_NORMAL][i],"color":item[2].srgb_to_linear(),"shirt":0.0,"garment":Vector2.ZERO,"bones":PackedInt32Array(),"weights":PackedFloat32Array()})
		for index in arrays[Mesh.ARRAY_INDEX]: data.indices.append(offset+index)

func bake(gender: String, kind: String) -> void:
	var person = ATHLETE.new()
	root.add_child(person)
	person.build(gender,0)
	var data = SOURCE.extract(person)
	if kind!="plain": PROPS.append(data,kind)
	add_chair(data)
	var count: int = data.vertices.size()
	var rows = ceili(float(count)/WIDTH)
	var image = Image.create(WIDTH,rows*12,false,Image.FORMAT_RGBAF)
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	var uv = PackedVector2Array()
	var uv2 = PackedVector2Array()
	for frame in range(6):
		set_pose(person,frame,kind)
		var transforms: Array[Transform3D] = []
		for bone in range(person.rests.size()): transforms.append(person.poses[bone]*person.rests[bone].affine_inverse())
		for i in range(count):
			var source: Dictionary = data.vertices[i]
			var p = Vector3.ZERO
			var n = Vector3.ZERO
			if source.get("prop",false):
				p = prop_transform*source.position
				n = prop_transform.basis*source.normal
			elif source.bones.is_empty():
				p = source.position
				n = source.normal
			else:
				for j in range(source.bones.size()):
					p += transforms[source.bones[j]]*source.position*source.weights[j]
					n += transforms[source.bones[j]].basis*source.normal*source.weights[j]
			n = n.normalized()
			image.set_pixel(i%WIDTH,i/WIDTH+frame*rows*2,Color(p.x,p.y,p.z,1))
			image.set_pixel(i%WIDTH,i/WIDTH+(frame*2+1)*rows,Color(n.x,n.y,n.z,1))
			if frame==0:
				vertices.append(p)
				normals.append(n)
				colors.append(source.color)
				uv.append(source.get("garment",Vector2.ZERO))
				uv2.append(Vector2(i,source.shirt))
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = data.indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var stem = gender+("" if kind=="plain" else "-"+kind)
	ResourceSaver.save(mesh,"res://assets/crowd/"+stem+".res")
	ResourceSaver.save(ImageTexture.create_from_image(image),"res://assets/crowd/"+stem+"-poses.res",ResourceSaver.FLAG_COMPRESS)
	print("CROWD BAKE ",stem,": ",count," vertices / ",data.indices.size()/3," triangles; pose rows=",rows)
	person.queue_free()

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/crowd")
	for gender in ["male","female"]:
		for kind in ["plain","flag","horn"]: bake(gender,kind)
	quit()

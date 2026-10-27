extends Node3D
## A real, lit 3D athlete: Skeleton3D, skinned jersey, articulated limbs and racket.
## All animation targets live in metres in the court, never in screen coordinates.

const MALE = preload("res://assets/athletes/male.glb")
const FEMALE = preload("res://assets/athletes/female.glb")
const RACKET_CENTER = .58
var desired: Dictionary = {}
var racket_contact_world = Vector3.ZERO
var skeleton: Skeleton3D
var bones: Dictionary = {}
var rests: Array[Transform3D] = []
var poses: Array[Transform3D] = []
var attachments: Dictionary = {}
var racket: Node3D
var gender = ""
var team = 0
var head_node: Node3D
var racket_center_world = Vector3.ZERO
var contact_error = 0.0
var joint_points: Dictionary = {}

static func material(color: Color, roughness: float = .72) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

static func mesh(parent: Node3D, shape: Mesh, mat: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.mesh = shape
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node

static func ellipsoid(parent: Node3D, at: Vector3, radii: Vector3, mat: Material) -> MeshInstance3D:
	var shape = SphereMesh.new()
	shape.radius = 1
	shape.height = 2
	shape.radial_segments = 20
	shape.rings = 12
	var node = mesh(parent,shape,mat,at)
	node.scale = radii
	return node

static func bar(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material, end_radius: float = -1) -> MeshInstance3D:
	var shape = CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius if end_radius<0 else end_radius
	shape.height = a.distance_to(b)
	shape.radial_segments = 12
	var node = mesh(parent,shape,mat,(a+b)*.5)
	node.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return node

func build(avatar: String, index: int) -> void:
	gender = avatar
	team = index
	for child in get_children():
		remove_child(child)
		child.queue_free()
	bones.clear()
	rests.clear()
	poses.clear()
	attachments.clear()
	var model = (FEMALE if avatar=="female" else MALE).instantiate()
	add_child(model)
	skeleton = model.find_children("*","Skeleton3D",true,false)[0]
	for id in range(skeleton.get_bone_count()):
		var name_: String = skeleton.get_bone_name(id)
		bones[name_] = id
		var parent = skeleton.get_bone_parent(id)
		var rest = skeleton.get_bone_rest(id)
		var global_rest = rests[parent]*rest if parent>=0 else rest
		rests.append(global_rest)
		poses.append(global_rest)
		if name_=="hand_r":
			var mount = BoneAttachment3D.new()
			mount.bone_name = name_
			skeleton.add_child(mount)
			attachments[name_] = mount
	var accent = material(Color("b8de65") if index==0 else Color("ee8976"))
	var dark = material(Color("142b39"))
	var white = material(Color("e9ede7"))
	preload("res://scripts/athlete_materials.gd").apply(model,index,avatar=="female")
	racket = Node3D.new()
	attachments.hand_r.add_child(racket)
	racket.basis = Basis.IDENTITY
	make_racket(racket,accent,dark,white)

static func make_racket(parent: Node3D, accent: Material, dark: Material, white: Material) -> void:
	bar(parent,Vector3(0,-.045,0),Vector3(0,.12,0),.018,dark)
	bar(parent,Vector3(0,.10,0),Vector3(0,.36,0),.007,white)
	# The string bed is an actual elliptical 3D frame, centred 0.58 m from the wrist.
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(48):
		var a = k*TAU/48.0
		var b = (k+1)*TAU/48.0
		for j in range(6):
			var points = []
			for pair in [[a,j],[b,j],[a,j+1],[b,j+1]]:
				var t: float = pair[0]
				var cross_angle = float(pair[1])*TAU/6
				points.append(Vector3(cos(t)*(.125+.008*cos(cross_angle)),.58+sin(t)*(.172+.008*cos(cross_angle)),.008*sin(cross_angle)))
			for id in [0,1,2,1,3,2]: surface.add_vertex(points[id])
	surface.generate_normals()
	mesh(parent,surface.commit(),accent)
	var strings = SurfaceTool.new()
	strings.begin(Mesh.PRIMITIVE_TRIANGLES)
	# World-space thread thickness: screen-space GL lines turned into an opaque
	# white disc when a distant racket was only a few pixels wide.
	for k in range(-4,5):
		var x = k*.024
		var h = .168*sqrt(maxf(0,1-pow(x/.125,2)))
		string_thread(strings,Vector3(x,.58-h,0),Vector3(x,.58+h,0))
	for k in range(-5,6):
		var y = k*.028
		var w = .122*sqrt(maxf(0,1-pow(y/.172,2)))
		string_thread(strings,Vector3(-w,.58+y,.0005),Vector3(w,.58+y,.0005))
	strings.generate_normals()
	var string_mesh = mesh(parent,strings.commit(),material(Color("6b8285")))
	string_mesh.name = "OpenStringBed"
	string_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func string_thread(surface: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var tangent = (b-a).normalized()
	var normal = tangent.cross(Vector3.FORWARD).normalized()
	for j in range(4):
		var u = (normal*cos(j*TAU/4)+Vector3.FORWARD*sin(j*TAU/4))*.0008
		var v = (normal*cos((j+1)*TAU/4)+Vector3.FORWARD*sin((j+1)*TAU/4))*.0008
		for point in [a+u,b+u,a+v,b+u,b+v,a+v]: surface.add_vertex(point)

func pose(name_: String, at: Vector3, basis_: Basis) -> void:
	var id: int = bones[name_]
	desired[id] = Transform3D(basis_*rests[id].basis,at)

func rest_at(name_: String) -> Vector3:
	return rests[bones[name_]].origin

func length_between(a: String, b: String) -> float:
	return rest_at(a).distance_to(rest_at(b))

func apply_poses() -> void:
	for id in range(skeleton.get_bone_count()):
		var parent = skeleton.get_bone_parent(id)
		var rest = skeleton.get_bone_rest(id)
		var name_: String = skeleton.get_bone_name(id)
		if name_.ends_with("_r") and (name_.begins_with("index_") or name_.begins_with("middle_") or name_.begins_with("ring_") or name_.begins_with("pinky_")) and not "leaf" in name_:
			var curl = .70 if "_01_" in name_ else 1.10
			var axis = rests[id].basis.inverse()*Vector3(0,0,-1)
			rest.basis = rest.basis*Basis(axis.normalized(),curl)
		var inherited = poses[parent]*rest if parent>=0 else rest
		poses[id] = desired.get(id,inherited)
		var local = poses[parent].affine_inverse()*poses[id] if parent>=0 else poses[id]
		skeleton.set_bone_pose_position(id,local.origin)
		skeleton.set_bone_pose_rotation(id,local.basis.get_rotation_quaternion().normalized())
	# Racket axis is independent of the imported hand's bone coordinate system.
	racket.basis = poses[bones.hand_r].basis.inverse()*racket_basis_current
	racket.position = poses[bones.hand_r].basis.inverse()*(racket_basis_current*Vector3(-.015,.035,-.055))

var racket_basis_current = Basis.IDENTITY

static func down_basis(direction: Vector3) -> Basis:
	return Basis(Quaternion(Vector3.DOWN,direction.normalized()))

static func solve_joint(start: Vector3, finish: Vector3, pole: Vector3, upper: float, lower: float) -> Vector3:
	var vector = finish-start
	var distance = clampf(vector.length(),absf(upper-lower)+.001,upper+lower-.001)
	var axis = vector.normalized()
	var projected = pole-start-axis*(pole-start).dot(axis)
	if projected.length()<.001: projected = axis.cross(Vector3.RIGHT)
	if projected.length()<.001: projected = axis.cross(Vector3.UP)
	var along = (upper*upper-lower*lower+distance*distance)/(2*distance)
	var height = sqrt(maxf(0,upper*upper-along*along))
	return start+axis*along+projected.normalized()*height

func limb(first: String, second: String, last: String, start: Vector3, target: Vector3, pole: Vector3, length_a: float, length_b: float, end_basis: Basis) -> Vector3:
	var direction = target-start
	if direction.length()<.0001: direction = Vector3.DOWN
	var end = start+direction.normalized()*clampf(direction.length(),absf(length_a-length_b)+.001,length_a+length_b-.001)
	var joint = solve_joint(start,end,pole,length_a,length_b)
	var upper_direction = (joint-start).normalized()
	var lower_direction = (end-joint).normalized()
	if first.begins_with("upperarm_"):
		# The authored T-pose has elbows pointing back (+Z), with flexion
		# toward the thumb side (-Z). Use ONE hinge plane for both segments.
		# Independent shortest-arc rotations can turn an elbow inside out.
		var handedness = 1.0 if first.ends_with("_r") else -1.0
		var hinge = upper_direction.cross(lower_direction).normalized()*handedness
		var upper_x = upper_direction*handedness
		var lower_x = lower_direction*handedness
		pose(first,start,Basis(upper_x,hinge,upper_x.cross(hinge)).orthonormalized())
		pose(second,joint,Basis(lower_x,hinge,lower_x.cross(hinge)).orthonormalized())
	else:
		pose(first,start,Basis(Quaternion((rest_at(second)-rest_at(first)).normalized(),upper_direction)))
		pose(second,joint,Basis(Quaternion((rest_at(last)-rest_at(second)).normalized(),lower_direction)))
	pose(last,end,end_basis)
	joint_points[first] = start
	joint_points[second] = joint
	joint_points[last] = end
	return end

static func lerp_vector(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b,smoothstep(0,1,clampf(t,0,1)))

static var measurements: Dictionary = {}
static func measured(avatar: String, bone_name: String) -> Vector3:
	if not measurements.has(avatar):
		measurements[avatar] = JSON.parse_string(FileAccess.get_file_as_string("res://assets/athletes/"+avatar+"-rig.json"))
	var a: Array = measurements[avatar][bone_name].head
	return Vector3(a[0],a[1],a[2])

static func body_frame(p: Dictionary, index: int) -> Dictionary:
	var avatar = str(p.get("avatar","male"))
	var base = Basis(Vector3.UP,0 if index==0 else PI)
	var side = 1.0 if index==0 else -1.0
	var lunge = float(p.get("lunge",0))
	var receiving = float(p.get("receive_ready",0))
	var serving = float(p.get("service_ready",0))
	var lean = -.075*receiving
	var turn = -side*float(p.get("body_turn",0))
	var hip_turn = -side*float(p.get("hip_turn",0))
	var left_foot: Vector2 = p.get("foot_l",p.pos+Vector2(-.16,0)) if index==0 else p.get("foot_r",p.pos+Vector2(.16,0))
	var right_foot: Vector2 = p.get("foot_r",p.pos+Vector2(.16,0)) if index==0 else p.get("foot_l",p.pos+Vector2(-.16,0))
	var lf = base.inverse()*Vector3(left_foot.x-p.pos.x,.09+float(p.get("lift_l" if index==0 else "lift_r",0)),left_foot.y-p.pos.y)
	var rf = base.inverse()*Vector3(right_foot.x-p.pos.x,.09+float(p.get("lift_r" if index==0 else "lift_l",0)),right_foot.y-p.pos.y)
	var rescue = float(p.get("rescue_weight",0))
	var crouch = lunge*.11+rescue*.075+sin(clampf(float(p.get("split",0))/.18,0,1)*PI)*.035+.075*receiving+.025*serving
	var rest_pelvis = measured(avatar,"pelvis")
	var hip_height = rest_pelvis.y-crouch-.025
	var hip_basis = Basis(Vector3.UP,hip_turn)
	var foot_bases={}
	for foot_side in ["l","r"]:
		var slot=foot_side if index==0 else ("r" if foot_side=="l" else "l")
		var pitch=clampf(float(p.get("heel_"+slot,0)),0,.40)
		var yaw=Basis(Vector3.UP,hip_turn+(-.06 if foot_side=="l" else .06))
		var flex=Basis(Vector3.RIGHT,-pitch)
		var pivot=measured(avatar,"ball_"+foot_side)-measured(avatar,"foot_"+foot_side)
		# Rotate the heel about the metatarsal joint, preserving its floor anchor.
		var correction=yaw*(pivot-flex*pivot)
		if foot_side=="l":lf+=correction
		else:rf+=correction
		foot_bases[foot_side]=yaw*flex
		foot_bases["toe_"+foot_side]=yaw
	hip_height+=float(p.get("bounce",0))-.018*smoothstep(.35,1.5,p.vel.length())
	var chest_basis = Basis(Vector3.UP,turn)*Basis(Vector3.RIGHT,lean)
	# Small, supported weight transfer: load the racket-side leg in preparation,
	# then settle over the anatomical left leg. Feet remain the support anchors.
	var preparation = float(p.get("preparation",0))
	var transfer = float(p.get("weight_shift",0))
	var grounded = (1-smoothstep(.08,.20,float(p.jump)))*(1-smoothstep(.35,1.0,p.vel.length()))*(1-lunge)
	var right_load = .5+.12*preparation-.18*transfer
	var balance = lf.lerp(rf,right_load)
	balance.y = 0
	balance = balance.limit_length(.09)*maxf(preparation,transfer)*grounded
	# Receive with a little more load over the front (left) leg, not a deep lunge.
	var service_balance = lf.lerp(rf,.42 if receiving>.01 else lerpf(.56,.46,float(p.get("service_long",0))))
	service_balance.y=0
	balance = balance.lerp(service_balance.limit_length(.06),maxf(receiving,serving)*grounded)
	# Shift a few centimetres over the reaching foot instead of stretching arms.
	var rescue_direction=base.inverse()*Vector3(float(p.get("rescue_x",0)),0,float(p.get("rescue_y",0)))
	balance+=rescue_direction*.16*rescue
	for foot_side in ["l","r"]:
		var foot: Vector3 = lf if foot_side=="l" else rf
		foot.y += measured(avatar,"foot_"+foot_side).y-.09
		var hip_offset = hip_basis*(measured(avatar,"thigh_"+foot_side)-rest_pelvis)
		var horizontal = Vector2(foot.x-hip_offset.x-balance.x,foot.z-hip_offset.z-balance.z).length()
		var leg_length = measured(avatar,"thigh_"+foot_side).distance_to(measured(avatar,"calf_"+foot_side))+measured(avatar,"calf_"+foot_side).distance_to(measured(avatar,"foot_"+foot_side))-.004
		hip_height = minf(hip_height,foot.y-hip_offset.y+sqrt(maxf(.04,leg_length*leg_length-horizontal*horizontal)))
	var pelvis = Vector3(balance.x,hip_height,balance.z)
	var chest = pelvis
	var previous = "pelvis"
	for pair in [["spine_01",.3],["spine_02",.65],["spine_03",1.0]]:
		chest += Basis(Vector3.UP,lerpf(hip_turn,turn,float(pair[1])))*Basis(Vector3.RIGHT,lean*float(pair[1]))*(measured(avatar,pair[0])-measured(avatar,previous))
		previous=pair[0]
	var shoulder = chest+chest_basis*(measured(avatar,"upperarm_r")-measured(avatar,"spine_03"))
	return {"base":base,"pelvis":pelvis,"chest":chest,"shoulder":shoulder,"hip_basis":hip_basis,"chest_basis":chest_basis,"lf":lf,"rf":rf,"hip_turn":hip_turn,"turn":turn,"lean":lean,"foot_bases":foot_bases}

static func can_reach(p: Dictionary, index: int, shuttle: Vector3) -> bool:
	# Both avatars share the reachable zone; body size never grants an advantage.
	for avatar in ["male","female"]:
		var state=p.duplicate();state.avatar=avatar
		if (shuttle.x-p.pos.x)*(1 if index==0 else -1)<-.25:
			state.body_turn=preload("res://scripts/footwork.gd").backhand_turn(p,index,shuttle)
			state.hip_turn=state.body_turn*.65
			state.preparation=0.0
		var frame=body_frame(state,index)
		var origin=Vector3(p.pos.x,p.jump,p.pos.y)
		var contact: Vector3=frame.base.inverse()*(Vector3(shuttle.x,shuttle.z,shuttle.y)-origin)
		var reach=measured(avatar,"upperarm_r").distance_to(measured(avatar,"lowerarm_r"))+measured(avatar,"lowerarm_r").distance_to(measured(avatar,"hand_r"))+RACKET_CENTER+.115
		# Low returns retain room for a neutral wrist instead of a straight arm/shaft chain.
		if (shuttle.x-p.pos.x)*(1 if index==0 else -1)<-.25:reach-=(.10 if shuttle.z-float(p.jump)<1.9 else .05)
		if contact.distance_to(frame.shoulder)>reach:return false
	return true

func defensive_contact(shoulder: Vector3, contact: Vector3, chest_basis: Basis, offset: float, backhand: bool) -> Dictionary:
	# Choose the shaft and wrist together. A shaft aimed straight from shoulder
	# to shuttle forces the palm perpendicular to the forearm on low returns.
	var grip_roll=-PI/4 if backhand else 0.0
	var grip_change=Basis(Vector3.UP,grip_roll)
	var radial=(contact-shoulder).normalized()
	var tangent=chest_basis*Vector3(0,-1,0)
	tangent=(tangent-radial*tangent.dot(radial)).normalized()
	if tangent.length()<.01:tangent=radial.cross(Vector3.FORWARD).normalized()
	var cross_axis=radial.cross(tangent).normalized()
	var high=contact.y>shoulder.y+.25
	var pole=shoulder+chest_basis*(Vector3(.16,.10,-.45) if high and backhand else Vector3(.16,-.35,-.45))
	var upper=length_between("upperarm_r","lowerarm_r")
	var lower=length_between("lowerarm_r","hand_r")
	var best={"axis":radial,"hand":contact-radial*offset,"cost":INF}
	for tilt in [.20,.30,.40,.50,.65,.85]:
		for azimuth in [0.0,PI*.25,PI*.5,PI*.75,PI,PI*1.25,PI*1.5,PI*1.75]:
			var shaft=(radial*cos(tilt)+(tangent*cos(azimuth)+cross_axis*sin(azimuth))*sin(tilt)).normalized()
			var grip=Basis(Quaternion(Vector3.UP,shaft))
			var hand=contact-shaft*offset-grip*Vector3(-.015,.035,-.055)
			for iteration in range(5):
				var elbow=solve_joint(shoulder,hand,pole,upper,lower)
				var forearm=(hand-elbow).normalized()
				var fingers=(forearm-shaft*forearm.dot(shaft)).normalized()
				if fingers.length()>.01:grip=Basis(shaft.cross(-fingers),shaft,-fingers).orthonormalized()*grip_change.inverse()
				hand=contact-shaft*offset-grip*Vector3(-.015,.035,-.055)
			var distance=hand.distance_to(shoulder)
			if distance>upper+lower-.001 or distance<absf(upper-lower)+.005:continue
			var elbow=solve_joint(shoulder,hand,pole,upper,lower)
			var forearm=(hand-elbow).normalized()
			var local_elbow=chest_basis.inverse()*(elbow-shoulder)
			var hinge=(elbow-shoulder).normalized().cross(forearm).normalized()
			var hand_frame=grip*grip_change
			var palm_up=hand_frame.x-forearm*hand_frame.x.dot(forearm)
			var twist=absf(hinge.signed_angle_to(palm_up.normalized(),forearm))
			var cost=(1-forearm.dot(-hand_frame.z))*12+(0.0 if backhand else maxf(0,twist-1.3)*2)+maxf(0,local_elbow.z+.03)*3+maxf(0,local_elbow.y-(.25 if high else 0.0))*2+maxf(0,-.05-local_elbow.x)*4
			if cost<float(best.cost):best={"axis":shaft,"hand":hand,"cost":cost}
	return best

func animate(p: Dictionary, index: int, shuttle: Vector3, time: float, serving: bool = false) -> void:
	if gender!=str(p.avatar) or team!=index: build(str(p.avatar),index)
	position = Vector3(p.pos.x,p.jump,p.pos.y)
	rotation.y = 0 if index==0 else PI
	desired.clear()
	var frame = body_frame(p,index)
	var base: Basis = frame.base
	var pelvis: Vector3 = frame.pelvis
	var chest: Vector3 = frame.chest
	var hip_basis: Basis = frame.hip_basis
	var chest_basis: Basis = frame.chest_basis
	var lf: Vector3 = frame.lf
	var rf: Vector3 = frame.rf
	var hip_turn: float = frame.hip_turn
	var turn: float = frame.turn
	var prep = float(p.get("preparation",0))
	var t = clampf(1-p.swing/.48,0,1)
	var hit = p.swing>0 and p.has("contact")
	var contact = Vector3.ZERO
	var contact_axis = Vector3.UP
	var contact_hand = Vector3.ZERO
	var contact_offset = RACKET_CENTER
	if hit:
		var raw: Vector3 = p.contact
		contact = base.inverse()*(Vector3(raw.x,raw.z,raw.y)-position)
		var shoulder: Vector3 = frame.shoulder
		var delta = contact-shoulder
		contact_axis = (contact-shoulder).normalized()
		if str(p.get("stroke",""))=="serve":
			contact_axis = Vector3(-.88,-.22,-.42).normalized() if int(p.shot)==1 else Vector3(.15,-.45,-.88).normalized()
		if absf(contact.distance_to(shoulder)-RACKET_CENTER)<.07:
			# A close body shot needs a tilted racket, not a fully folded zero-length arm.
			var tilt_axis = contact_axis.cross(Vector3.UP)
			if tilt_axis.length()<.01: tilt_axis = Vector3.RIGHT
			contact_axis = contact_axis.rotated(tilt_axis.normalized(),.24)
		contact_offset = clampf(delta.length()-length_between("upperarm_r","lowerarm_r")-length_between("lowerarm_r","hand_r")+.004,RACKET_CENTER,RACKET_CENTER+.12)
		contact_hand = contact-contact_axis*contact_offset-Basis(Quaternion(Vector3.UP,contact_axis))*Vector3(-.015,.035,-.055)
		if str(p.get("stroke","")) in ["net","lift","drive"] or (bool(p.get("backhand",false)) and str(p.get("stroke",""))=="overhead"):
			var defensive=defensive_contact(shoulder,contact,chest_basis,contact_offset,bool(p.get("backhand",false)))
			contact_axis=defensive.axis;contact_hand=defensive.hand
	pose("pelvis",pelvis,hip_basis)
	var previous = "pelvis"
	var at = pelvis
	var torso_basis = hip_basis
	for pair in [["spine_01",.3],["spine_02",.65],["spine_03",1.0],["neck_01",1.0],["Head",1.0]]:
		var name_: String = pair[0]
		torso_basis = Basis(Vector3.UP,lerpf(hip_turn,turn,float(pair[1])))*Basis(Vector3.RIGHT,float(frame.lean)*float(pair[1]))
		at += torso_basis*(rest_at(name_)-rest_at(previous))
		pose(name_,at,torso_basis)
		if name_=="spine_03": chest=at
		previous=name_
	var local_ball = base.inverse()*(Vector3(shuttle.x,shuttle.z,shuttle.y)-position)
	if bones.has("ponytail"):
		var head: Transform3D = desired[bones.Head]
		var tail_at = head*rests[bones.Head].affine_inverse()*rest_at("ponytail")
		var head_rotation = head.basis*rests[bones.Head].basis.inverse()
		pose("ponytail",tail_at,head_rotation*Basis.from_euler(Vector3(sin(time*5)*.025+clampf(p.vel.y*.015,-.08,.08),0,clampf(p.vel.x*.02,-.10,.10))))
	for foot_side in ["l","r"]:
		var sign_x = -1.0 if foot_side=="l" else 1.0
		var start = pelvis+hip_basis*(rest_at("thigh_"+foot_side)-rest_at("pelvis"))
		var target = lf if foot_side=="l" else rf
		target.y += rest_at("foot_"+foot_side).y-.09
		var ankle=limb("thigh_"+foot_side,"calf_"+foot_side,"foot_"+foot_side,start,target,start+hip_basis*Vector3(sign_x*.08,-.2,-1),length_between("thigh_"+foot_side,"calf_"+foot_side),length_between("calf_"+foot_side,"foot_"+foot_side),frame.foot_bases[foot_side])
		pose("ball_"+foot_side,ankle+frame.foot_bases[foot_side]*(rest_at("ball_"+foot_side)-rest_at("foot_"+foot_side)),frame.foot_bases["toe_"+foot_side])
	var height_adjust = chest.y-1.33
	var ready_hand = Vector3(.28,1.18+height_adjust,-.26)
	var ready_axis = Vector3(.10,.85,-.40).normalized()
	# Preparation holds the head above the hand; racket drop belongs to the stroke,
	# not the waiting pose. Keep the raised elbow and hand in the shoulder plane.
	var hand = ready_hand
	var axis = ready_axis.slerp(Vector3(.10,.96,.20).normalized(),prep)
	var free_hand = lerp_vector(Vector3(-.28,1.17+height_adjust,-.20),Vector3(-.23,1.76+height_adjust,-.34),prep)
	var receive = float(p.get("receive_ready",0))
	hand = hand.lerp(Vector3(.25,1.26+height_adjust,-.37),receive)
	axis = axis.slerp(Vector3(.05,.98,.12).normalized(),receive)
	free_hand = free_hand.lerp(Vector3(-.30,1.12+height_adjust,-.19),receive)
	if serving:
		var high = float(p.get("service_long",0))
		free_hand = local_ball+Vector3(0,.085,.025)
		var short_axis = Vector3(-.88,-.22,-.42).normalized()
		var short_basis = Basis(Quaternion(Vector3.UP,short_axis))
		var short_hand = local_ball-short_axis*RACKET_CENTER-short_basis*Vector3(-.015,.035,-.055)
		var long_hand = Vector3(.32,.94+height_adjust,.10)
		hand = short_hand.lerp(chest+chest_basis*(long_hand-chest),high)
		axis = short_axis.slerp(chest_basis*Vector3(.15,-.25,.96).normalized(),high)
	if hit:
		var stroke: String = p.get("stroke","overhead")
		var follow_hand = Vector3(.04,1.18+height_adjust,-.34)
		var follow_axis = Vector3(-.75,-.45,-.12).normalized()
		if stroke=="net":
			follow_hand = contact_hand+Vector3(0,.025,-.06)
			follow_axis = contact_axis
		elif stroke=="serve" and int(p.shot)==1:
			follow_hand = contact_hand+Vector3(0,.035,-.10)
			follow_axis = contact_axis
		elif stroke in ["lift","serve"]:
			follow_hand = Vector3(.24,1.30+height_adjust,-.38)
			follow_axis = Vector3(.05,.72,-.65).normalized()
		elif stroke=="drive":
			follow_hand = Vector3(-.05,1.25+height_adjust,-.42)
			follow_axis = Vector3(-.55,.05,-.65).normalized()
		if p.get("backhand",false):
			if stroke=="overhead":
				follow_hand=Vector3(.20,1.20+height_adjust,-.38)
				follow_axis=Vector3(.10,.15,-.95).normalized()
			if stroke!="net":
				follow_hand=chest+chest_basis*(follow_hand-chest)
				follow_axis=chest_basis*follow_axis
			ready_hand=chest+chest_basis*(ready_hand-chest)
			ready_axis=chest_basis*ready_axis
		if t<.40:
			hand = lerp_vector(contact_hand,follow_hand,t/.40)
			axis = contact_axis.slerp(follow_axis,smoothstep(0,.40,t))
		else:
			hand = lerp_vector(follow_hand,ready_hand,(t-.40)/.60)
			axis = follow_axis.slerp(ready_axis,smoothstep(.40,1,t))
		free_hand = Vector3(-.26,1.18+height_adjust,-.19)
		if stroke=="net": free_hand = Vector3(-.40,1.12+height_adjust,.20)
	elif not serving:
		# A running athlete carries both arms with the turned torso. Keeping the
		# hands in the old net-facing plane pulls upper arms through the sleeves.
		hand = chest+chest_basis*(hand-chest)
		free_hand = chest+chest_basis*(free_hand-chest)
		axis = chest_basis*axis
	var right_shoulder = chest+chest_basis*(rest_at("upperarm_r")-rest_at("spine_03"))
	var left_shoulder = chest+chest_basis*(rest_at("upperarm_l")-rest_at("spine_03"))
	# Pole targets orient elbows through the shoulder plane, rather than rotating a flat arm.
	var arm_pole = right_shoulder+chest_basis*Vector3(.12,-.65,.02).lerp(Vector3(.40,.10,-.20),prep)
	if serving or (hit and str(p.get("stroke",""))=="serve"):
		arm_pole = right_shoulder+chest_basis*Vector3(.05,-.35,.40).lerp(Vector3(.12,-.65,.02),float(p.get("service_long",0)))
	if not hit and not serving:
		# Build a compact preparation from the actual arm lengths. The angle at
		# the elbow (shoulder -> elbow -> wrist) is 60 degrees for either avatar.
		var upper_direction = Vector3(1,-.2,0).normalized()
		var bend_direction = Vector3(0,.6,-1)
		bend_direction = (bend_direction-upper_direction*bend_direction.dot(upper_direction)).normalized()
		var lower_direction = -upper_direction*cos(PI/3)+bend_direction*sin(PI/3)
		var prepared_elbow = right_shoulder+chest_basis*upper_direction*length_between("upperarm_r","lowerarm_r")
		var prepared_hand = prepared_elbow+chest_basis*lower_direction*length_between("lowerarm_r","hand_r")
		var compact = smoothstep(0,.8,prep)*(1-receive)
		hand = hand.lerp(prepared_hand,compact)
		arm_pole = (right_shoulder+chest_basis*Vector3(.12,-.65,.02)).lerp(prepared_elbow,compact)
	if hit and str(p.stroke)=="overhead":
		# The elbow and forearm travel across the front of the shirt on follow-through.
		arm_pole = right_shoulder+chest_basis*Vector3(.28,-.16,-.10).lerp(Vector3(.35,-.35,-.30),smoothstep(0,.4,t))
		if bool(p.get("backhand",false)):
			arm_pole=right_shoulder+chest_basis*Vector3(.16,.10,-.45).lerp(Vector3(.12,-.35,-.35),smoothstep(.25,.85,t))
	var defensive_stroke = hit and str(p.get("stroke","")) in ["net","lift","drive"]
	if defensive_stroke:
		arm_pole=right_shoulder+chest_basis*Vector3(.16,-.35,-.45)
		free_hand=chest+chest_basis*(Vector3(-.34,1.10+height_adjust,.12)-chest)
	# Backhand uses a thumb grip: turn the handle within the grip, not the wrist
	# through 180 degrees. The hand frame below remains aligned with the forearm.
	var backhand_stroke=hit and bool(p.get("backhand",false)) and str(p.get("stroke",""))!="serve"
	var grip_change=Basis(Vector3.UP,-PI/4 if backhand_stroke else 0.0)
	if backhand_stroke:free_hand=chest+chest_basis*(Vector3(-.34,1.10+height_adjust,.12)-chest)
	if backhand_stroke and t>.001:
		var wrist_elbow=solve_joint(right_shoulder,hand,arm_pole,length_between("upperarm_r","lowerarm_r"),length_between("lowerarm_r","hand_r"))
		var wrist_forward=(hand-wrist_elbow).normalized()
		var parallel=clampf(axis.dot(wrist_forward),-.65,.65)
		var across=axis-wrist_forward*axis.dot(wrist_forward)
		if across.length()>.01:
			var neutral_axis=wrist_forward*parallel+across.normalized()*sqrt(1-parallel*parallel)
			axis=axis.slerp(neutral_axis,smoothstep(0,.08,t)).normalized()

	var racket_basis = Basis(Quaternion(Vector3.UP,axis.normalized()))
	var service_stroke = hit and str(p.get("stroke",""))=="serve"
	if not hit or service_stroke or defensive_stroke or backhand_stroke:
		# A shaft direction alone has no roll. The shortest UP-to-shaft rotation
		# lost the shoulder turn and left the palm twisted against the forearm.
		# Resolve the string-bed roll from the elbow-to-wrist direction instead.
		var place_shuttle = serving and float(p.get("service_long",0))<.001
		var place_contact = (service_stroke or defensive_stroke or backhand_stroke) and t<.001
		for iteration in range(8 if place_shuttle or place_contact else 1):
			var elbow = solve_joint(right_shoulder,hand,arm_pole,length_between("upperarm_r","lowerarm_r"),length_between("lowerarm_r","hand_r"))
			var forearm = (hand-elbow).normalized()
			var shaft = axis.normalized()
			var fingers = (forearm-shaft*forearm.dot(shaft)).normalized()
			if fingers.length()>.01:
				var prepared_basis = Basis(shaft.cross(-fingers),shaft,-fingers).orthonormalized()*grip_change.inverse()
				var align = 1.0 if serving or service_stroke or defensive_stroke or backhand_stroke else maxf(smoothstep(0,.65,prep),receive)
				racket_basis = Basis(racket_basis.get_rotation_quaternion().slerp(prepared_basis.get_rotation_quaternion(),align))
			if place_shuttle or place_contact:
				hand = (contact if place_contact else local_ball)-shaft*(contact_offset if place_contact else RACKET_CENTER)-racket_basis*Vector3(-.015,.035,-.055)
	# Rest fingers point +X, thumb is on -Z, palm faces -Y.
	# In a forehand grip the thumb side points toward the racket head (+Y).
	# Preserve handedness: the previous frame put the pinky above the thumb.
	var grip_basis = racket_basis*grip_change*Basis(Vector3(0,0,-1),Vector3(1,0,0),Vector3(0,-1,0))
	var hand_end = limb("upperarm_r","lowerarm_r","hand_r",right_shoulder,hand,arm_pole,length_between("upperarm_r","lowerarm_r"),length_between("lowerarm_r","hand_r"),grip_basis)
	# Forearm pronation is limited around its length; retain the elbow hinge.
	var forearm_direction: Vector3 = (hand_end-joint_points.lowerarm_r).normalized()
	var forearm_basis: Basis = desired[bones.lowerarm_r].basis*rests[bones.lowerarm_r].basis.inverse()
	var target_up = grip_basis.y-forearm_direction*grip_basis.y.dot(forearm_direction)
	if target_up.length()>.01:
		var twist = forearm_basis.y.signed_angle_to(target_up.normalized(),forearm_direction)
		var prepared = 1.0 if serving or service_stroke or defensive_stroke or backhand_stroke else (maxf(smoothstep(0,.65,prep),receive) if not hit else 0.0)
		# Let the forearm carry preparation pronation instead of leaving the
		# remaining rotation as an abrupt twist at the wrist seam.
		var applied_twist = lerpf(clampf(twist,-1.15,1.15)*.7,clampf(twist,-1.65,1.65),prepared)
		# A backhand can cross from pronation to supination. Capping this roll
		# at 95 degrees left the remaining rotation as an inverted wrist seam.
		# Rotate around the forearm's own axis; the elbow hinge stays unchanged.
		if backhand_stroke:applied_twist=twist
		pose("lowerarm_r",joint_points.lowerarm_r,Basis(forearm_direction,applied_twist)*forearm_basis)
	var free_pole = left_shoulder+chest_basis*Vector3(-.12,-.75,.15).lerp(Vector3(-.40,.05,.1),prep)
	var free_elbow = solve_joint(left_shoulder,free_hand,free_pole,length_between("upperarm_l","lowerarm_l"),length_between("lowerarm_l","hand_l"))
	limb("upperarm_l","lowerarm_l","hand_l",left_shoulder,free_hand,free_pole,length_between("upperarm_l","lowerarm_l"),length_between("lowerarm_l","hand_l"),Basis(Quaternion((rest_at("hand_l")-rest_at("lowerarm_l")).normalized(),(free_hand-free_elbow).normalized())))
	racket_basis_current = racket_basis
	apply_poses()
	racket_contact_world = position+base*(hand_end+racket_basis*Vector3(-.015,.035,-.055)+axis.normalized()*contact_offset)
	racket_center_world = position+base*(hand_end+racket_basis*Vector3(-.015,.035,-.055)+axis.normalized()*RACKET_CENTER)
	contact_error = racket_contact_world.distance_to(position+base*contact) if hit and t<.001 else 0.0

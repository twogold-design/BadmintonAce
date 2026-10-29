extends Node3D
## A real, lit 3D athlete: Skeleton3D, skinned jersey, articulated limbs and racket.
## All animation targets live in metres in the court, never in screen coordinates.

const MALE = preload("res://assets/athletes/male.glb")
const FEMALE = preload("res://assets/athletes/female.glb")
const RACKET_CENTER = .58
const HAND_GRIP = Basis(Vector3(0,0,-1),Vector3(1,0,0),Vector3(0,-1,0))
const PALM_ANCHOR = Vector3(.105,-.028,0)
## HAND_GRIP's zero roll places the palm across the string bed. A basic
## handshake/V grip brings the palm close to its plane, with a 15 degree bevel.
const FOREHAND_ROLL = -5*PI/12
const READY_HAND = Vector3(.44,.14,-.22) # Relative to the chest.
const READY_AXIS = Vector3(-.50,.85,-.15)
const READY_POLE = Vector3(.38,-.35,-.12)
const FREE_READY = Vector3(-.38,-.12,-.20)
const NET_CONTACT_TOLERANCE = .28
const NET_MIN_FLEX = PI/6 # 30 degrees away from a locked straight elbow.

static func forearm_racket_basis(shaft: Vector3, forearm: Vector3, roll: float) -> Basis:
	var along=shaft.normalized()
	var fingers=(forearm-along*forearm.dot(along)).normalized()
	return Basis(along.cross(-fingers),along,-fingers).orthonormalized()*Basis(Vector3.UP,roll).inverse()

static func service_axis(high: float) -> Vector3:
	return Vector3(-.92,-.35,-.12).lerp(Vector3(-.91,-.38,-.14),high).normalized()

func grip_mount(backhand: bool = false, ready_roll: float = FOREHAND_ROLL) -> Vector3:
	return grip_mount_for(gender if not gender.is_empty() else "male",backhand,ready_roll)

static func grip_mount_for(avatar: String, backhand: bool, ready_roll: float = FOREHAND_ROLL) -> Vector3:
	# Centre the handle inside the palm, independently of forehand/backhand roll.
	var hand_scale=measured(avatar,"hand_r").distance_to(measured(avatar,"middle_01_r"))/.1165
	return Basis(Vector3.UP,-PI/4 if backhand else ready_roll)*HAND_GRIP*(PALM_ANCHOR*hand_scale)-Vector3(0,.035,0)

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
	stroke_solution.clear()
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
			var curl = 1.10 if "_01_" in name_ else (1.20 if "_02_" in name_ else .85)
			var axis = rests[id].basis.inverse()*Vector3(0,0,-1)
			rest.basis = rest.basis*Basis(axis.normalized(),curl)
		var inherited = poses[parent]*rest if parent>=0 else rest
		poses[id] = desired.get(id,inherited)
		var local = poses[parent].affine_inverse()*poses[id] if parent>=0 else poses[id]
		skeleton.set_bone_pose_position(id,local.origin)
		skeleton.set_bone_pose_rotation(id,local.basis.get_rotation_quaternion().normalized())
	# Racket axis is independent of the imported hand's bone coordinate system.
	racket.basis = poses[bones.hand_r].basis.inverse()*racket_basis_current
	racket.position = poses[bones.hand_r].basis.inverse()*(racket_basis_current*racket_mount_current)

var racket_basis_current = Basis.IDENTITY
var racket_mount_current = Vector3.ZERO
var stroke_solution: Dictionary = {}
var stroke_contact = Vector3(INF,INF,INF)
var stroke_kind = ""
var previous_swing = 0.0
var previous_arm_twist = 0.0
var arm_twist_valid = false

static func service_contact(avatar: String, shoulder: Vector3, contact: Vector3, chest_basis: Basis, high: float) -> Dictionary:
	var shaft=service_axis(high)
	var grip=Basis(Quaternion(Vector3.UP,shaft))
	var mount=grip_mount_for(avatar,true)
	var hand=contact-shaft*RACKET_CENTER-grip*mount
	var pole=shoulder+chest_basis*Vector3(.28,-.45,-.28)
	var upper=measured(avatar,"upperarm_r").distance_to(measured(avatar,"lowerarm_r"))
	var lower=measured(avatar,"lowerarm_r").distance_to(measured(avatar,"hand_r"))
	for iteration in range(32):
		var elbow=solve_arm_joint(shoulder,hand,pole,upper,lower,chest_basis)
		var forearm=(hand-elbow).normalized()
		var fingers=(forearm-shaft*forearm.dot(shaft)).normalized()
		grip=Basis(shaft.cross(-fingers),shaft,-fingers).orthonormalized()*Basis(Vector3.UP,PI/4)
		hand=hand.lerp(contact-shaft*RACKET_CENTER-grip*mount,.55)
	return {"axis":shaft,"hand":hand,"basis":grip,"offset":RACKET_CENTER,"valid":true}

static func down_basis(direction: Vector3) -> Basis:
	return Basis(Quaternion(Vector3.DOWN,direction.normalized()))

static func overhead_release(avatar: String, start_frame: Basis, start_relative: Basis) -> Dictionary:
	var shoulder=measured(avatar,"upperarm_r")
	var upper=shoulder.distance_to(measured(avatar,"lowerarm_r"))
	var lower=measured(avatar,"lowerarm_r").distance_to(measured(avatar,"hand_r"))
	var wanted=Vector3(-.42,shoulder.y-.55,-.38)
	var best={"cost":INF}
	# Choose the arm path around a bounded pronation, not an unrelated wrist
	# orientation obtained by solving a second imaginary contact at the hip.
	for ux in [-.08,.02,.12]:
		for uy in [-.12,-.20]:
			for uz in [-.12,-.22]:
				var up=Vector3(ux,uy,uz).normalized()
				var elbow=shoulder+up*upper
				for lx in [-.9,-.6,-.3]:
					for ly in [-.9,-.5,-.1]:
						for lz in [-.8,-.4,-.1]:
							var down=Vector3(lx,ly,lz).normalized()
							var flex=acos(clampf(up.dot(down),-1,1))
							if flex<.25 or flex>2.1:continue
							var hinge=up.cross(down).normalized()
							var upper_frame=Basis(up,hinge,up.cross(hinge)).orthonormalized()
							var lower_frame=Basis(down,hinge,down.cross(hinge)).orthonormalized()
							for pronation in [-.25,-.40,-.55]:
								var relative=Basis(Vector3.RIGHT,pronation)*start_relative
								var grip=lower_frame*relative*HAND_GRIP.inverse()*Basis(Vector3.UP,FOREHAND_ROLL).inverse()
								var hand=elbow+down*lower
								var center=hand+grip*(grip_mount_for(avatar,false)+Vector3(0,RACKET_CENTER,0))
								var cost=center.distance_squared_to(wanted)*12
								cost+=maxf(0,center.x+.28)*500+maxf(0,center.y-(shoulder.y-.48))*500
								cost+=maxf(0,grip.y.x+.15)*200+maxf(0,grip.y.y+.15)*200+maxf(0,center.z+.12)*100
								cost+=start_frame.get_rotation_quaternion().angle_to(upper_frame.get_rotation_quaternion())*.12
								if cost<float(best.cost):best={"cost":cost,"upper_frame":upper_frame,"flex":flex,"relative":relative}
	return best

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

static func solve_arm_joint(start: Vector3, finish: Vector3, pole: Vector3, upper: float, lower: float, chest_basis: Basis, side: float = 1.0) -> Vector3:
	# Intersect the elbow's fixed-length IK circle with the shoulder plane.
	# The outward branch keeps low-stroke elbows from switching across ribs.
	var joint=solve_joint(start,finish,pole,upper,lower)
	var normal=chest_basis.z
	if normal.dot(joint-start)<=.035:return joint
	var axis=(finish-start).normalized()
	var distance=clampf(start.distance_to(finish),absf(upper-lower)+.001,upper+lower-.001)
	var along=(upper*upper-lower*lower+distance*distance)/(2*distance)
	var center=start+axis*along
	var radius=sqrt(maxf(0,upper*upper-along*along))
	var planar=normal-axis*normal.dot(axis)
	if radius<.0001 or planar.length()<.0001:return joint
	var u=planar.normalized()
	var v=axis.cross(u).normalized()
	var x=clampf((.035-normal.dot(center-start))/(radius*planar.length()),-1,1)
	var y=sqrt(maxf(0,1-x*x))
	var a=center+radius*(u*x+v*y)
	var b=center+radius*(u*x-v*y)
	# Keep the nearest point on the same elbow circle. Choosing a new branch
	# solely by lateral position flips low elbows while the torso lowers.
	return a if joint.distance_squared_to(a)<joint.distance_squared_to(b) else b

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
	var lean = -.20*receiving-.04*serving
	if float(p.get("swing",0))>0 and str(p.get("stroke",""))=="overhead" and not bool(p.get("backhand",false)):
		var follow=clampf(1-float(p.swing)/.48,0,1)
		# A small chest-led follow-through accompanies axial shoulder rotation.
		# Zero at impact and recovery; never stretch the shoulder away from its rig.
		lean-=.065*smoothstep(.02,.25,follow)*(1-smoothstep(.55,1,follow))
	var turn = -side*float(p.get("body_turn",0))
	var hip_turn = -side*float(p.get("hip_turn",0))
	var left_foot: Vector2 = p.get("foot_l",p.pos+Vector2(-.16,0)) if index==0 else p.get("foot_r",p.pos+Vector2(.16,0))
	var right_foot: Vector2 = p.get("foot_r",p.pos+Vector2(.16,0)) if index==0 else p.get("foot_l",p.pos+Vector2(-.16,0))
	var lf = base.inverse()*Vector3(left_foot.x-p.pos.x,.09+float(p.get("lift_l" if index==0 else "lift_r",0)),left_foot.y-p.pos.y)
	var rf = base.inverse()*Vector3(right_foot.x-p.pos.x,.09+float(p.get("lift_r" if index==0 else "lift_l",0)),right_foot.y-p.pos.y)
	var rescue = float(p.get("rescue_weight",0))
	var crouch = lunge*.11+rescue*.075+sin(clampf(float(p.get("split",0))/.18,0,1)*PI)*.035+.075*receiving+.025*serving
	# Relaxed athletic stance: knees absorb movement and landing, while the
	# short jump countermovement loads the legs before the feet leave ground.
	var on_ground=1-smoothstep(.02,.18,float(p.jump))
	var athletic=(1-maxf(receiving,serving))*on_ground*(1-clampf(float(p.get("preparation",0)),0,1))
	var reach_up=float(p.get("reach_up",0))
	if float(p.get("swing",0))>0 and p.has("contact") and p.contact.z-float(p.jump)>1.9:
		reach_up=1-smoothstep(.10,.55,1-float(p.swing)/.48)
	athletic*=1-reach_up
	# An athletic ready stance stays hinged forward even at zero speed.
	# Carry part of the pitch through the hips, not just a bend in the spine.
	var stance_lean=-.19*athletic
	var air_weight=1-on_ground
	var air_lean=-.10*air_weight
	lean+=stance_lean+air_lean
	# Approach the net with a small whole-torso pitch and a forward pelvis load.
	# Derive it from the shared velocity in player space, so P2 leans toward its
	# own net. Fade into braking/lunging and high contact instead of bowing there.
	var forward_speed=maxf(0,-p.vel.y*side)
	var forward_weight=smoothstep(.2,4.5,forward_speed)*smoothstep(0,.6,forward_speed/maxf(.01,p.vel.length()))
	forward_weight*=athletic*(1-.85*lunge)*(1-.75*rescue)*(1-float(p.get("jump_crouch",0)))
	var run_lean=-.13*forward_weight
	var hip_lean=stance_lean*.45+run_lean*.60+air_lean*.45-.07*receiving
	lean+=run_lean
	crouch+=(.065+.022*smoothstep(.3,3.5,p.vel.length()))*athletic
	crouch+=.12*float(p.get("jump_crouch",0))
	crouch+=.065*sin(PI*clampf(float(p.get("landing",0))/.18,0,1))*on_ground
	var rest_pelvis = measured(avatar,"pelvis")
	var hip_height = rest_pelvis.y-crouch-.025
	var hip_basis = Basis(Vector3.UP,hip_turn)*Basis(Vector3.RIGHT,hip_lean)
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
	var service_balance = lf.lerp(rf,.42 if receiving>.01 else .56)
	service_balance.y=0
	balance = balance.lerp(service_balance.limit_length(.06),maxf(receiving,serving)*grounded)
	# Shift a few centimetres over the reaching foot instead of stretching arms.
	var rescue_direction=base.inverse()*Vector3(float(p.get("rescue_x",0)),0,float(p.get("rescue_y",0)))
	balance+=rescue_direction*.16*rescue
	balance+=Basis(Vector3.UP,turn)*Vector3(0,0,-.055*forward_weight)
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
		chest += Basis(Vector3.UP,lerpf(hip_turn,turn,float(pair[1])))*Basis(Vector3.RIGHT,lerpf(hip_lean,lean,float(pair[1])))*(measured(avatar,pair[0])-measured(avatar,previous))
		previous=pair[0]
	var shoulder = chest+chest_basis*(measured(avatar,"upperarm_r")-measured(avatar,"spine_03"))
	return {"base":base,"pelvis":pelvis,"chest":chest,"shoulder":shoulder,"hip_basis":hip_basis,"chest_basis":chest_basis,"lf":lf,"rf":rf,"hip_turn":hip_turn,"turn":turn,"lean":lean,"hip_lean":hip_lean,"foot_bases":foot_bases}

static func can_reach(p: Dictionary, index: int, shuttle: Vector3, stroke: String = "") -> bool:
	# Both avatars share the reachable zone; body size never grants an advantage.
	var backhand=preload("res://scripts/footwork.gd").uses_backhand(p,index,shuttle)
	var underarm=(str(p.get("stroke","")) if stroke.is_empty() else stroke) in ["net","lift"]
	for avatar in ["male","female"]:
		var state=p.duplicate();state.avatar=avatar
		state.reach_up=1.0 if shuttle.z-float(p.jump)>1.9 else 0.0
		if underarm:
			state.body_turn=preload("res://scripts/footwork.gd").underarm_turn(p,index,shuttle,backhand)
			state.hip_turn=state.body_turn*.65
			state.preparation=0.0
		elif backhand:
			state.body_turn=preload("res://scripts/footwork.gd").backhand_turn(p,index,shuttle)
			state.hip_turn=state.body_turn*.65
			state.preparation=0.0
		var frame=body_frame(state,index)
		var origin=Vector3(p.pos.x,p.jump,p.pos.y)
		var contact: Vector3=frame.base.inverse()*(Vector3(shuttle.x,shuttle.z,shuttle.y)-origin)
		var reach=measured(avatar,"upperarm_r").distance_to(measured(avatar,"lowerarm_r"))+measured(avatar,"lowerarm_r").distance_to(measured(avatar,"hand_r"))+RACKET_CENTER+.115
		# Low returns retain room for a neutral wrist instead of a straight arm/shaft chain.
		if backhand:
			var upper=measured(avatar,"upperarm_r").distance_to(measured(avatar,"lowerarm_r"))
			var lower=measured(avatar,"lowerarm_r").distance_to(measured(avatar,"hand_r"))
			var scale=measured(avatar,"hand_r").distance_to(measured(avatar,"middle_01_r"))/.1165
			var offset=RACKET_CENTER+.12
			# Reach includes the actual palm anchor and a bounded wrist bend.
			var along=lower*cos(deg_to_rad(50))+PALM_ANCHOR.x*scale
			var across=lower*sin(deg_to_rad(50))+offset-.035
			reach=minf(reach,upper+sqrt(along*along+across*across)-.025)
		if contact.distance_to(frame.shoulder)>reach+(NET_CONTACT_TOLERANCE if underarm else 0.0):return false
		var upper_length=measured(avatar,"upperarm_r").distance_to(measured(avatar,"lowerarm_r"))
		var lower_length=measured(avatar,"lowerarm_r").distance_to(measured(avatar,"hand_r"))
		var offset=clampf(contact.distance_to(frame.shoulder)-upper_length-lower_length+.004,RACKET_CENTER,RACKET_CENTER+.12)
		if not defensive_contact(avatar,frame.shoulder,contact,frame.chest_basis,offset,backhand,shuttle.z-float(p.jump)>1.9,underarm).valid:return false

	return true

static func underarm_contact(avatar: String, shoulder: Vector3, contact: Vector3, chest_basis: Basis, offset: float, backhand: bool) -> Dictionary:
	var best=underarm_contact_exact(avatar,shoulder,contact,chest_basis,offset,backhand)
	if best.valid:return best
	# A close body return may miss the exact shuttle centre by a small amount.
	# Prefer a relaxed wrist/elbow to a tightly folded arm or a large body turn.
	for shift in [Vector3(0,0,-.26),Vector3(.18,0,0),Vector3(-.18,0,0),Vector3(0,0,.20),Vector3(.14,0,-.16),Vector3(-.14,0,-.16),Vector3(0,.16,-.10),Vector3(0,-.16,-.10)]:
		var candidate=underarm_contact_exact(avatar,shoulder,contact+chest_basis*shift,chest_basis,offset,backhand)
		candidate.cost+=shift.length()*45
		if candidate.valid:return candidate
	return best

static func underarm_contact_exact(avatar: String, shoulder: Vector3, contact: Vector3, chest_basis: Basis, offset: float, backhand: bool) -> Dictionary:
	var upper=measured(avatar,"upperarm_r").distance_to(measured(avatar,"lowerarm_r"))
	var lower=measured(avatar,"lowerarm_r").distance_to(measured(avatar,"hand_r"))
	var change=Basis(Vector3.UP,-PI/4 if backhand else FOREHAND_ROLL)
	var radial=(contact-shoulder).normalized()
	var tangent=radial.cross(chest_basis.x).normalized()
	if tangent.length()<.01:tangent=radial.cross(Vector3.UP).normalized()
	var across=radial.cross(tangent).normalized()
	var wanted=Vector3.DOWN if backhand else Vector3.UP
	var best={"axis":radial,"hand":contact-radial*offset,"cost":INF,"basis":Basis(Quaternion(Vector3.UP,radial)),"valid":false,"offset":offset}
	var chest=shoulder-chest_basis*(measured(avatar,"upperarm_r")-measured(avatar,"spine_03"))
	var contact_side=(chest_basis.inverse()*(contact-chest)).x
	if (not backhand and contact_side<.10) or (backhand and contact_side>-.10):return best
	var compact=(chest_basis.inverse()*(contact-shoulder)).z>-.45 or contact.y>shoulder.y+.05
	for tilt in [.10,.25,.40,.55,.70,.85,1.0,1.15,1.30,1.45,1.60,1.80,2.0,2.2]:
		for i in range(24):
			var angle=TAU*i/24.0
			var shaft=(radial*cos(tilt)+(tangent*cos(angle)+across*sin(angle))*sin(tilt)).normalized()
			var palm=wanted-shaft*wanted.dot(shaft)
			if palm.length()<.55:continue
			palm=palm.normalized()
			for roll in [-.3,0.0,.3]:
				var y=-palm.rotated(shaft,roll)
				var hand_frame=Basis(y.cross(-shaft),y,-shaft).orthonormalized()
				var grip=hand_frame*HAND_GRIP.inverse()*change.inverse()
				var hand=contact-shaft*offset-grip*grip_mount_for(avatar,backhand)
				var distance=shoulder.distance_to(hand)
				var relaxed_reach=sqrt(upper*upper+lower*lower+2*upper*lower*cos(NET_MIN_FLEX))
				if distance>relaxed_reach or distance<(.27 if backhand or compact else .34):continue
				var local_hand=chest_basis.inverse()*(hand-shoulder)
				if local_hand.z>(.035 if backhand else (-.10 if compact else -.20)):continue
				var first_elbow=solve_arm_joint(shoulder,hand,hand-hand_frame.x*lower,upper,lower,chest_basis)
				var arm_axis=(hand-shoulder).normalized()
				var center=shoulder+arm_axis*(upper*upper-lower*lower+distance*distance)/(2*distance)
				for swivel in [-.7,0.0,.7]:
					var elbow=center+(first_elbow-center).rotated(arm_axis,swivel)
					if chest_basis.z.dot(elbow-shoulder)>.0351:continue
					var forearm=(hand-elbow).normalized()
					var wrist=hand_frame.x.dot(forearm)
					if wrist<cos(deg_to_rad(38)):continue
					var hinge=(elbow-shoulder).normalized().cross(forearm).normalized()
					var up=(hand_frame.y-forearm*hand_frame.y.dot(forearm)).normalized()
					var twist=absf(hinge.signed_angle_to(up,forearm))
					if twist>1.4:continue
					var cost=(1-wrist)*80+maxf(0,twist-1.4)*40+maxf(0,local_hand.z+.15)*30+maxf(0,.3-distance)*20+absf(roll)*2
					if contact.y<shoulder.y+.1:cost+=maxf(0,local_hand.y+.15)*80
					cost+=maxf(0,hand.y-maxf(contact.y+.18,shoulder.y-.40))*240
					if cost<float(best.cost):best={"axis":shaft,"hand":hand,"elbow":elbow,"basis":grip,"offset":offset,"cost":cost,"valid":true}

	if not best.valid and offset<RACKET_CENTER+.119:return underarm_contact_exact(avatar,shoulder,contact,chest_basis,minf(offset+.04,RACKET_CENTER+.12),backhand)
	return best

static func defensive_contact(avatar: String, shoulder: Vector3, contact: Vector3, chest_basis: Basis, offset: float, backhand: bool, overhead: bool = false, underarm: bool = false) -> Dictionary:
	if underarm:return underarm_contact(avatar,shoulder,contact,chest_basis,offset,backhand)
	# Choose the shaft and wrist together. A shaft aimed straight from shoulder
	# to shuttle forces the palm perpendicular to the forearm on low returns.
	var grip_roll=-PI/4 if backhand else FOREHAND_ROLL
	var grip_change=Basis(Vector3.UP,grip_roll)
	var radial=(contact-shoulder).normalized()
	var tangent=chest_basis*Vector3(0,-1,0)
	tangent=(tangent-radial*tangent.dot(radial)).normalized()
	if tangent.length()<.01:tangent=radial.cross(Vector3.FORWARD).normalized()
	var cross_axis=radial.cross(tangent).normalized()
	var high=contact.y>shoulder.y+.25
	var pole=shoulder+chest_basis*(Vector3(.16,.10,-.45) if high and backhand else Vector3(.12,-.65,-.08))
	if high and backhand and contact.x<-.6:pole=shoulder+chest_basis*Vector3(-.20,.05,.15)
	if overhead and not backhand:pole=shoulder+chest_basis*Vector3(.40,.12,-.12)
	var upper=measured(avatar,"upperarm_r").distance_to(measured(avatar,"lowerarm_r"))
	var lower=measured(avatar,"lowerarm_r").distance_to(measured(avatar,"hand_r"))
	var best={"axis":radial,"hand":contact-radial*offset,"cost":INF,"basis":Basis(Quaternion(Vector3.UP,radial)),"valid":false,"offset":offset}
	var tilts=[.10,.20,.30,.40,.50,.65,.85,1.05,1.2,1.4,1.6] if high else [.10,.20,.30,.40,.50,.65,.85,1.05,1.2,1.4,1.6,1.8,2.0,2.2]
	if overhead:tilts=[.10,.20,.30,.40,.50,.60,.70,.80,.90,1.0,1.10,1.20,1.30,1.40,1.50,1.60]
	var azimuths=[]
	for i in range(24 if overhead else 8):azimuths.append(TAU*i/(24.0 if overhead else 8.0))
	for tilt in tilts:
		for azimuth in azimuths:
			var shaft=(radial*cos(tilt)+(tangent*cos(azimuth)+cross_axis*sin(azimuth))*sin(tilt)).normalized()
			var grip=Basis(Quaternion(Vector3.UP,shaft))
			var hand=contact-shaft*offset-grip*grip_mount_for(avatar,backhand)
			for iteration in range(10):
				var elbow=solve_arm_joint(shoulder,hand,pole,upper,lower,chest_basis)
				var forearm=(hand-elbow).normalized()
				var fingers=(forearm-shaft*forearm.dot(shaft)).normalized()
				if fingers.length()>.01:grip=Basis(shaft.cross(-fingers),shaft,-fingers).orthonormalized()*grip_change.inverse()
				hand=hand.lerp(contact-shaft*offset-grip*grip_mount_for(avatar,backhand),.55)
			var residual=hand+grip*grip_mount_for(avatar,backhand)+shaft*offset-contact
			if residual.length()>.001:continue
			var distance=hand.distance_to(shoulder)
			if distance>upper+lower-.001 or distance<absf(upper-lower)+.005:continue
			var elbow=solve_arm_joint(shoulder,hand,pole,upper,lower,chest_basis)
			var forearm=(hand-elbow).normalized()
			var local_elbow=chest_basis.inverse()*(elbow-shoulder)
			var local_hand=chest_basis.inverse()*(hand-shoulder)
			# A folded hand beside the shoulder may reach the shuttle on paper,
			# but makes low returns flip their elbow as the player crouches.
			var posture_cost=0.0
			if not high:
				posture_cost=maxf(0,.23-distance)*100+maxf(0,local_hand.z+.10)*100+maxf(0,local_hand.y+.15)*100+maxf(0,local_elbow.y+.035)*100+maxf(0,.04-local_elbow.x)*100
			var hinge=(elbow-shoulder).normalized().cross(forearm).normalized()
			if overhead and not backhand:
				# Keep the contact elbow on the same raised, outward branch as
				# the V-grip preparation, rather than choosing a lower-cost fold
				# that rolls the upper arm almost half a turn on the impact frame.
				var local_upper=local_elbow.normalized()
				var preferred_upper=Vector3(1,-.2,0).normalized()
				var preferred_lower=Vector3(-.5,.51,-.85).normalized()
				var preferred_hinge=preferred_upper.cross(preferred_lower).normalized()
				var local_hinge=chest_basis.inverse()*hinge
				var transported_hinge=Basis(Quaternion(preferred_upper,local_upper))*preferred_hinge
				if transported_hinge.dot(local_hinge)<cos(deg_to_rad(60)):continue
				posture_cost+=maxf(0,.02-local_elbow.x)*160
				posture_cost+=(1-local_hinge.dot(transported_hinge))*35
				posture_cost+=(1-local_upper.dot(preferred_upper))*8
			var hand_frame=grip*grip_change
			var palm_up=hand_frame.x-forearm*hand_frame.x.dot(forearm)
			var twist=absf(hinge.signed_angle_to(palm_up.normalized(),forearm))
			if not high and not backhand:posture_cost+=maxf(0,twist-1.65)*12
			if backhand and (twist>1.8 or forearm.dot(-hand_frame.z)<cos(deg_to_rad(50)) or (high and hand_frame.x.z>-.1)):continue
			var cost=(1-forearm.dot(-hand_frame.z))*12+maxf(0,twist-1.3)*(8 if backhand else 2)+maxf(0,local_elbow.z+.03)*3+maxf(0,local_elbow.y-(.25 if high else 0.0))*2+maxf(0,-.05-local_elbow.x)*4
			cost+=posture_cost
			if not backhand:cost+=maxf(0,cos(deg_to_rad(48))-forearm.dot(-hand_frame.z))*(2000 if overhead else 100)
			if backhand and high:
				# Rearcourt backhands strike with the back of the hand towards the net.
				# Wrist alignment alone also admits the opposite (forehand) palm face.
				cost+=maxf(0,hand_frame.x.z+.25)*30+(1-absf(grip.z.z))*4
			if cost<float(best.cost):best={"axis":shaft,"hand":hand,"elbow":elbow,"cost":cost,"basis":grip,"valid":true,"offset":offset,"wrist_dot":forearm.dot(-hand_frame.z)}
	# A tilted shaft can use the outer string bed without stretching the arm.
	if not best.valid and offset<RACKET_CENTER+.119:
		return defensive_contact(avatar,shoulder,contact,chest_basis,minf(offset+.04,RACKET_CENTER+.12),backhand,overhead,underarm)
	if overhead and not backhand and best.valid and float(best.wrist_dot)<cos(deg_to_rad(50)) and offset<RACKET_CENTER+.139:
		var outer=defensive_contact(avatar,shoulder,contact,chest_basis,minf(offset+.02,RACKET_CENTER+.14),backhand,overhead,underarm)
		if outer.valid and float(outer.cost)<float(best.cost):return outer
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
	if not hit:stroke_solution.clear()
	var contact = Vector3.ZERO
	var contact_axis = Vector3.UP
	var contact_hand = Vector3.ZERO
	var contact_offset = RACKET_CENTER
	var contact_grip=Basis.IDENTITY
	var solved_contact=false
	if hit:
		var raw: Vector3 = p.contact
		contact = base.inverse()*(Vector3(raw.x,raw.z,raw.y)-position)
		var shoulder: Vector3 = frame.shoulder
		var delta = contact-shoulder
		contact_axis = (contact-shoulder).normalized()
		if str(p.get("stroke",""))=="serve":
			contact_axis = service_axis(0.0 if int(p.shot)==1 else 1.0)
		if absf(contact.distance_to(shoulder)-RACKET_CENTER)<.07:
			# A close body shot needs a tilted racket, not a fully folded zero-length arm.
			var tilt_axis = contact_axis.cross(Vector3.UP)
			if tilt_axis.length()<.01: tilt_axis = Vector3.RIGHT
			contact_axis = contact_axis.rotated(tilt_axis.normalized(),.24)
		contact_offset = clampf(delta.length()-length_between("upperarm_r","lowerarm_r")-length_between("lowerarm_r","hand_r")+.004,RACKET_CENTER,RACKET_CENTER+.12)
		contact_hand = contact-contact_axis*contact_offset-Basis(Quaternion(Vector3.UP,contact_axis))*grip_mount(bool(p.get("backhand",false)) or str(p.get("stroke",""))=="serve")
		var kind=str(p.get("stroke",""))
		if kind in ["net","lift","drive","overhead","serve"]:
			# Choose the impact solution once. Re-running the discrete search on
			# every recovery frame could jump to the opposite elbow/shaft branch.
			if stroke_solution.is_empty() or stroke_contact!=raw or stroke_kind!=kind or float(p.swing)>previous_swing+.001 or t<.001:
				arm_twist_valid=false
				stroke_solution=service_contact(gender,shoulder,contact,chest_basis,0.0 if int(p.shot)==1 else 1.0) if kind=="serve" else defensive_contact(gender,shoulder,contact,chest_basis,contact_offset,bool(p.get("backhand",false)),kind=="overhead",kind in ["net","lift"])
				stroke_solution.hand_offset=stroke_solution.hand-contact
				stroke_contact=raw;stroke_kind=kind
			var defensive=stroke_solution
			contact_axis=defensive.axis;contact_hand=contact+defensive.hand_offset
			contact_offset=defensive.offset
			contact_grip=defensive.basis;solved_contact=defensive.valid
	previous_swing=float(p.swing)
	pose("pelvis",pelvis,hip_basis)
	var previous = "pelvis"
	var at = pelvis
	var torso_basis = hip_basis
	for pair in [["spine_01",.3],["spine_02",.65],["spine_03",1.0],["neck_01",1.0],["Head",1.0]]:
		var name_: String = pair[0]
		torso_basis = Basis(Vector3.UP,lerpf(hip_turn,turn,float(pair[1])))*Basis(Vector3.RIGHT,lerpf(float(frame.hip_lean),float(frame.lean),float(pair[1])))
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
	var ready_hand = chest+READY_HAND
	var ready_axis = READY_AXIS.normalized()
	# Preparation holds the head above the hand; racket drop belongs to the stroke,
	# not the waiting pose. Keep the raised elbow and hand in the shoulder plane.
	var hand = ready_hand
	var axis = ready_axis.slerp(Vector3(.10,.96,.20).normalized(),prep)
	var free_hand = lerp_vector(chest+FREE_READY,Vector3(-.34,1.76+height_adjust,-.34),prep)
	var receive = float(p.get("receive_ready",0))
	# Lift the forearm from a relaxed, open elbow. Carry the racket inward
	# and slightly forward, with the same basic grip as ordinary readiness.
	hand = hand.lerp(chest+READY_HAND,receive)
	axis = axis.slerp(READY_AXIS.normalized(),receive)
	free_hand = free_hand.lerp(chest+FREE_READY,receive)
	if serving:
		var high = float(p.get("service_long",0))
		free_hand = local_ball+Vector3(0,.085,.025)
		var short_axis = service_axis(high)
		var short_basis = Basis(Quaternion(Vector3.UP,short_axis))
		hand = local_ball-short_axis*RACKET_CENTER-short_basis*grip_mount(true)
		axis = short_axis
	if hit:
		var stroke: String = p.get("stroke","overhead")
		var follow_hand = Vector3(.04,1.18+height_adjust,-.34)
		var follow_axis = Vector3(-.75,-.45,-.12).normalized()
		if stroke=="net":
			follow_hand = contact_hand+Vector3(0,.025,-.06)
			follow_axis = contact_axis
		elif stroke=="serve":
			var high=0.0 if int(p.shot)==1 else 1.0
			follow_hand = contact_hand+Vector3(0,lerpf(.035,.12,high),-lerpf(.10,.20,high))
			follow_axis = contact_axis.slerp(Vector3(-.84,.08,-.54).normalized(),high)
		elif stroke=="lift":
			follow_hand = contact_hand+Vector3(0,.12,-.10)
			follow_axis = contact_axis.slerp(Vector3(0,.50,-.86).normalized(),.25)
		elif stroke=="drive":
			follow_hand = Vector3(-.05,1.25+height_adjust,-.42)
			follow_axis = Vector3(-.55,.05,-.65).normalized()
		if p.get("backhand",false) and stroke!="serve":
			if stroke=="overhead":
				follow_hand=Vector3(.20,1.20+height_adjust,-.38)
				follow_axis=Vector3(.10,.15,-.95).normalized()
			if stroke not in ["net","lift"]:
				follow_hand=chest+chest_basis*(follow_hand-chest)
				follow_axis=chest_basis*follow_axis
			ready_hand=chest+chest_basis*(ready_hand-chest)
			ready_axis=chest_basis*ready_axis
		elif stroke in ["net","lift"]:
			ready_hand=chest+chest_basis*(ready_hand-chest)
			ready_axis=chest_basis*ready_axis
		if t<.40:
			hand = lerp_vector(contact_hand,follow_hand,t/.40)
			axis = contact_axis.slerp(follow_axis,smoothstep(0,.40,t))
		else:
			hand = lerp_vector(follow_hand,ready_hand,(t-.40)/.60)
			axis = follow_axis.slerp(ready_axis,smoothstep(.40,1,t))
			if stroke in ["net","lift"]:
				# Return in front of the chest, not directly across the shoulder
				# axis where the elbow's bending plane becomes ambiguous.
				var recovery=smoothstep(.40,1,t)
				var waypoint=(follow_hand+ready_hand)*.5+chest_basis*Vector3(0,.04,-.55)
				hand=follow_hand.lerp(waypoint,recovery).lerp(waypoint.lerp(ready_hand,recovery),recovery)
		free_hand = Vector3(-.46,1.18+height_adjust,-.20)
		if stroke=="net": free_hand = Vector3(-.48,1.12+height_adjust,-.10)
		if not bool(p.get("backhand",false)):free_hand=chest+chest_basis*(free_hand-chest)
		if stroke=="serve":
			# The shuttle hand stays beside release, then opens for balance.
			free_hand=(contact+Vector3(0,.085,.025)).lerp(chest+chest_basis*FREE_READY,smoothstep(.08,.70,t))
	elif not serving:
		# A running athlete carries both arms with the turned torso. Keeping the
		# hands in the old net-facing plane pulls upper arms through the sleeves.
		hand = chest+chest_basis*(hand-chest)
		free_hand = chest+chest_basis*(free_hand-chest)
		axis = chest_basis*axis
	var right_shoulder = chest+chest_basis*(rest_at("upperarm_r")-rest_at("spine_03"))
	var left_shoulder = chest+chest_basis*(rest_at("upperarm_l")-rest_at("spine_03"))
	if hit and t>.001:
		# Resolve the wrist against the same reachable endpoint used by limb().
		# Otherwise a torso turn can shorten the arm after the wrist was aimed.
		var to_hand=hand-right_shoulder
		var upper=length_between("upperarm_r","lowerarm_r")
		var lower=length_between("lowerarm_r","hand_r")
		hand=right_shoulder+to_hand.normalized()*clampf(to_hand.length(),absf(upper-lower)+.001,upper+lower-.001)
	# Pole targets orient elbows through the shoulder plane, rather than rotating a flat arm.
	var arm_pole = right_shoulder+chest_basis*READY_POLE.lerp(Vector3(.40,.10,-.20),prep)
	if serving or (hit and str(p.get("stroke",""))=="serve"):
		arm_pole = right_shoulder+chest_basis*Vector3(.28,-.45,-.28)
		if not serving:arm_pole=arm_pole.lerp(right_shoulder+chest_basis*READY_POLE,smoothstep(.40,1,t))
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
		arm_pole = (right_shoulder+chest_basis*READY_POLE.lerp(Vector3(.38,-.35,-.12),receive)).lerp(prepared_elbow,compact)
	if hit and str(p.stroke)=="overhead":
		# The elbow and forearm travel across the front of the shirt on follow-through.
		arm_pole = right_shoulder+chest_basis*Vector3(.40,.12,-.12).lerp(Vector3(.35,-.35,-.30),smoothstep(0,.4,t))
		if bool(p.get("backhand",false)):
			arm_pole=right_shoulder+chest_basis*Vector3(.16,.10,-.45).lerp(Vector3(.12,-.35,-.35),smoothstep(.25,.85,t))
			if contact.x<-.6:arm_pole=right_shoulder+chest_basis*Vector3(-.20,.05,.15).lerp(Vector3(.12,-.35,-.35),smoothstep(.25,.85,t))
	if hit:
		arm_pole=arm_pole.lerp(right_shoulder+chest_basis*READY_POLE,smoothstep(.65,1,t))
	var defensive_stroke = hit and str(p.get("stroke","")) in ["net","lift","drive"]
	var underarm_stroke = hit and str(p.get("stroke","")) in ["net","lift"]
	var forehand_overhead = hit and str(p.get("stroke",""))=="overhead" and not bool(p.get("backhand",false))
	var service_stroke = hit and str(p.get("stroke",""))=="serve"
	var joint_stroke = (underarm_stroke or forehand_overhead or service_stroke) and solved_contact
	if defensive_stroke:
		arm_pole=right_shoulder+chest_basis*Vector3(.12,-.65,-.08).lerp(READY_POLE,smoothstep(.65,1,t))
		free_hand=chest+chest_basis*(Vector3(-.48,1.10+height_adjust,-.12)-chest)
	# Backhand uses a thumb grip: turn the handle within the grip, not the wrist
	# through 180 degrees. The hand frame below remains aligned with the forearm.
	var backhand_stroke=hit and bool(p.get("backhand",false)) and str(p.get("stroke",""))!="serve"
	var backhand_grip=backhand_stroke or serving or service_stroke
	# Waiting and receiving use the same basic forehand V grip. The forearm
	# determines the palm, rather than a world-facing flat racket plane.
	var ready_roll = FOREHAND_ROLL
	var grip_roll=-PI/4 if backhand_grip else ready_roll
	if service_stroke or backhand_stroke:grip_roll=lerpf(-PI/4,FOREHAND_ROLL,smoothstep(.65,1,t))
	var grip_change=Basis(Vector3.UP,grip_roll)
	var current_mount=grip_mount(false,grip_roll)
	if backhand_stroke:free_hand=chest+chest_basis*(Vector3(-.48,1.10+height_adjust,-.12)-chest)
	if hit and t>.001:
		var wrist_elbow=solve_arm_joint(right_shoulder,hand,arm_pole,length_between("upperarm_r","lowerarm_r"),length_between("lowerarm_r","hand_r"),chest_basis)
		var wrist_forward=(hand-wrist_elbow).normalized()
		var parallel=clampf(axis.dot(wrist_forward),-.65,.65)
		var across=axis-wrist_forward*axis.dot(wrist_forward)
		if across.length()<.01:
			across=chest_basis.x-wrist_forward*chest_basis.x.dot(wrist_forward)
			if across.length()<.01:across=chest_basis.z-wrist_forward*chest_basis.z.dot(wrist_forward)
		if across.length()>.01:
			var neutral_axis=wrist_forward*parallel+across.normalized()*sqrt(1-parallel*parallel)
			axis=axis.slerp(neutral_axis,smoothstep(0,.08,t)).normalized()

	var racket_basis = Basis(Quaternion(Vector3.UP,axis.normalized()))
	if not hit or service_stroke or defensive_stroke or backhand_stroke or solved_contact or t>.001:
		# A shaft direction alone has no roll. The shortest UP-to-shaft rotation
		# lost the shoulder turn and left the palm twisted against the forearm.
		# Resolve the string-bed roll from the elbow-to-wrist direction instead.
		var place_shuttle = serving
		var place_contact = hit and t<.001

		if place_contact and solved_contact:
			racket_basis=contact_grip;hand=contact_hand
		for iteration in range(0 if place_contact and solved_contact else (24 if place_shuttle or place_contact else 1)):
			var elbow = solve_arm_joint(right_shoulder,hand,arm_pole,length_between("upperarm_r","lowerarm_r"),length_between("lowerarm_r","hand_r"),chest_basis)
			var forearm = (hand-elbow).normalized()
			var shaft = axis.normalized()
			var fingers = (forearm-shaft*forearm.dot(shaft)).normalized()
			if fingers.length()>.01:
				racket_basis = forearm_racket_basis(shaft,forearm,grip_roll)
			if place_shuttle or place_contact:
				hand = hand.lerp((contact if place_contact else local_ball)-shaft*(contact_offset if place_contact else RACKET_CENTER)-racket_basis*current_mount,.55)
	if joint_stroke and solved_contact:
		var upper_length=length_between("upperarm_r","lowerarm_r")
		var lower_length=length_between("lowerarm_r","hand_r")
		if not stroke_solution.has("upper_frame"):
			var contact_elbow=stroke_solution.elbow if stroke_solution.has("elbow") else solve_arm_joint(right_shoulder,contact_hand,arm_pole,upper_length,lower_length,chest_basis)
			var upper_dir=(contact_elbow-right_shoulder).normalized()
			var lower_dir=(contact_hand-contact_elbow).normalized()
			var hinge=upper_dir.cross(lower_dir).normalized()
			var upper_frame=Basis(upper_dir,hinge,upper_dir.cross(hinge)).orthonormalized()
			var lower_frame=Basis(lower_dir,hinge,lower_dir.cross(hinge)).orthonormalized()
			stroke_solution.upper_frame=chest_basis.inverse()*upper_frame
			stroke_solution.flex=acos(clampf(upper_dir.dot(lower_dir),-1,1))
			stroke_solution.hand_relative=lower_frame.inverse()*contact_grip*Basis(Vector3.UP,-PI/4 if backhand_stroke or service_stroke else FOREHAND_ROLL)*HAND_GRIP
		var rest_shoulder=rest_at("upperarm_r")
		var rest_hand=rest_at("spine_03")+READY_HAND
		var rest_elbow=solve_arm_joint(rest_shoulder,rest_hand,rest_shoulder+READY_POLE,upper_length,lower_length,Basis.IDENTITY)
		var rest_upper=(rest_elbow-rest_shoulder).normalized()
		var rest_lower=(rest_hand-rest_elbow).normalized()
		var rest_hinge=rest_upper.cross(rest_lower).normalized()
		var rest_upper_frame=Basis(rest_upper,rest_hinge,rest_upper.cross(rest_hinge)).orthonormalized()
		var rest_lower_frame=Basis(rest_lower,rest_hinge,rest_lower.cross(rest_hinge)).orthonormalized()
		var rest_hand_frame=forearm_racket_basis(READY_AXIS,rest_lower,FOREHAND_ROLL)*Basis(Vector3.UP,FOREHAND_ROLL)*HAND_GRIP
		var rest_relative=rest_lower_frame.inverse()*rest_hand_frame
		var start_frame:Basis=stroke_solution.upper_frame
		var follow_frame=Basis(Vector3.RIGHT,.12 if str(p.stroke)=="lift" else .025)*start_frame
		var follow_flex=maxf(deg_to_rad(25),float(stroke_solution.flex)-(.10 if str(p.stroke)=="lift" else .05))
		var start_relative:Basis=stroke_solution.hand_relative
		var follow_relative=start_relative
		if service_stroke:
			if not stroke_solution.has("release"):
				# Short, forward push from the actual impact pose. Preserve the
				# hand plane instead of solving a new sideways shaft each frame.
				var high=0.0 if int(p.shot)==1 else 1.0
				var start_lower=start_frame.x.rotated(start_frame.y,float(stroke_solution.flex))
				var start_lower_frame=Basis(start_lower,start_frame.y,start_lower.cross(start_frame.y)).orthonormalized()
				var start_hand=rest_shoulder+start_frame.x*upper_length+start_lower*lower_length
				var end_hand=start_hand+Vector3(0,lerpf(.015,.04,high),-lerpf(.07,.12,high))
				var max_reach=sqrt(upper_length*upper_length+lower_length*lower_length+2*upper_length*lower_length*cos(deg_to_rad(30)))
				end_hand=rest_shoulder+(end_hand-rest_shoulder).limit_length(max_reach)
				var end_elbow=solve_arm_joint(rest_shoulder,end_hand,rest_shoulder+start_frame.x*upper_length,upper_length,lower_length,Basis.IDENTITY)
				var end_upper=(end_elbow-rest_shoulder).normalized()
				var end_lower=(end_hand-end_elbow).normalized()
				var hinge=end_upper.cross(end_lower).normalized()
				var end_lower_frame=Basis(end_lower,hinge,end_lower.cross(hinge)).orthonormalized()
				stroke_solution.release={"upper_frame":Basis(end_upper,hinge,end_upper.cross(hinge)).orthonormalized(),"flex":acos(clampf(end_upper.dot(end_lower),-1,1)),"relative":end_lower_frame.inverse()*start_lower_frame*start_relative}
			follow_frame=stroke_solution.release.upper_frame
			follow_flex=stroke_solution.release.flex
			follow_relative=stroke_solution.release.relative
		if forehand_overhead:
			if not stroke_solution.has("release"):
				stroke_solution.release=overhead_release(gender,start_frame,start_relative)
			follow_frame=stroke_solution.release.upper_frame
			follow_flex=stroke_solution.release.flex
			follow_relative=stroke_solution.release.relative
		var recovery=smoothstep(.40,1,t)
		var upper_frame:Basis
		var flex:float
		if t<.40:
			var forward=smoothstep(0,.40,t)
			upper_frame=Basis(start_frame.get_rotation_quaternion().slerp(follow_frame.get_rotation_quaternion(),forward))
			flex=lerpf(float(stroke_solution.flex),follow_flex,forward)
		else:
			upper_frame=Basis(follow_frame.get_rotation_quaternion().slerp(rest_upper_frame.get_rotation_quaternion(),recovery))
			flex=lerpf(follow_flex,acos(clampf(rest_upper.dot(rest_lower),-1,1)),recovery)
		upper_frame=chest_basis*upper_frame
		var lower_dir=upper_frame.x.rotated(upper_frame.y,flex)
		var lower_frame=Basis(lower_dir,upper_frame.y,lower_dir.cross(upper_frame.y)).orthonormalized()
		arm_pole=right_shoulder+upper_frame.x*upper_length
		hand=arm_pole+lower_dir*lower_length
		var relative=Basis(start_relative.get_rotation_quaternion().slerp(follow_relative.get_rotation_quaternion(),smoothstep(0,.25,t)))
		var hand_frame=lower_frame*Basis(relative.get_rotation_quaternion().slerp(rest_relative.get_rotation_quaternion(),recovery))
		racket_basis=hand_frame*HAND_GRIP.inverse()*grip_change.inverse()
		axis=racket_basis.y
	# Rest fingers point +X, thumb is on -Z, palm faces -Y.
	# In a forehand grip the thumb side points toward the racket head (+Y).
	# Preserve handedness: the previous frame put the pinky above the thumb.
	var grip_basis = racket_basis*grip_change*HAND_GRIP
	if not joint_stroke:arm_pole=solve_arm_joint(right_shoulder,hand,arm_pole,length_between("upperarm_r","lowerarm_r"),length_between("lowerarm_r","hand_r"),chest_basis)
	if hit and not backhand_stroke and not service_stroke and not joint_stroke:
		var forearm=(hand-arm_pole).normalized()
		var hinge=(arm_pole-right_shoulder).normalized().cross(forearm).normalized()
		var palm=(grip_basis.y-forearm*grip_basis.y.dot(forearm)).normalized()
		var roll=hinge.signed_angle_to(palm,forearm)
		if t>.001:
			if arm_twist_valid:roll=previous_arm_twist+wrapf(roll-previous_arm_twist,-PI,PI)
			var resting=forearm_racket_basis(ready_axis,forearm,FOREHAND_ROLL)*Basis(Vector3.UP,FOREHAND_ROLL)*HAND_GRIP
			var resting_palm=(resting.y-forearm*resting.y.dot(forearm)).normalized()
			var resting_roll=hinge.signed_angle_to(resting_palm,forearm)
			var target_roll=lerpf(clampf(roll,-1.55,1.55),resting_roll,smoothstep(.65,1,t))
			var correction=(target_roll-roll)*smoothstep(0,.10,t)
			var rotation_=Basis(forearm,correction)
			racket_basis=rotation_*racket_basis
			grip_basis=rotation_*grip_basis
			axis=racket_basis.y
		previous_arm_twist=roll
		arm_twist_valid=true
	# The racket remains fixed inside the V grip. Power comes from forearm
	# rotation, not from turning the handle in the palm or folding the wrist.
	var forehand_hit=hit and not backhand_stroke and not service_stroke
	var pronation=0.0
	if forehand_hit and not joint_stroke:
		var strength=1.0 if str(p.stroke)=="overhead" else .55
		pronation=deg_to_rad(22.0)*strength*smoothstep(0,.20,t)*(1-smoothstep(.40,.85,t))
	elif not hit and not serving:
		pronation=-deg_to_rad(18.0)*prep*(1-receive)
	if absf(pronation)>.0001:
		var forearm=(hand-arm_pole).normalized()
		var spin=Basis(forearm,pronation)
		racket_basis=spin*racket_basis;grip_basis=spin*grip_basis
		axis=racket_basis.y
	var hand_end = limb("upperarm_r","lowerarm_r","hand_r",right_shoulder,hand,arm_pole,length_between("upperarm_r","lowerarm_r"),length_between("lowerarm_r","hand_r"),grip_basis)
	# Forearm pronation is limited around its length; retain the elbow hinge.
	var forearm_direction: Vector3 = (hand_end-joint_points.lowerarm_r).normalized()
	var forearm_basis: Basis = desired[bones.lowerarm_r].basis*rests[bones.lowerarm_r].basis.inverse()
	var target_up = grip_basis.y-forearm_direction*grip_basis.y.dot(forearm_direction)
	if target_up.length()>.01:
		var twist = forearm_basis.y.signed_angle_to(target_up.normalized(),forearm_direction)
		var prepared = 1.0 if not hit or service_stroke or defensive_stroke or backhand_stroke else 0.0
		# Let the forearm carry preparation pronation instead of leaving the
		# remaining rotation as an abrupt twist at the wrist seam.
		var applied_twist = lerpf(clampf(twist,-1.15,1.15)*.7,clampf(twist,-1.65,1.65),prepared)
		# A backhand can cross from pronation to supination. Capping this roll
		# at 95 degrees left the remaining rotation as an inverted wrist seam.
		# Rotate around the forearm's own axis; the elbow hinge stays unchanged.
		if hit:applied_twist=twist
		if bones.has("ace_forearm_r_4"):
			pose("lowerarm_r",joint_points.lowerarm_r,forearm_basis)
			for segment in range(1,5):
				pose("ace_forearm_r_"+str(segment),joint_points.lowerarm_r,Basis(forearm_direction,applied_twist*segment/4.0)*forearm_basis)
		else:
			pose("lowerarm_r",joint_points.lowerarm_r,Basis(forearm_direction,applied_twist)*forearm_basis)
	var free_pole = left_shoulder+chest_basis*Vector3(-.42,-.45,-.14).lerp(Vector3(-.40,.05,-.1),0.0 if hit else prep)
	if serving or receive>.01:free_pole=left_shoulder+chest_basis*Vector3(-.38,-.36,-.12)
	var balance_open=1-smoothstep(.45,1,t) if underarm_stroke else (float(p.get("rescue_weight",0)) if not hit and not serving and local_ball.y<1.9 else 0.0)
	var balance_twist=0.0
	if balance_open>0:
		# Keep the ready stance elbow bend; lift/open the upper arm only nine
		# degrees instead of reaching the free hand away from the body.
		var upper_length=length_between("upperarm_l","lowerarm_l")
		var lower_length=length_between("lowerarm_l","hand_l")
		var rest_shoulder=rest_at("upperarm_l")-rest_at("spine_03")
		var endpoints=[]
		var resting_elbow=solve_arm_joint(rest_shoulder,FREE_READY,rest_shoulder+Vector3(-.42,-.45,-.14),upper_length,lower_length,Basis.IDENTITY,-1.0)
		var resting_upper=(resting_elbow-rest_shoulder).normalized()
		var resting_lower=(FREE_READY-resting_elbow).normalized()
		var resting_hinge=resting_upper.cross(resting_lower).normalized()
		var resting_frame=Basis(resting_upper,resting_hinge,resting_upper.cross(resting_hinge)).orthonormalized()
		var resting_flex=acos(clampf(resting_upper.dot(resting_lower),-1,1))
		endpoints.append({"frame":resting_frame,"flex":resting_flex})
		endpoints.append({"frame":Basis(Vector3.BACK,-.16)*resting_frame,"flex":resting_flex})
		# Interpolate joint angles, not independent wrist/pole positions that
		# can cross a singularity and switch the elbow to the opposite branch.
		var upper_frame=Basis(endpoints[0].frame.get_rotation_quaternion().slerp(endpoints[1].frame.get_rotation_quaternion(),balance_open))
		var flex=lerpf(endpoints[0].flex,endpoints[1].flex,balance_open)
		var open_frame:Basis=endpoints[1].frame
		var open_lower=open_frame.x.rotated(open_frame.y,float(endpoints[1].flex))
		var open_palm=Vector3(.8,-.1,-.7)
		open_palm=(open_palm-open_lower*open_palm.dot(open_lower)).normalized()
		balance_twist=clampf(open_frame.y.signed_angle_to(open_palm,open_lower),-2.0,2.0)
		upper_frame=chest_basis*upper_frame
		free_pole=left_shoulder+upper_frame.x*upper_length
		free_hand=free_pole+upper_frame.x.rotated(upper_frame.y,flex)*lower_length
	var free_elbow = solve_arm_joint(left_shoulder,free_hand,free_pole,length_between("upperarm_l","lowerarm_l"),length_between("lowerarm_l","hand_l"),chest_basis,-1.0)
	free_pole=free_elbow
	# Use the same elbow hinge for the free hand and forearm. Independent
	# shortest-arc aiming left the wrist rolled against the arm when it opened.
	var free_forearm=(free_hand-free_elbow).normalized()
	var free_hinge=-(free_elbow-left_shoulder).normalized().cross(free_forearm).normalized()
	var free_basis=Basis(-free_forearm,free_hinge,(-free_forearm).cross(free_hinge)).orthonormalized()
	var free_twist=0.0
	if balance_open>0:
		free_twist=balance_twist*balance_open
		free_basis=Basis(free_forearm,free_twist)*free_basis
	limb("upperarm_l","lowerarm_l","hand_l",left_shoulder,free_hand,free_pole,length_between("upperarm_l","lowerarm_l"),length_between("lowerarm_l","hand_l"),free_basis)
	if bones.has("ace_forearm_l_4"):
		var lower_basis=desired[bones.lowerarm_l].basis*rests[bones.lowerarm_l].basis.inverse()
		for segment in range(1,5):
			pose("ace_forearm_l_"+str(segment),joint_points.lowerarm_l,Basis(free_forearm,free_twist*segment/4.0)*lower_basis)
	racket_basis_current = racket_basis
	racket_mount_current = current_mount
	apply_poses()
	racket_contact_world = position+base*(hand_end+racket_basis*racket_mount_current+axis.normalized()*contact_offset)
	racket_center_world = position+base*(hand_end+racket_basis*racket_mount_current+axis.normalized()*RACKET_CENTER)
	contact_error = racket_contact_world.distance_to(position+base*contact) if hit and t<.001 else 0.0

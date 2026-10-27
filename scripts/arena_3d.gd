extends SubViewport
## A shared 3D world and camera for the court, athletes, racket and shuttle.
const ATHLETE_3D = preload("res://scripts/athlete_3d.gd")
var world: Node3D
var court: Node3D
var back_walls = []
var camera: Camera3D
var athletes = []
var previews = []
var shuttle: Node3D
var view_key = ""
var camera_focus_y = .45
var game_ref: Node2D

func setup(game: Node2D) -> void:
	game_ref = game
	size = Vector2i(1440,900)
	transparent_bg = true
	world_3d = World3D.new()
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_2X
	world = Node3D.new()
	add_child(world)
	var environment = WorldEnvironment.new()
	var settings = Environment.new()
	settings.background_mode = Environment.BG_CLEAR_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c7c9d2")
	settings.ambient_light_energy = .30
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	world.add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-28,0)
	light.light_color = Color("fff2da")
	light.light_energy = .85
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 38
	world.add_child(light)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-32,148,0)
	fill.light_color = Color("b9dcea")
	fill.light_energy = .22
	world.add_child(fill)
	camera = Camera3D.new()
	camera.near = .05
	camera.far = 100
	world.add_child(camera)
	camera.current = true
	court = Node3D.new()
	world.add_child(court)
	build_court()
	for i in range(2):
		var athlete = ATHLETE_3D.new()
		world.add_child(athlete)
		athlete.build("male",i)
		athletes.append(athlete)
	shuttle = Node3D.new()
	world.add_child(shuttle)
	preload("res://scripts/shuttle_3d.gd").build(shuttle)
	configure_view(game)

func box(parent: Node3D, at: Vector3, dimensions: Vector3, mat: Material) -> MeshInstance3D:
	var shape = BoxMesh.new()
	shape.size = dimensions
	return ATHLETE_3D.mesh(parent,shape,mat,at)

func build_court() -> void:
	var apron = ATHLETE_3D.material(Color("282a30"))
	var rubber = ShaderMaterial.new()
	rubber.shader = preload("res://scripts/court_surface.gdshader")
	rubber.set_shader_parameter("floor_color",Color("287363"))
	var line = ATHLETE_3D.material(Color("e8e6e0"))
	box(court,Vector3(0,-.22,0),Vector3(38,.12,42),ATHLETE_3D.material(Color("111217")))
	box(court,Vector3(0,-.10,0),Vector3(10.5,.16,18.8),apron)
	box(court,Vector3(0,-.014,0),Vector3(6.1,.02,13.4),rubber)
	for x in [-3.05,-2.59,2.59,3.05]: box(court,Vector3(x,.012,0),Vector3(.025,.012,13.4),line)
	for z in [-6.7,-5.94,-1.98,1.98,5.94,6.7]: box(court,Vector3(0,.012,z),Vector3(6.1,.012,.025),line)
	for z in [-4.34,4.34]: box(court,Vector3(0,.014,z),Vector3(.025,.012,4.72),line)
	var posts = ATHLETE_3D.material(Color("22232a"),.4)
	for x in [-3.2,3.2]:
		ATHLETE_3D.bar(court,Vector3(x,0,0),Vector3(x,1.60,0),.027,posts)
		box(court,Vector3(x,.025,0),Vector3(.34,.05,.18),apron)
	# Actual mesh net: players and shuttle occlude correctly from either baseline.
	var net_mesh = SurfaceTool.new()
	net_mesh.begin(Mesh.PRIMITIVE_LINES)
	for i in range(65):
		var x = -3.2+i*.1
		net_mesh.add_vertex(Vector3(x,.78,0))
		net_mesh.add_vertex(Vector3(x,1.55,0))
	for i in range(9):
		net_mesh.add_vertex(Vector3(-3.2,.78+i*.096,0))
		net_mesh.add_vertex(Vector3(3.2,.78+i*.096,0))
	ATHLETE_3D.mesh(court,net_mesh.commit(),ATHLETE_3D.material(Color("414347")))
	box(court,Vector3(0,1.55,0),Vector3(6.4,.035,.025),line)
	# Restrained 3D arena furniture, outside the playable court.
	var seats = ATHLETE_3D.material(Color("171923"))
	for z in [-10.1,10.1]:
		for row in range(3): box(court,Vector3(0,.25+row*.28,z+signf(z)*row*.45),Vector3(9,.25,.38),seats)
	# Sponsor perimeter outside the run-off area. Text faces the playing court.
	for side in [-1,1]:
		for k in range(6):
			if side==1 and k in [2,3]: continue
			advert_board(Vector3(side*4.9,0,-6.75+k*2.7),-side*PI/2,2.62,k+(0 if side<0 else 2))
		for k in range(4):
			advert_board(Vector3(-3.6+k*2.4,0,side*9.4),PI if side>0 else 0,2.32,k+1)
	umpire_chair(Vector3(4.5,0,0))
	for entry in [[Vector3(-4.3,0,.4),-PI/2],[Vector3(6.1,0,-3.2),PI/2],[Vector3(6.1,0,3.9),PI/2]]:
		seated_official(entry[0],entry[1],0)
	for side in [-1,1]:
		floor_word(Vector3(side*4.1,-.006,4.2*side),0 if side<0 else PI,"ACE  ARENA")
	# Dark arena walls retain a lit court and a restrained competition backdrop.
	back_walls.append(box(court,Vector3(0,3,-11),Vector3(28,6,.2),ATHLETE_3D.material(Color("0d0e14"))))
	back_walls.append(box(court,Vector3(0,3,11),Vector3(28,6,.2),ATHLETE_3D.material(Color("0d0e14"))))

func event_label(parent: Node3D, caption: String, at: Vector3, pixel: float = .0046) -> Label3D:
	var label = Label3D.new()
	var font = FontVariation.new()
	font.base_font = preload("res://assets/NotoSansSC.ttf")
	font.variation_opentype = {0x77676874:750.0}
	label.font=font; label.text=caption; label.font_size=64
	label.pixel_size=pixel; label.outline_size=0; label.position=at
	parent.add_child(label)
	return label

func floor_word(at: Vector3, yaw: float, caption: String) -> void:
	var label=event_label(court,caption,at,.0032)
	label.rotation=Vector3(-PI/2,yaw,0)
	label.modulate=Color("d8d9dc")

func seated_official(at: Vector3, yaw: float, elevation: float) -> void:
	var seat=Node3D.new();court.add_child(seat);seat.position=at;seat.rotation.y=yaw
	var steel=ATHLETE_3D.material(Color("626773"));var fabric=ATHLETE_3D.material(Color("222734"))
	box(seat,Vector3(0,elevation+.46,.03),Vector3(.49,.07,.48),fabric)
	box(seat,Vector3(0,elevation+.78,.25),Vector3(.49,.59,.045),fabric)
	for x in [-.20,.20]:
		for z in [-.17,.20]: ATHLETE_3D.bar(seat,Vector3(x,elevation+.43,z),Vector3(x*1.2,elevation,z*1.2),.018,steel)
	var person=ATHLETE_3D.new();seat.add_child(person);person.build("male",1);person.position.y=elevation
	person.racket.visible=false;person.desired.clear()
	var pelvis=Vector3(0,.56,.04);person.pose("pelvis",pelvis,Basis.IDENTITY)
	var previous="pelvis";var point=pelvis
	for name_ in ["spine_01","spine_02","spine_03","neck_01","Head"]:
		point+=person.rest_at(name_)-person.rest_at(previous);person.pose(name_,point,Basis.IDENTITY);previous=name_
	for side in ["l","r"]:
		var sx=-1.0 if side=="l" else 1.0
		var hip=pelvis+person.rest_at("thigh_"+side)-person.rest_at("pelvis")
		person.limb("thigh_"+side,"calf_"+side,"foot_"+side,hip,Vector3(sx*.16,.10,-.44),hip+Vector3(0,.0,-1),person.length_between("thigh_"+side,"calf_"+side),person.length_between("calf_"+side,"foot_"+side),Basis.IDENTITY)
		var shoulder=pelvis+person.rest_at("upperarm_"+side)-person.rest_at("pelvis")
		person.limb("upperarm_"+side,"lowerarm_"+side,"hand_"+side,shoulder,Vector3(sx*.20,.72,-.24),shoulder+Vector3(sx*.1,-.5,.05),person.length_between("upperarm_"+side,"lowerarm_"+side),person.length_between("lowerarm_"+side,"hand_"+side),Basis(Quaternion(Vector3(sx,0,0),Vector3(0,-.3,-.95).normalized())))
	person.apply_poses()
	for part in person.find_children("*","MeshInstance3D",true,false):
		for surface in range(part.mesh.get_surface_count()):
			var mat=part.get_surface_override_material(surface)
			if mat is ShaderMaterial: mat.set_shader_parameter("jersey_color",Color("848d9c"))

func umpire_chair(at: Vector3) -> void:
	var navy=ATHLETE_3D.material(Color("24243c"))
	box(court,at+Vector3(.12,1.03,.16),Vector3(.95,2.06,1.1),navy)
	for x in [-.33,.33]:
		ATHLETE_3D.bar(court,at+Vector3(x,0,-.95),at+Vector3(x,1.9,-.36),.025,ATHLETE_3D.material(Color("b4bac4")))
	for k in range(7): box(court,at+Vector3(0,.15+k*.26,-.90+k*.08),Vector3(.72,.045,.10),ATHLETE_3D.material(Color("b4bac4")))
	seated_official(at+Vector3(0,0,-.05),PI/2,1.55)
	var badge=event_label(court,"ACE\nSPORTS",at+Vector3(.10,1.0,.73),.0037)
	badge.modulate=Color("dfe4ed")

func advert_board(at: Vector3, yaw: float, width: float, variant: int) -> void:
	var holder = Node3D.new()
	court.add_child(holder)
	holder.position = at
	holder.rotation.y = yaw
	var index = variant%4
	var colors = [Color("153a43"),Color("dce8d3"),Color("be5d48"),Color("182837")]
	var inks = [Color("d6f68c"),Color("24494d"),Color("fff1df"),Color("cce4dd")]
	var base = ATHLETE_3D.material(colors[index])
	var trim = ATHLETE_3D.material(inks[index])
	box(holder,Vector3(0,.34,0),Vector3(width,.66,.065),base)
	box(holder,Vector3(0,.665,.01),Vector3(width,.025,.09),trim)
	for end in [-1,1]:
		box(holder,Vector3(end*(width*.5-.15),.035,-.10),Vector3(.12,.06,.40),ATHLETE_3D.material(Color("101e27")))
	var label = Label3D.new()
	var advert_font = FontVariation.new()
	advert_font.base_font = preload("res://assets/NotoSansSC.ttf")
	advert_font.variation_opentype = {0x77676874:750.0}
	label.font = advert_font
	label.text = ["ACE SPORTS","羽动装备","FEATHER CLUB","飞羽运动"][index]
	label.font_size = 64
	label.pixel_size = .0046
	label.modulate = inks[index]
	label.outline_size = 0
	label.position = Vector3(0,.37,.075)
	holder.add_child(label)

func configure_view(game: Node2D) -> void:
	var viewport_size = Vector2i(game.get_viewport_rect().size)
	if viewport_size.x>0 and viewport_size.y>0 and size!=viewport_size: size=viewport_size
	var key = game.screen+str(game.baseline_camera)+str(game._local_player_index())+str(size)
	if key==view_key: return
	view_key = key
	for wall in back_walls: wall.visible=wall.position.z*(game._view_sign() if game.screen=="game" else 1)<0
	if game.screen=="avatars":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 8.2*size.y/(game.interface_scale()*900)
		camera.position = Vector3(0,0,8)
		camera.look_at(Vector3.ZERO)
	elif game.screen=="menu":
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 37
		camera.position = Vector3(-6,12,18)
		camera.look_at(Vector3(-5.2,.5,0))
	else:
		var side = game._view_sign()
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 30 if game.baseline_camera else 40
		camera.position = Vector3(0,5.7,16.0*side) if game.baseline_camera else Vector3(0,17.5,13.0*side)
		camera.look_at(Vector3(0,.45 if game.baseline_camera else .35,0))
	if game.screen!="avatars":
		var aspect = float(size.x)/size.y
		# A 4:3 window still has ample room for the court: don't zoom it out
		# just to preserve the old wide-screen header/sidebar proportions.
		var minimum_aspect = 1.6 if game.screen=="menu" else 1.2
		camera.fov = rad_to_deg(2*atan(tan(deg_to_rad(camera.fov)*.5)*maxf(1,minimum_aspect/aspect)))

func project(value: Vector3, game: Node2D) -> Vector2:
	configure_view(game)
	return game.screen_to_interface(camera.unproject_position(Vector3(value.x,value.z,value.y)))

func update_rally_camera(game: Node2D, dt: float) -> void:
	if game.screen!="game" or not game.baseline_camera:return
	var future: Vector3 = game.ball+game.velocity*.18+Vector3(0,0,-.5*game.G*.18*.18)
	var height = maxf(game.ball.z,future.z)
	var target_focus = .45+clampf((height-3.0)*.5,0,1.5)
	camera_focus_y = lerpf(camera_focus_y,target_focus,1-exp(-maxf(dt,.001)*7))
	camera.look_at(Vector3(0,camera_focus_y,0))
	var view = camera.transform.affine_inverse()
	var aspect = float(size.x)/size.y
	var tangent = tan(deg_to_rad(30)*.5)
	var points = [Vector3(-3.2,0,-6.8),Vector3(3.2,0,-6.8),Vector3(-3.2,0,6.8),Vector3(3.2,0,6.8),Vector3(game.ball.x,game.ball.z,game.ball.y),Vector3(future.x,future.z,future.y)]
	for point in points:
		var local: Vector3 = view*point
		if local.z<-.1:
			tangent=maxf(tangent,maxf(absf(local.y)/(-local.z*.90),absf(local.x)/(-local.z*aspect*.93)))
	var desired_fov = clampf(rad_to_deg(2*atan(tangent)),30,58)
	# Anticipate rising shuttle; ease back in after a high clear, keeping true projection.
	camera.fov = desired_fov if desired_fov>camera.fov else lerpf(camera.fov,desired_fov,1-exp(-maxf(dt,.001)*4))

func sync(game: Node2D, dt: float = 1.0/60) -> void:
	configure_view(game)
	update_rally_camera(game,dt)
	var active = game.screen in ["menu","game","avatars"]
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	court.visible = game.screen!="avatars"
	shuttle.visible = game.screen!="avatars"
	for athlete in athletes: athlete.visible = game.screen!="avatars"
	for preview in previews: preview.visible = game.screen=="avatars"
	if not active: return
	if game.screen=="avatars":
		if previews.is_empty():
			for i in range(4):
				var model = ATHLETE_3D.new()
				world.add_child(model)
				model.build("male" if i<2 else "female",1-i%2)
				previews.append(model)
		for i in range(4):
			var p: Dictionary = game.players[0].duplicate(true)
			p.merge({"pos":Vector2.ZERO,"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"buffer":0.0,"landing":0.0,"step":0.0,"dash":0.0,"avatar":"male" if i<2 else "female"},true)
			game.FOOTWORK.reset(p)
			previews[i].animate(p,1-i%2,Vector3(0,0,2),game.clock_time)
			var point: Vector2 = Vector2([395,545,895,1045][i],571)*game.interface_scale()+game.interface_offset()
			previews[i].position = Vector3((point.x-size.x*.5)*camera.size/size.y,(size.y*.5-point.y)*camera.size/size.y,0)
	else:
		for i in range(2): athletes[i].animate(game.players[i],i,game.ball,game.clock_time,game.phase=="serve" and game.server==i)
		shuttle.position = Vector3(game.ball.x,game.ball.z,game.ball.y)
		var direction = Vector3(game.velocity.x,game.velocity.z,game.velocity.y)
		if direction.length()>.1: shuttle.quaternion = Quaternion(Vector3.UP,-direction.normalized())

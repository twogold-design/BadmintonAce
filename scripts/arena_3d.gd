extends SubViewport
## A shared 3D world and camera for the court, athletes, racket and shuttle.
const ATHLETE_3D = preload("res://scripts/athlete_3d.gd")
var world: Node3D
var court: Node3D
var camera: Camera3D
var athletes = []
var previews = []
var shuttle: Node3D
var view_key = ""
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
	settings.ambient_light_color = Color("c6d9e0")
	settings.ambient_light_energy = .35
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
	var white = ATHLETE_3D.material(Color("f6f4df"))
	ATHLETE_3D.ellipsoid(shuttle,Vector3.ZERO,Vector3(.035,.038,.035),ATHLETE_3D.material(Color("d8c1a0")))
	for i in range(12):
		var a = i*TAU/12
		var feather = ATHLETE_3D.ellipsoid(shuttle,Vector3(cos(a)*.052,.09,sin(a)*.052),Vector3(.018,.068,.008),white)
		feather.rotation = Vector3(sin(a)*.38,-a,cos(a)*-.38)
	configure_view(game)

func box(parent: Node3D, at: Vector3, dimensions: Vector3, mat: Material) -> void:
	var shape = BoxMesh.new()
	shape.size = dimensions
	ATHLETE_3D.mesh(parent,shape,mat,at)

func build_court() -> void:
	var apron = ATHLETE_3D.material(Color("254247"))
	var green = ATHLETE_3D.material(Color("287363"))
	var stripe = ATHLETE_3D.material(Color("2c7969"))
	var line = ATHLETE_3D.material(Color("e0e9cc"))
	box(court,Vector3(0,-.10,0),Vector3(8.5,.16,16),apron)
	box(court,Vector3(0,-.014,0),Vector3(6.1,.02,13.4),green)
	for i in range(7): box(court,Vector3(0,.0,-6.7+(i*2+.5)*13.4/14),Vector3(6.1,.008,13.4/14),stripe)
	for x in [-3.05,-2.59,2.59,3.05]: box(court,Vector3(x,.012,0),Vector3(.025,.012,13.4),line)
	for z in [-6.7,-5.94,-1.98,1.98,5.94,6.7]: box(court,Vector3(0,.012,z),Vector3(6.1,.012,.025),line)
	for z in [-4.34,4.34]: box(court,Vector3(0,.014,z),Vector3(.025,.012,4.72),line)
	var posts = ATHLETE_3D.material(Color("8caaa8"),.4)
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
	ATHLETE_3D.mesh(court,net_mesh.commit(),ATHLETE_3D.material(Color("678d89")))
	box(court,Vector3(0,1.55,0),Vector3(6.4,.035,.025),line)
	# Restrained 3D arena furniture, outside the playable court.
	var seats = ATHLETE_3D.material(Color("16323e"))
	for z in [-8.6,8.6]:
		for row in range(3): box(court,Vector3(0,.25+row*.28,z+signf(z)*row*.45),Vector3(9,.25,.38),seats)

func configure_view(game: Node2D) -> void:
	var key = game.screen+str(game.baseline_camera)+str(game._local_player_index())
	if key==view_key: return
	view_key = key
	if game.screen=="avatars":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 8.2
		camera.position = Vector3(0,0,8)
		camera.look_at(Vector3.ZERO)
	elif game.screen=="menu":
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 42
		camera.position = Vector3(-7,12,20)
		camera.look_at(Vector3(-6.0,.4,0))
	else:
		var side = game._view_sign()
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 44 if game.baseline_camera else 45
		camera.position = Vector3(0,8.0,17.0*side) if game.baseline_camera else Vector3(0,17.5,13.0*side)
		camera.look_at(Vector3(0,1.8 if game.baseline_camera else 1.15,0))

func project(value: Vector3, game: Node2D) -> Vector2:
	configure_view(game)
	return camera.unproject_position(Vector3(value.x,value.z,value.y))

func sync(game: Node2D) -> void:
	configure_view(game)
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
			previews[i].position = Vector3(([395,545,895,1045][i]-720)*8.2/900.0,(450-571)*8.2/900.0,0)
	else:
		for i in range(2): athletes[i].animate(game.players[i],i,game.ball,game.clock_time,game.phase=="serve" and game.server==i)
		shuttle.position = Vector3(game.ball.x,game.ball.z,game.ball.y)
		var direction = Vector3(game.velocity.x,game.velocity.z,game.velocity.y)
		if direction.length()>.1: shuttle.quaternion = Quaternion(Vector3.UP,-direction.normalized())

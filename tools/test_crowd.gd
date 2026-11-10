extends SceneTree
## Crowd remains decorative, camera-safe and responsive to local/remote scores.
var checks = 0
var failures = 0

func _initialize(): call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func check_assets() -> void:
	for gender in ["male","female","male-flag","female-flag","male-horn","female-horn"]:
		var mesh: ArrayMesh = load("res://assets/crowd/"+gender+".res")
		var texture: Texture2D = load("res://assets/crowd/"+gender+"-poses.res")
		check(mesh!=null and texture!=null,gender+" audience assets exist")
		if not mesh or not texture: continue
		check(mesh.get_surface_count()==1,gender+" uses one consolidated surface")
		var arrays = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var garment: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var triangles = indices.size()/3
		check(triangles>3000 and triangles<12000,gender+" retains human detail within the crowd triangle budget")
		check(vertices.size()>1000 and uv2.size()==vertices.size() and garment.size()==vertices.size(),gender+" has complete vertex pose and garment coordinates")
		var bounds = mesh.get_aabb().size
		check(bounds.y>1.0 and bounds.y<2.1 and bounds.x>.3 and bounds.x<1.1,gender+" seated mesh has human proportions")
		var image = texture.get_image()
		check(image!=null and not image.is_empty(),gender+" baked pose image is readable")
		if not image or image.is_empty(): continue
		var rows = ceili(float(vertices.size())/image.get_width())
		check(image.get_format()==Image.FORMAT_RGBAF and image.get_height()==rows*12,gender+" pose texture stores six position/normal frame pairs")
		var all_finite = true
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel = image.get_pixel(x,y)
				if not (is_finite(pixel.r) and is_finite(pixel.g) and is_finite(pixel.b) and is_finite(pixel.a)):
					all_finite = false
		check(all_finite,gender+" pose texture contains only finite values")
		var matching_ids = true
		var stable_chair = true
		var body_motion = 0.0
		var has_skin_mask = false
		for i in range(vertices.size()):
			matching_ids = matching_ids and is_equal_approx(uv2[i].x,float(i))
			has_skin_mask = has_skin_mask or garment[i].y>.5
			var rest = image.get_pixel(i%image.get_width(),i/image.get_width())
			var rest_position = Vector3(rest.r,rest.g,rest.b)
			for frame in range(1,6):
				var pixel = image.get_pixel(i%image.get_width(),i/image.get_width()+frame*rows*2)
				var position = Vector3(pixel.r,pixel.g,pixel.b)
				if i>=vertices.size()-144:
					stable_chair = stable_chair and position.is_equal_approx(rest_position)
				else:
					body_motion = maxf(body_motion,position.distance_to(rest_position))
		check(matching_ids and has_skin_mask,gender+" shader can address every baked vertex and identify skin surfaces")
		check(stable_chair,gender+" chair remains fixed through all six poses")
		check(body_motion>.2 and body_motion<1.5,gender+" seated and standing poses have bounded meaningful movement")
		print("CROWD ASSET ",gender,": ",vertices.size()," vertices, ",triangles," triangles, ",image.get_width(),"x",image.get_height()," pose texture")

func run() -> void:
	check_assets()
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.offline_mode = true
	game.test_mode = true # Native test windows must not auto-pause on focus loss.
	game.start_game("ai")
	var crowd = game.arena.crowd
	game.arena.sync(game,0)
	check(crowd.visible,"Spectators are visible during a match")
	var population = 0
	var prop_counts = {"plain":0,"flag":0,"horn":0}
	var check_gpu_placement = DisplayServer.get_name()!="headless"
	if not check_gpu_placement:
		print("SKIP crowd placement readback: headless dummy renderer does not retain MultiMesh transforms; run this test with a native renderer for placement assertions.")
	for section in crowd.sections:
		population += section.multimesh.instance_count
		var kind = str(section.get_meta("prop_kind",""))
		check(prop_counts.has(kind),"Each crowd group has a supported prop type")
		if prop_counts.has(kind): prop_counts[kind] += section.multimesh.instance_count
		check(section.layers==2,"Spectators and held props use the dim audience light layer")
		check(section.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Fans do not add dynamic shadow passes")
		check(section.multimesh.use_colors,"Explicit instance colors preserve skin and face vertex colors")
		if check_gpu_placement:
			for i in range(section.multimesh.instance_count):
				var at: Vector3 = section.multimesh.get_instance_transform(i).origin
				check(absf(at.x)>5.8 or absf(at.z)>9.7,"Fans remain outside the court and advertising perimeter")
				check(section.multimesh.get_instance_color(i).is_equal_approx(Color.WHITE),"Instance tint keeps original skin and shoes visible")
		var side = float(section.get_meta("baseline_side"))
		check(section.visible==(side!=1.0),"P1 view keeps near-baseline fans out of the foreground")
	check(population==96 and population<=120,"Crowd population stays within the lightweight budget")
	check(crowd.sections.size()<=24,"Characters and prop variants stay within twenty-four instanced groups")
	check(prop_counts=={"plain":72,"flag":16,"horn":8},"A minority of spectators carry flags and horns")
	var crowd_key = game.arena.world.get_node_or_null("CrowdKey")
	var crowd_fill = game.arena.world.get_node_or_null("CrowdFill")
	check(crowd_key is DirectionalLight3D and crowd_fill is DirectionalLight3D,"Audience has dedicated directional lights")
	if crowd_key and crowd_fill:
		check(crowd_key.light_cull_mask==2 and crowd_fill.light_cull_mask==2,"Audience lights affect only the crowd layer")
		check(crowd_key.light_energy>0 and crowd_key.light_energy<.85 and crowd_fill.light_energy>=0 and crowd_fill.light_energy<.22,"Audience lights are dimmer than the court lights")
	var before = crowd.elapsed
	game.arena.sync(game,.2)
	check(crowd.elapsed>before,"Crowd animation advances during play")
	game.phase = "rally"
	game.arena.sync(game,0)
	game.score = [1,0]
	game.phase = "point"
	game.arena.sync(game,.1)
	check(is_equal_approx(crowd.excitement,1.0),"A scored point starts a celebration")
	game.arena.sync(game,.5)
	check(crowd.excitement>0.0 and crowd.excitement<1.0,"Repeated score snapshots let a celebration decay")
	game.paused = true
	before = crowd.elapsed
	var cheer_before = crowd.excitement
	game.arena.sync(game,1.0)
	check(is_equal_approx(crowd.elapsed,before) and is_equal_approx(crowd.excitement,cheer_before),"Pause freezes crowd motion and celebration")
	game.paused = false
	game.arena.sync(game,3.0)
	check(is_zero_approx(crowd.excitement),"An unchanged score does not continuously restart celebration")
	game.mode = "online"
	game.net_role = "guest"
	game.arena.sync(game,0)
	for section in crowd.sections:
		var side = float(section.get_meta("baseline_side"))
		check(section.visible==(side!=-1.0),"Guest view hides its own near-baseline section")
	game.score = [1,1]
	game.phase = "serve"
	game.arena.sync(game,.1)
	check(is_equal_approx(crowd.excitement,1.0),"Guest score changes cheer even when a point phase was skipped")
	game.arena.sync(game,3.0)
	game.phase = "end"
	game.arena.sync(game,.1)
	check(is_equal_approx(crowd.excitement,1.0),"Match end starts a final celebration")
	for screen in ["menu","avatars","login","challenges"]:
		game.screen = screen
		before = crowd.elapsed
		crowd.sync(game,1.0)
		check(not crowd.visible and is_equal_approx(crowd.elapsed,before),"Fans are hidden and idle on "+screen)
	game.screen = "game"
	game.mode = "practice"
	game.net_role = ""
	game.score = [0,0]
	game.phase = "rally"
	crowd.sync(game,0)
	check(is_zero_approx(crowd.excitement),"A fresh match clears the previous celebration")
	game.phase = "point"
	crowd.sync(game,.1)
	check(is_equal_approx(crowd.excitement,1.0),"Practice rallies cheer without changing the score")
	var ball_before: Vector3 = game.ball
	var score_before: Array = game.score.duplicate()
	var phase_before: String = game.phase
	crowd.sync(game,.1)
	check(game.ball==ball_before and game.score==score_before and game.phase==phase_before,"Crowd updates do not modify gameplay")
	print("CROWD: ",checks," checks; ",failures," failures; population=",population)
	game.queue_free()
	quit(1 if failures else 0)

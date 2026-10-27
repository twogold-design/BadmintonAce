extends SceneTree
var game

func _initialize() -> void: call_deferred("run")

func capture(name_: String) -> void:
	game.arena.sync(game)
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/"+name_+".png")

func run() -> void:
	root.size = Vector2i(1440,900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game._build_menu()
	for frame in range(180): game._physics_process(1.0/60)
	await capture("menu")
	game.start_game("ai")
	game.players[0].avatar = "male"
	game.players[1].avatar = "female"
	game.baseline_camera = true
	await capture("3d-court")
	game.phase = "rally"
	game.ball = Vector3(.45,2.9,2.45)
	var p: Dictionary = game.players[0]
	p.pos = Vector2(0,3.3)
	game.FOOTWORK.reset(p)
	p.charge = 0
	for k in range(45): game.FOOTWORK.update(p,0,1.0/120,true,true,game.ball,false)
	await capture("3d-prepare")
	p.charge = -1
	p.stroke = "overhead"
	p.backhand = false
	game.FOOTWORK.hit(p,0,game.ball,false)
	await capture("3d-contact")
	print("CONTACT ERROR: ",game.arena.athletes[0].contact_error)
	for k in range(24):
		p.swing = maxf(0,p.swing-1.0/120)
		game.FOOTWORK.update(p,0,1.0/120,true,false,game.ball,false)
	await capture("3d-follow")
	game.mode = "online"
	game.net_role = "guest"
	await capture("3d-p2")
	game._show_avatar_selection()
	await capture("3d-avatars")
	# Full-resolution turnarounds of the actual game rig, for anatomy/garment review.
	game.arena.camera.size = 2.35
	game.arena.camera.position = Vector3(0,.92,7)
	game.arena.camera.look_at(Vector3(0,.92,0))
	for i in range(4): game.arena.previews[i].position = Vector3(-1.38+i*.92,0,0)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	game.arena.get_texture().get_image().save_png("res://artifacts/3d-model-review.png")
	quit(0)

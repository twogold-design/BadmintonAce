extends SceneTree
## Render the actual match from both player cameras and the overhead camera.
var game

func _initialize(): call_deferred("run")

func capture(label: String) -> void:
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var error = root.get_texture().get_image().save_png("res://artifacts/crowd-"+label+".png")
	if error!=OK:
		push_error("Could not save crowd capture: "+label)
		quit(1)
	print("Captured crowd-",label,".png")

func run() -> void:
	root.size = Vector2i(1440,900)
	root.content_scale_size = Vector2i(1440,900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.offline_mode = true
	game.test_mode = true # Window focus changes must not open the pause overlay.
	game.start_game("ai")
	game.toast_time = 0.0
	game.baseline_camera = true
	game.arena.sync(game,.6)
	await capture("baseline-p1")
	game.mode = "online"
	game.net_role = "guest"
	game.arena.sync(game,.6)
	await capture("baseline-p2")
	game.mode = "ai"
	game.net_role = ""
	game.baseline_camera = false
	game.arena.sync(game,.6)
	await capture("overhead")
	game.baseline_camera = true
	game.phase = "point"
	game.last_winner = 0
	game.last_reason = "落地得分"
	game.score = [1,0]
	game.arena.sync(game,.1)
	game.arena.sync(game,.85)
	await capture("point")
	# Close-up isolates the distant fans for checking faces and waving arms.
	game.arena.camera.position = Vector3(0,3.1,-6.0)
	game.arena.camera.fov = 45
	game.arena.camera.look_at(Vector3(0,1.6,-10.7))
	await capture("closeup")
	game.queue_free()
	quit()

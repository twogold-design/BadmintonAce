extends SceneTree

var game
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if not value:
		push_error("FAIL: " + label)
		failures += 1
	checks += 1

func release_shot() -> void:
	var key = InputEventKey.new()
	key.physical_keycode = KEY_L
	key.pressed = true
	game._unhandled_key_input(key)
	key.pressed = false
	game._unhandled_key_input(key)

func setup_rally() -> void:
	game.start_game("local")
	game.phase = "rally"
	game.last_hit = 1
	game.players[0].pos = Vector2(0,3)
	game.FOOTWORK.reset(game.players[0])

func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.baseline_camera = true
	game.start_game("local")
	release_shot()
	check(game.total_hits == 0,"initial serve delay respected")
	for tick in range(30): game._physics_process(1.0/120)
	check(game.total_hits == 1,"early release queues one serve")
	setup_rally()
	game.ball = Vector3(0,3,3.3)
	game.velocity = Vector3(0,0,-2)
	release_shot()
	check(game.total_hits == 0,"out-of-reach shuttle waits for contact")
	for tick in range(36): game._physics_process(1.0/120)
	check(game.total_hits == 1 and game.last_hit == 0,"buffered descending shuttle returned exactly once")
	check(game.players[0].buffer == 0,"successful hit consumes queue")
	setup_rally()
	game.ball = Vector3(0,3,5)
	game.velocity = Vector3.ZERO
	release_shot()
	for tick in range(48): game._physics_process(1.0/120)
	check(game.total_hits == 0 and game.players[0].buffer == 0,"expired input cannot hit a high shuttle")
	check(game.toast.begins_with("未击中"),"miss feedback appears after expiry")
	setup_rally()
	game.mode = "online"
	game.last_hit = 0
	game.players[1].pos = Vector2(0,-3)
	game.players[1].buffer = .3
	game.ball = Vector3(1.6,-3,2.6)
	game.velocity = Vector3(0,0,-1)
	game.remote_move = Vector2.LEFT
	game._update_player(1,.05,false)
	check(game.players[1].pos.x < 0,"manual direction overrides assist")
	game.players[1].pos = Vector2(0,-3)
	game.players[1].vel = Vector2.ZERO
	game.remote_move = Vector2.ZERO
	game._update_player(1,.05,false)
	check(game.players[1].pos.x > 0 and game.players[1].pos.x < .2,"nearby queued shot makes a small step")
	game.players[1].pos = Vector2(0,-3)
	game.players[1].vel = Vector2.ZERO
	game.ball.x = 3
	game._update_player(1,.05,false)
	check(game.players[1].pos.x == 0,"assist never chases distant shuttle")
	game.players[1].jump = .001
	game.players[1].jump_v = -1
	game._update_player(1,.05,false)
	check(game.players[1].jump == 0 and game.players[1].landing > 0,"landing triggers recovery pose")
	for shot in range(4):
		setup_rally()
		game.ball = Vector3(0,3,2.5)
		check(game._try_hit(0,shot),"shot accepted")
		check(game.players[0].stroke == ["overhead","overhead","overhead","lift"][shot],"shot and contact height select animation")
		for tick in range(300):
			if game.phase != "rally": break
			game.arena.sync(game,1.0/120)
			var projected = (game._project(game.ball)*game.interface_scale()+game.interface_offset())/game.get_viewport_rect().size*Vector2(1440,900)
			check(projected.y > 20 and projected.y < 868,"actual flight stays outside scoreboard and controls")
			game._step_ball(1.0/120)
	setup_rally()
	game.ball = Vector3(0,3,1.5)
	game._try_hit(0,2)
	check(game.players[0].stroke == "drive","low K uses drive animation")
	# True camera projection must agree with the world, including off-screen extreme heights.
	for side in [-6.7,0.0,6.7]:
		var expected: Vector2 = game.screen_to_interface(game.arena.camera.unproject_position(Vector3(0,12,side)))
		check(game._project(Vector3(0,side,12)).distance_to(expected)<.001,"3D projection never distorts physical height")
	check(game._floor(Vector2(0,6.7)).y > game._floor(Vector2(0,-6.7)).y,"near/far orientation retained")
	var baseline_far = game._floor(Vector2(0,-6.7))
	game.baseline_camera = false
	check(game._floor(Vector2(0,-6.7)).y < baseline_far.y,"baseline view is lower than original overhead view")
	print("CONTROLS / CAMERA: ",checks," checks; ",failures," failures")
	game.queue_free()
	quit(1 if failures else 0)

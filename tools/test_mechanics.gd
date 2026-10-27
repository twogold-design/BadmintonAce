extends SceneTree

var game
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if not condition:
		push_error("FAIL: " + label)
		failures += 1
	checks += 1

func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	print("Font axes: ",game.FONT_SOURCE.get_supported_variation_list())
	for shot in range(4):
		game.start_game("ai")
		game.phase = "rally"
		game.ball = Vector3(0,3,2.5)
		game.players[0].pos = Vector2(0,3)
		game.FOOTWORK.reset(game.players[0])
		game.players[0].charge_time = .25
		game.last_hit = 1
		check(game._try_hit(0,shot),"shot accepted " + str(shot))
		check(not game._try_hit(0,shot),"double touch rejected")
		var min_net = 100.0
		for step in range(400):
			if game.phase != "rally": break
			if absf(game.ball.y) < .12: min_net = minf(min_net,game.ball.z)
			game._step_ball(1.0/120)
		check(game.score[0] == 1,"valid trajectory lands in opponent court " + str(shot))
		check(min_net >= 1.55,"clears net " + str(shot))
	game.start_game("ai")
	game.phase_time = .5
	check(game._try_hit(0,1),"short serve")
	check(game._landing().x < 0 and game._landing().y < -1.98,"diagonal legal serve")
	game.phase = "rally"
	game.ball = Vector3(0,.02,1.0)
	game.velocity = Vector3(0,-5,0)
	game.last_hit = 0
	game._step_ball(.02)
	check(game.score[1] == 1,"net fault awards receiver")
	game.phase = "rally"
	game.ball = Vector3(3.1,-4,.001)
	game.velocity = Vector3(0,0,-1)
	game._step_ball(.02)
	check(game.score[1] == 2,"outside singles sideline is fault")
	check(game.GOAL_SCORE==11,"all matches use fixed eleven-point scoring")
	game.score = [11,10]
	check(not game._match_won(0),"deuce needs two")
	game.score = [12,10]
	check(game._match_won(0),"two-point lead wins")
	game.score = [15,14]
	check(game._match_won(0),"quick match cap")
	game.score = [14,13]
	check(not game._match_won(0),"11-point deuce below cap")
	game.score = [11,9]
	check(game._match_won(0),"11-point standard win")
	game.phase = "rally"
	game.players[0].stamina = 100
	game._jump(0)
	check(game.players[0].jump_v > 0 and game.players[0].stamina == 88,"jump uses stamina")
	game._dash(0)
	check(game.players[0].dash > 0 and game.players[0].stamina == 64,"dash uses stamina")
	# Drop placement must vary, retain a chosen direction, and still clear the net.
	game.start_game("ai")
	game.players[1].pos = Vector2.ZERO
	var drop_landings = []
	for shot in range(6):
		game.phase = "rally"
		game.ball = Vector3(0,3,2.5)
		game.players[0].pos = Vector2(0,3)
		game.FOOTWORK.reset(game.players[0])
		game.players[0].charge_time = .25
		game.last_hit = 1
		check(game._try_hit(0,1),"automatic drop accepted")
		drop_landings.append(game._landing())
		for tick in range(400):
			if game.phase != "rally": break
			game._step_ball(1.0/120)
		check(game.last_winner == 0,"variable drop legally clears net")
	check(drop_landings[0].x * drop_landings[1].x < 0,"automatic drops use both corners")
	check(drop_landings[0].distance_to(drop_landings[2]) > .25,"same-side drops vary depth or width")
	game.players[0].shot_aim = Vector2(-1,1)
	game.players[0].aim = Vector2.ZERO
	var short_left = game._drop_target(0)
	check(short_left.x < -2 and absf(short_left.y) < 1,"stored aim retains short left drop after stopping")
	game.players[0].shot_aim = Vector2(1,-1)
	var long_right = game._drop_target(0)
	check(long_right.x > 2 and absf(long_right.y) > 2,"right deep drop selection")
	game.players[1].shot_aim = Vector2(1,-1)
	check(game._drop_target(1).y < 1,"far player screen direction maps to short depth")
	game.players[0].shot_aim = Vector2.ZERO
	game.players[1].pos = Vector2(2,-3)
	check(game._drop_target(0).x < 0,"automatic drop attacks open space")
	print("MECHANICS PASS: ",checks," checks")
	game.queue_free()
	quit(1 if failures else 0)

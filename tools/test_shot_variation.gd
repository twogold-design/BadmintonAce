extends SceneTree

var game
var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if not ok:
		push_error(label)
		failures += 1
	checks += 1

func hit(i: int, shot: int, height: float, aim: Vector2 = Vector2.ZERO) -> Vector2:
	var side = 1.0 if i == 0 else -1.0
	game.phase = "rally"
	game.ball = Vector3(0,3*side,height)
	game.players[i].pos = Vector2(0,3*side)
	game.FOOTWORK.reset(game.players[i])
	game.players[i].aim = Vector2.ZERO
	game.players[i].shot_aim = aim
	game.players[i].charge_time = .25
	game.last_hit = 1-i
	check(game._try_hit(i,shot),"hit accepted")
	return game._landing()

func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.shot_rng.seed = 72491
	var report = []
	# Integrate actual flight for both players; successful shots must clear the net
	# and land in bounds, not merely produce different target coordinates.
	for i in range(2):
		for scenario in [[0,2.5],[2,2.5],[2,1.4],[3,1.4]]:
			game.start_game("ai")
			game.players[1-i].pos.x = 0
			var points: Array[Vector2] = []
			for n in range(32):
				var landing = hit(i,scenario[0],scenario[1])
				points.append(landing)
				check(absf(landing.x)<2.59 and absf(landing.y)<6.7,"automatic return in singles bounds")
				var before: int = game.score[i]
				for tick in range(480):
					if game.phase != "rally": break
					game._step_ball(1.0/120)
				check(game.score[i]==before+1,"varied return clears net and lands legally")
			var min_x = 99.0
			var max_x = -99.0
			var min_y = 99.0
			var max_y = 0.0
			var repeats = 0
			for n in range(points.size()):
				min_x = minf(min_x,points[n].x)
				max_x = maxf(max_x,points[n].x)
				min_y = minf(min_y,absf(points[n].y))
				max_y = maxf(max_y,absf(points[n].y))
				if n>0 and points[n].distance_to(points[n-1])<.4: repeats+=1
			check(min_x < -1.5 and max_x > 1.5,"stationary returns cover both sides")
			check(max_y-min_y>.25,"constant charge still varies depth")
			check(repeats==0,"automatic returns avoid consecutive identical locations")
			report.append({"player":i,"shot":scenario[0],"height":scenario[1],"x_range":[min_x,max_x],"depth_range":[min_y,max_y]})
		# Direction retained after stopping must override tactical random placement.
		for side in [-1,1]:
			for n in range(12):
				var landing = hit(i,2,2.5,Vector2(side,0))
				check(landing.x*side>1.85 and landing.x*side<2.25,"manual smash keeps chosen side")
		var direction = -1.0 if i == 0 else 1.0
		var short_ball = hit(i,2,2.5,Vector2(0,-direction))
		var deep_ball = hit(i,2,2.5,Vector2(0,direction))
		check(absf(deep_ball.y)-absf(short_ball.y)>.9,"manual depth mirrors for far player")
	# An opponent camping on the right should attract more shots to the left,
	# while occasional body/right shots prevent a fully predictable response.
	game.start_game("ai")
	game.players[1].pos.x = 2
	var left = 0
	var right = 0
	for n in range(120):
		var landing = hit(0,2,2.5)
		if landing.x<0: left+=1
		else: right+=1
	check(left>right and right>10,"placement prefers open space without becoming deterministic")
	var file = FileAccess.open("res://artifacts/shot-variation-test.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":failures==0,"checks":checks,"failures":failures,"samples":report,"open_space":{"left":left,"right":right}},"  "))
	print("SHOT VARIATION ","PASS" if failures==0 else "FAIL",": ",checks," checks; ",failures," failures; 256 integrated returns, manual aim, depth and open space")
	game.queue_free()
	quit(0 if failures==0 else 1)

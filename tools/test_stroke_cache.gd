extends SceneTree
const ATHLETE = preload("res://scripts/athlete_3d.gd")
const FOOTWORK = preload("res://scripts/footwork.gd")
var failures = 0

func _initialize(): call_deferred("run")

func check(ok: bool, label: String):
	if not ok:
		failures += 1
		push_error(label)

func run():
	var model = ATHLETE.new()
	root.add_child(model)
	for avatar in ["male","female"]:
		var p = {"avatar":avatar,"pos":Vector2(0,3.3),"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"stroke":"overhead","backhand":false}
		FOOTWORK.reset(p)
		var ball = Vector3(.35,2.9,2.2)
		FOOTWORK.hit(p,0,ball,false)
		model.animate(p,0,ball,0)
		check(model.stroke_solution.get("valid",false),"A legal contact must have a pose")
		var grip = model.racket_basis_current
		model.stroke_solution.cache_marker = true
		for frame in range(12): model.animate(p,0,ball,frame/144.0)
		check(model.stroke_solution.has("cache_marker"),"Repeated impact frames must reuse the solve")
		check(model.racket_basis_current.is_equal_approx(grip),"Hit-stop must keep the same racket pose")
		p.pos.x += .05
		model.animate(p,0,ball,.1)
		check(not model.stroke_solution.has("cache_marker"),"Changed impact inputs must invalidate the solve")
		model.stroke_solution.cache_marker = true
		p.swing = .2
		model.animate(p,0,ball,.2)
		check(model.stroke_solution.has("cache_marker"),"Follow-through must reuse its contact solve")
		FOOTWORK.hit(p,0,ball,false)
		model.animate(p,0,ball,.3)
		check(not model.stroke_solution.has("cache_marker"),"A new stroke at the same position must solve again")
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.start_game("ai")
	game.phase = "rally"
	game.last_hit = 1
	game.players[0].pos = Vector2(0,3.3)
	FOOTWORK.reset(game.players[0])
	game.ball = Vector3(.35,2.9,2.2)
	check(game._try_hit(0,2),"Set up a real smash")
	var contact: Vector3 = game.ball
	game._physics_process(1.0/60)
	check(game.ball.distance_to(contact)>.01,"The shuttle must advance immediately after a smash")
	print("STROKE CACHE / CONTINUOUS SMASH: failures=",failures)
	quit(1 if failures else 0)

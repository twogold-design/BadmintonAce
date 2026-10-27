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

func packet(t: float, hit: int = 1) -> Dictionary:
	var start = Vector3(.3,2,4)
	var speed = Vector3(1,-5,4)
	var decay = exp(-game.DRAG*t)
	var position = start+Vector3(speed.x*(1-decay)/game.DRAG,speed.y*(1-decay)/game.DRAG,speed.z*t-.5*game.G*t*t)
	var ps = []
	for p in game.players:
		ps.append({"pos":[p.pos.x,p.pos.y],"vel":[0,0],"jump":0,"landing":0,"step":0,"swing":0,"stroke":"overhead","shot":0,"charge":-1,"backhand":false,"motion":game.FOOTWORK.snapshot(p)})
	return {"time":t,"hits":hit,"phase":"rally","last_hit":0,"ball":[position.x,position.y,position.z],"velocity":[speed.x*decay,speed.y*decay,speed.z-game.G*t],"players":ps}

func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.net_role = "host"
	game.start_game("online")
	game.phase = "rally"
	# Controlled lateral chasse; full-speed lateral travel now turns into a run.
	game.remote_move = Vector2(.45,0)
	var planted_frames = 0
	for tick in range(100):
		var p: Dictionary = game.players[1]
		var old_leg = int(p.step_leg)
		var old_support: Vector2 = p.foot_r if old_leg==0 else p.foot_l
		game._update_player(1,1.0/120,false)
		check(not (p.lift_l>.001 and p.lift_r>.001),"ground movement keeps a support foot")
		check(p.foot_l.x<p.foot_r.x,"sideways chasse never crosses the feet")
		if old_leg>=0 and p.step_leg==old_leg:
			var support: Vector2 = p.foot_r if old_leg==0 else p.foot_l
			if support.distance_to(old_support)<.0001: planted_frames += 1
	check(planted_frames>35,"support feet stay planted for most of the stepping cycle")
	check(game.players[1].footwork=="chasse","sideways movement uses chasse steps")
	game.remote_move = Vector2.ZERO
	game.players[1].charge = 0
	game.ball = Vector3(game.players[1].pos.x,game.players[1].pos.y,2.5)
	for tick in range(30): game._update_player(1,1.0/120,false)
	check(absf(game.players[1].body_turn)>.7,"overhead preparation turns the shoulders sideways")
	check(absf(game.players[1].hip_turn)<absf(game.players[1].body_turn),"hips and shoulders have independent rotation")
	var before = float(game.players[1].body_turn)
	game.players[1].charge = -1
	game.last_hit = 0
	check(game._try_hit(1,0),"prepared player hits")
	for tick in range(30): game._update_player(1,1.0/120,false)
	check(absf(game.players[1].body_turn-before)>.3,"stroke rotates out of the sideways preparation")
	check(game.players[1].weight_shift>.7,"stroke transfers weight through the legs")
	for tick in range(65): game._update_player(1,1.0/120,false)
	check(absf(game.players[1].body_turn)<.05,"stroke recovers to net-facing stance")
	game.players[0].pos = Vector2(0,1.3)
	game.FOOTWORK.reset(game.players[0])
	game.ball = Vector3(.4,1.4,1)
	game.last_hit = 1
	game._try_hit(0,1)
	game._update_player(0,.08,false)
	check(game.players[0].lunge>.5,"net shot bends into a racket-side lunge")
	game.players[0].jump = .5
	game.players[0].stroke = "overhead"
	game.FOOTWORK.update(game.players[0],0,.01,true,false,game.ball,false)
	check(game.players[0].footwork=="scissor","airborne overhead uses scissor foot exchange")
	game.net_role = "guest"
	game.start_game("online")
	game.phase = "rally"
	game.baseline_camera = true
	check(game._floor(Vector2(0,-4)).y>game._floor(Vector2(0,4)).y,"P2 own side is nearest camera")
	check(game._floor(Vector2(-1,-4)).x>game._floor(Vector2(1,-4)).x,"P2 horizontal world axis is reversed")
	var remote = game.REMOTE_VIEW.new()
	game.ball = Vector3(.3,2,4)
	game.velocity = Vector3(1,-5,4)
	var expected: Vector2 = game._landing()
	var next_snapshot = 0
	var max_landing_drift = 0.0
	for frame in range(60):
		var wall = frame/60.0
		while next_snapshot/30.0 + ([0.0,.012,.003,.018][next_snapshot%4]) <= wall:
			remote.push(packet(next_snapshot/30.0))
			next_snapshot += 1
		remote.render(game,1.0/60)
		var drift = game._landing().distance_to(expected)
		max_landing_drift = maxf(max_landing_drift,drift)
		check(drift<.002,"jittered packets preserve a stable predicted landing")
	remote.push(packet(1.02,2))
	for frame in range(20): remote.render(game,1.0/60)
	check(remote.shown_hit==2,"render timeline advances across a shot boundary")
	var pose = game.ATHLETE.STROKE_POSE
	var athlete: Dictionary = game.players[0].duplicate(true)
	athlete.merge({"vel":Vector2.ZERO,"step":0.0,"swing":.48,"stroke":"overhead","backhand":false},true)
	var contact = pose.sample(athlete,0)
	var contact_hand: Vector2 = (pose.direction(contact[0],1)+pose.direction(contact[1],1))*16
	check(contact_hand.y< -28,"overhead contact extends above the shoulder")
	athlete.swing = .48-.18
	var follow = pose.sample(athlete,0)
	var follow_hand: Vector2 = (pose.direction(follow[0],1)+pose.direction(follow[1],1))*16
	check(follow_hand.x< -15,"forehand follow-through crosses to the opposite side")
	athlete.stroke = "net"
	athlete.swing = .48
	var net_contact = pose.sample(athlete,0)
	athlete.swing = .48-.144
	var net_follow = pose.sample(athlete,0)
	check(absf(net_contact[2]-net_follow[2])<15,"net shot uses a short racket action")
	for stroke in ["overhead","net","drive","lift","serve"]:
		athlete.stroke = stroke
		athlete.swing = .00001
		var ending = pose.sample(athlete,0)
		athlete.swing = 0.0
		var ready = pose.sample(athlete,0)
		check(absf(ending[0]-ready[0])+absf(ending[1]-ready[1])+absf(ending[2]-ready[2])<.01,"stroke returns continuously to ready: "+stroke)
	var hip = Vector2(-6,-44)
	var ankle = Vector2(-14,-5)
	var knee: Vector2 = game.ATHLETE.knee(hip,ankle,Vector2(0,-.45),1)
	check(knee.x>=minf(hip.x,ankle.x) and knee.x<=maxf(hip.x,ankle.x),"front-facing knee does not bow sideways")
	if failures>0:
		print("MOTION FAILED: ",failures," / ",checks)
		game.queue_free()
		quit(1)
		return
	print("MOTION / P2 VIEW PASS: ",checks," checks; planted frames=",planted_frames,"; prediction drift=",max_landing_drift)
	game.queue_free()
	quit(0)

extends SceneTree
var game
var checks=0
var failures=0
var cases=[]
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func setup(index: int,avatar: String):
	game.start_game("local");game.mode="online";game.phase="rally";game.last_hit=1-index;game.total_hits=10;game.remote_move=Vector2.ZERO
	var side=1.0 if index==0 else -1.0
	var p=game.players[index];p.avatar=avatar;p.pos=Vector2(0,3*side);game.FOOTWORK.reset(p);p.buffer=.36;p.shot=0
	game.ball=Vector3(-1.2*side,1.75*side,1.25);game.velocity=Vector3(0,.8*side,-1.2)
	return p
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.set_physics_process(false);game.sound_on=false
	for avatar in ["male","female"]:
		for index in [0,1]:
			var side=1.0 if index==0 else -1.0
			for kind in ["net","smash"]:
				for offset in [-1.2,1.4]:
					var p=setup(index,avatar);var initial: Vector2=p.pos
					if kind=="net":game.ball.x=offset*side
					else:game.ball=Vector3(offset*side,2.25*side,1.85);game.velocity=Vector3(0,9*side,-5.5)
					check(not game._can_hit(index),"Distant incoming return starts outside physical racket reach")
					var hit=false;var peak=0.0
					for tick in range(43):
						game._update_player(index,1.0/120,false);peak=maxf(peak,p.rescue_weight)
						check(p.rescue_budget>=0 and p.rescue_budget<=.74,"Approach distance budget stays bounded")
						game._step_ball(1.0/120)
						if game.phase!="rally":break
						p.buffer=maxf(0,p.buffer-1.0/120)
						if p.buffer>0 and game._try_hit(index,0):hit=true;break
					check(hit,"Short lunge saves "+avatar+" P"+str(index+1)+" "+kind+" "+str(offset))
					check(peak>.2 and p.pos.distance_to(initial)<.82,"Save uses a visible bounded physical step")
					check(game.total_hits==11 and p.buffer==0,"One input produces exactly one return")
					game.arena.sync(game)
					check(game.arena.athletes[index].contact_error<.14,"Racket still contacts the real shuttle")
					var target=game.FOOTWORK.snapshot(p);var copy=p.duplicate(true);game.FOOTWORK.reset(copy);game.FOOTWORK.receive(copy,target)
					for tick in range(60):game.FOOTWORK.interpolate(copy,1.0/60)
					check(absf(copy.rescue_weight-p.rescue_weight)<.002 and absf(copy.rescue_x-p.rescue_x)<.002,"P2 receives lunge weight and direction")
					cases.append({"avatar":avatar,"player":index,"kind":kind,"offset":offset,"hit":hit,"travel":p.pos.distance_to(initial),"contact_error":game.arena.athletes[index].contact_error})
					p.buffer=0;p.charge=-1;p.vel=Vector2.ZERO
					for tick in range(100):game._update_player(index,1.0/120,false)
					check(p.rescue_weight<.01 and p.rescue_time==0,"Lunge recovers after return")
	for guard in ["far","high","landed","own_hit","opposite_half","no_input","away","jump","serve","ai"]:
		var p=setup(1,"male");var movement=Vector2.ZERO
		match guard:
			"far":game.ball.x=3.2
			"high":game.ball.z=3.5
			"landed":game.ball.z=.05
			"own_hit":game.last_hit=1
			"opposite_half":game.ball.y=1.5
			"no_input":p.buffer=0
			"away":movement=Vector2.LEFT
			"jump":p.jump=.3
			"serve":game.phase="serve"
		game._rescue_step(1,1.0/120,movement,guard=="ai")
		check(p.rescue_time==0,"Guard prevents unintended rescue: "+guard)
	var p=setup(1,"female")
	game._rescue_step(1,.01,Vector2.ZERO,false)
	check(p.rescue_time>0,"Valid input starts rescue")
	game._rescue_step(1,.01,Vector2.LEFT,false)
	check(p.rescue_time==0,"Moving away cancels ongoing rescue")
	game._rescue_step(1,.01,Vector2.ZERO,false)
	check(p.rescue_time==0,"Same incoming shot cannot restart rescue")
	game.total_hits+=2
	game._rescue_step(1,.01,Vector2.ZERO,false)
	check(p.rescue_time>0,"Next rally return can use a new rescue")
	p=setup(1,"male");p.buffer=0;p.charge=1
	var manual=Vector2(1,.3).normalized()
	var assisted=game._rescue_step(1,.01,manual,false)
	check(p.rescue_time>0,"Holding a shot key can prepare a rescue before release")
	check(assisted.distance_to(manual)<.001,"Manual approach direction remains unchanged")
	var file=FileAccess.open("res://artifacts/rescue-step-test.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"  ")+"\n");file.close()
	print("RESCUE STEP: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

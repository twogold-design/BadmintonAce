extends SceneTree
var checks=0
var failures=0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false
	for avatar in ["male","female"]:
		for index in [0,1]:
			for x in [-.35,-.50,-.70,-.80]:
				game.start_game("ai");game.phase="rally";game.last_hit=1-index
				var side=1.0 if index==0 else -1.0
				var p: Dictionary=game.players[index]
				p.avatar=avatar;p.pos=Vector2(0,5*side);p.vel=Vector2.ZERO;p.jump=0;p.swing=0;p.charge=0;p.stroke="overhead"
				game.FOOTWORK.reset(p)
				var contact=Vector3(x*side,4.7*side,2.05 if x<-.75 else 2.2);game.ball=contact
				for tick in range(60):game.FOOTWORK.update(p,index,1.0/120,true,true,contact,false)
				var backhand=x<-.65
				check(game.FOOTWORK.uses_backhand(p,index,contact)==backhand,"High nearby left shuttle stays forehand; wide left becomes backhand")
				check((p.body_turn*side<0)==backhand,"Preparation uses the same stroke side as contact")
				check(game._try_hit(index,0),"Both nearby overhead forehands and wide backhands remain playable")
				check(p.backhand==backhand and p.stroke=="overhead","Actual hit selects the intended overhead grip")
				var model=game.arena.athletes[index];model.animate(p,index,contact,0)
				check(model.contact_error<.003,"Selected overhead pose reaches actual shuttle with the string bed")
				var low=Vector3(-.35*side,4.7*side,1.1)
				check(game.FOOTWORK.uses_backhand(p,index,low),"Low left returns still use backhand")
				p.jump=.7
				check(game.FOOTWORK.uses_backhand(p,index,Vector3(-.35*side,4.7*side,2.2)),"Stroke choice uses shuttle height relative to jumping athlete")
	print("ROUND HEAD SELECTION: ",checks," checks; ",failures," failures")
	game.queue_free();quit(1 if failures else 0)

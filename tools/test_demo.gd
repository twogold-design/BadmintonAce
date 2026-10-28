extends SceneTree
var game
var failures=0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	if not ok:failures+=1;push_error(label)
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false
	game._disconnect();game.authenticated=true
	var min_pelvis=100.0;var max_foot=0.0;var contacts=0;var preparations=0
	for avatar in ["male","female"]:
		game.selected_avatar=avatar;game._build_menu()
		for frame in range(1800):
			var before=game.demo_leg
			game._physics_process(1.0/60)
			game.arena.sync(game)
			for i in range(2):
				var p: Dictionary=game.players[i]
				var model=game.arena.athletes[i]
				min_pelvis=minf(min_pelvis,model.poses[model.bones.pelvis].origin.y)
				max_foot=maxf(max_foot,maxf(p.pos.distance_to(p.foot_l),p.pos.distance_to(p.foot_r)))
				if p.preparation>.8:preparations+=1
				if before!=game.demo_leg and i==game.last_hit:
					contacts+=1
					check(p.has("contact") and p.swing>.44,"New demo return starts one real contact animation")
					check(game.ARENA_3D.ATHLETE_3D.can_reach(p,i,p.contact),"Demo contact stays within anatomical reach")
		game.start_game("ai");game.players[0].jump=.5;game.players[0].swing=.3
		game._build_menu();game.arena.sync(game)
		check(game.players[0].jump==0 and game.menu_time==0,"Returning to menu resets stale game pose and demo clock")
	check(min_pelvis>.70,"Menu players must not collapse into a seated pose")
	check(max_foot<.66,"Menu movement must advance planted feet with body")
	check(contacts>=40 and preparations>100,"Continuous demo includes repeated preparation and alternating returns")
	print("HOME DEMO: failures=",failures," contacts=",contacts," min pelvis=",min_pelvis," max foot offset=",max_foot)
	quit(1 if failures else 0)

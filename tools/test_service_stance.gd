extends SceneTree
var game
var failures=0
var checks=0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false
	for avatar in ["male","female"]:
		for server in [0,1]:
			for parity in [0,1]:
				for shot in [1,0]:
					game.start_game("ai");game.server=server;game.score[server]=parity;game._begin_serve()
					for p in game.players:p.avatar=avatar
					game.players[server].charge=shot
					for tick in range(120):
						for i in range(2):game._update_player(i,1.0/120,false)
					game.ball=game._serve_ball();game.phase_time=.6
					for index in range(2):
						var p: Dictionary=game.players[index]
						var serving=index==server
						var model=game.arena.athletes[index]
						model.animate(p,index,game.ball,0,serving)
						var frame=game.ARENA_3D.ATHLETE_3D.body_frame(p,index)
						check(p.lift_l<.001 and p.lift_r<.001,"Settled server and receiver keep both feet down")
						check(frame.rf.x-frame.lf.x>.30,"Service stance retains lateral space between feet")
						if not serving or shot==0:
							check(frame.lf.z<frame.rf.z-.25,"Receiver and forehand server place non-racket leg forward")
						else:
							check(frame.rf.z<frame.lf.z-.20,"Backhand server places racket leg slightly forward")
						var head: Vector3=model.basis.inverse()*(model.racket_center_world-model.position)
						var forearm: Vector3=(model.joint_points.hand_r-model.joint_points.lowerarm_r).normalized()
						var palm: Basis=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
						var lower: Basis=model.poses[model.bones.ace_forearm_r_4].basis*model.rests[model.bones.ace_forearm_r_4].basis.inverse()
						check(palm.x.dot(forearm)>cos(deg_to_rad(45)),"Service preparation avoids a sharply bent wrist")
						check(absf(lower.y.signed_angle_to((palm.y-forearm*palm.y.dot(forearm)).normalized(),forearm))<deg_to_rad(15),"Service preparation carries twist through forearm")
						if not serving:
							check(head.z<-.25 and head.y>1.4,"Receiver presents raised racket in front of body")
							check(frame.pelvis.y<model.rest_at("pelvis").y-.08,"Receiver bends knees rather than standing upright")
							check(frame.lean<-.05,"Receiver leans slightly forward from torso")
						elif shot==1:
							var error=model.racket_center_world.distance_to(Vector3(game.ball.x,game.ball.z,game.ball.y))
							check(error<.003,"Short-service string bed waits next to held shuttle")
						else:
							check(head.z>.15 and head.y<1.05,"Forehand server prepares racket low behind the body")
						var copied=p.duplicate(true);game.FOOTWORK.reset(copied)
						game.FOOTWORK.receive(copied,game.FOOTWORK.snapshot(p))
						for tick in range(60):game.FOOTWORK.interpolate(copied,1.0/60)
						check(absf(copied.receive_ready-p.receive_ready)<.001 and absf(copied.service_long-p.service_long)<.001,"Network motion preserves serving and receiving poses")
					check(game._try_hit(server,shot),"Both serve types launch from stance")
					var model=game.arena.athletes[server]
					model.animate(game.players[server],server,game.ball,0,false)
					check(model.contact_error<.003,"Racket meets actual service contact")
	print("SERVICE STANCES: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

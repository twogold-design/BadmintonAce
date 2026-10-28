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
		for index in [0,1]:
			for movement in [Vector2.ZERO,Vector2(4.5,0),Vector2(0,-4.5)]:
				game.start_game("ai")
				var p:Dictionary=game.players[index];game.FOOTWORK.reset(p)
				p.avatar=avatar;p.jump=0;p.swing=0;p.vel=movement*(1 if index==0 else -1)
				var model=game.arena.athletes[index]
				var previous=Basis.IDENTITY
				# Ordinary rally readiness through receiving stance: no flat-racket
				# branch may reappear as the receive flag fades after the serve.
				for tick in range(61):
					p.receive_ready=float(tick)/60
					model.animate(p,index,Vector3(0,0,2),0)
					var frame=game.ARENA_3D.ATHLETE_3D.body_frame(p,index)
					var elbow=frame.chest_basis.inverse()*(model.joint_points.lowerarm_r-model.joint_points.upperarm_r)
					check(elbow.x>.08 and elbow.z<.04,"Waiting racket elbow stays open and in front of shoulder")
					var forearm=(model.joint_points.hand_r-model.joint_points.lowerarm_r).normalized()
					var palm=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
					var lower=model.poses[model.bones.ace_forearm_r_4].basis*model.rests[model.bones.ace_forearm_r_4].basis.inverse()
					check(palm.x.dot(forearm)>cos(deg_to_rad(35)),"Waiting wrist follows forearm")
					check(absf(lower.y.signed_angle_to((palm.y-forearm*palm.y.dot(forearm)).normalized(),forearm))<deg_to_rad(15),"Waiting wrist does not carry residual forearm twist")
					var face=frame.chest_basis.inverse()*model.racket_basis_current.z
					check(face.x>.25 and face.z>.25,"Waiting basic forehand grip keeps the string bed oblique")
					var scale=model.rest_at("hand_r").distance_to(model.rest_at("middle_01_r"))/.1165
					var socket=model.joint_points.hand_r+palm*model.PALM_ANCHOR*scale
					var handle=model.joint_points.hand_r+model.racket_basis_current*(model.racket_mount_current+Vector3(0,.035,0))
					check(socket.distance_to(handle)<.001,"Ready V grip seats the handle in the palm")
					if tick>0:check(previous.get_rotation_quaternion().angle_to(palm.get_rotation_quaternion())<deg_to_rad(5),"Receive readiness changes wrist continuously")
					previous=palm
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
						for limb in ["l","r"]:
							var upper=frame.chest_basis.inverse()*(model.joint_points["lowerarm_"+limb]-model.joint_points["upperarm_"+limb])
							check(upper.x*(-1 if limb=="l" else 1)>.055,"Ready elbows retain space away from the ribs")
						check(p.lift_l<.001 and p.lift_r<.001,"Settled server and receiver keep both feet down")
						check(frame.rf.x-frame.lf.x>.30,"Service stance retains lateral space between feet")
						if not serving:
							check(frame.lf.z<frame.rf.z-.25,"Receiver places non-racket leg forward")
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
							check(forearm.y>sin(deg_to_rad(10)),"Receiver forearm slopes upward: "+avatar+" "+str(forearm.y))
							var face=frame.chest_basis.inverse()*model.racket_basis_current.z
							# Check the signed direction in the player's frame: an absolute
							# angle accepts the opposite grip rotation as equally correct.
							check(face.x>.25 and face.z>.25,"Receiver basic forehand grip turns in the correct direction: "+avatar+" "+str(face))
							var hand_scale=model.rest_at("hand_r").distance_to(model.rest_at("middle_01_r"))/.1165
							var socket=model.joint_points.hand_r+palm*model.PALM_ANCHOR*hand_scale
							var handle=model.joint_points.hand_r+model.racket_basis_current*(model.racket_mount_current+Vector3(0,.035,0))
							check(socket.distance_to(handle)<.001,"Receiving grip keeps handle seated inside palm")
							check(frame.pelvis.y<model.rest_at("pelvis").y-.08,"Receiver bends knees rather than standing upright")
							check(frame.lean<-.05,"Receiver leans slightly forward from torso")
						else:
							var error=model.racket_center_world.distance_to(Vector3(game.ball.x,game.ball.z,game.ball.y))
							check(error<.003,"Both backhand serves keep the string bed beside the held shuttle")
							check(head.z<-.25 and head.y<1.15,"High serve retains backhand preparation in front of body")
						var copied=p.duplicate(true);game.FOOTWORK.reset(copied)
						game.FOOTWORK.receive(copied,game.FOOTWORK.snapshot(p))
						for tick in range(60):game.FOOTWORK.interpolate(copied,1.0/60)
						check(absf(copied.receive_ready-p.receive_ready)<.001 and absf(copied.service_long-p.service_long)<.001,"Network motion preserves serving and receiving poses")
					check(game._try_hit(server,shot),"Both serve types launch from stance")
					check(game.players[server].backhand,"Short and high serves both use the backhand grip")
					var model=game.arena.athletes[server]
					model.animate(game.players[server],server,game.ball,0,false)
					check(model.contact_error<.003,"Racket meets actual service contact")
	print("SERVICE STANCES: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

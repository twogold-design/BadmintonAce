extends SceneTree
var game
var checks=0
var failures=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1;push_error(label)
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false
	game.start_game("ai")
	for avatar in ["male","female"]:
		for index in range(2):
			var side=1.0 if index==0 else -1.0
			var p: Dictionary=game.players[index]
			p.avatar=avatar;p.pos=Vector2(0,5*side);p.vel=Vector2.ZERO
			p.swing=0;p.charge=-1;p.buffer=0
			game.FOOTWORK.reset(p)
			var shuttle=Vector3(.2,4.5*side,3.2)
			for tick in range(60): game.FOOTWORK.update(p,index,1.0/120,true,true,shuttle,false)
			check(absf(p.body_turn)>.6 and absf(p.body_turn)<.9,"Rear receiver turns moderately without holding a key")
			var model=game.arena.athletes[index]
			for charge in [-1,0,1,2]:
				p.charge=charge
				for tick in range(30): game.FOOTWORK.update(p,index,1.0/120,true,true,shuttle,false)
				model.animate(p,index,shuttle,0)
				var forearm: Vector3=(model.joint_points.hand_r-model.joint_points.lowerarm_r).normalized()
				var elbow_to_shoulder: Vector3=(model.joint_points.upperarm_r-model.joint_points.lowerarm_r).normalized()
				var elbow_angle=rad_to_deg(acos(clampf(elbow_to_shoulder.dot(forearm),-1,1)))
				check(absf(elbow_angle-60)<.5,"Prepared elbow interior angle stays at 60 degrees for either avatar")
				check(model.joint_points.hand_r.distance_to(model.joint_points.upperarm_r)<.29,"Prepared hand stays close to the shoulder")
				var palm: Basis=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
				var lower: Basis=model.poses[model.bones.ace_forearm_r_4].basis*model.rests[model.bones.ace_forearm_r_4].basis.inverse()
				var wrist_twist=absf(lower.y.signed_angle_to((palm.y-forearm*palm.y.dot(forearm)).normalized(),forearm))
				check(wrist_twist<deg_to_rad(15),"Preparation does not leave forearm roll twisted at wrist seam")
				check(palm.x.dot(forearm)>cos(deg_to_rad(35)),"Prepared palm continues the forearm without a sharp wrist bend")
				var thumb: Vector3=model.poses[model.bones.thumb_01_r].origin
				var pinky: Vector3=model.poses[model.bones.pinky_01_r].origin
				check((thumb-pinky).dot(model.racket_basis_current.y)>.025,"Prepared grip keeps thumb above pinky")
				check(model.racket_basis_current.y.y>.9,"Ready racket stays upright for either player and all overhead shots")
				check(model.racket_center_world.y>model.position.y+model.joint_points.hand_r.y+.4,"Racket head is above the grip")
			p.charge=-1
			for tick in range(60): game.FOOTWORK.update(p,index,1.0/120,true,false,shuttle,false)
			check(p.preparation<.01 and absf(p.body_turn)<.01,"Preparation releases when the player is no longer receiving")
	for index in range(2):
		for parity in range(2):
			for dt in [1.0/120,1.0/60,1.0/30]:
				game.start_game("ai");game.server=index;game.score[index]=parity;game._begin_serve();game.phase_time=.5
				check(game._try_hit(index,1),"Short serve launches")
				var crossed=false
				var peak=game.ball.z
				for tick in range(240):
					var previous: Vector3=game.ball
					game._step_ball(dt);peak=maxf(peak,game.ball.z)
					if previous.y*game.ball.y<0:
						crossed=true
						var h=lerpf(previous.z,game.ball.z,absf(previous.y)/(absf(previous.y)+absf(game.ball.y)))
						check(h>1.59 and h<1.62,"Short serve clears tape by 4–7 cm")
					if game.phase!="rally": break
				check(crossed and game.last_reason=="落地得分","Short serve clears the net and lands legally")
				check(peak<1.85,"Short serve has a low apex")
				check(absf(game.ball.y)>1.98 and absf(game.ball.y)<3.0 and absf(game.ball.x)<2.59,"Short serve lands in diagonal service box")
	print("REAR PREPARATION / SHORT SERVE: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const FOOTWORK=preload("res://scripts/footwork.gd")
var failures=0
var cases=0
var maxima={}
var worst={}
func _initialize():call_deferred("run")
func record(key,value,label):
	if not maxima.has(key) or value>maxima[key]:maxima[key]=value;worst[key]=label
func run():
	var model=ATHLETE.new();root.add_child(model)
	for avatar in ["male","female"]:
		for index in [0,1]:
			var side=1.0 if index==0 else -1.0
			for stroke in ["net","lift"]:
				for x in [-1.0,-.8,-.6,-.35,0.0,.5,.8,1.0]:
					for depth in [-.15,-.35,-.7,-.95]:
						for height in [.6,1.05,1.4,1.8]:
							var p={"avatar":avatar,"pos":Vector2(0,2.5*side),"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"stroke":stroke}
							FOOTWORK.reset(p)
							var ball=Vector3(x*side,(2.5+depth)*side,height)
							p.backhand=FOOTWORK.uses_backhand(p,index,ball)
							if not ATHLETE.can_reach(p,index,ball):continue
							FOOTWORK.hit(p,index,ball,false)
							cases+=1
							var last_elbow=Vector3.ZERO
							var last_basis=Basis.IDENTITY
							var last_center=Vector3.ZERO
							var last_left=Vector3.ZERO
							var last_left_basis=Basis.IDENTITY
							for tick in range(61):
								p.swing=.48*(1-float(tick)/60)
								if tick>0:FOOTWORK.update(p,index,.008,true,false,ball,false)
								model.animate(p,index,ball,0)
								var label="%s P%d %s x%.2f z%.2f h%.2f frame%d"%[avatar,index+1,stroke,x,depth,height,tick]
								var shoulder=model.joint_points.upperarm_r
								var elbow=model.joint_points.lowerarm_r
								var forearm=(model.joint_points.hand_r-elbow).normalized()
								var body=ATHLETE.body_frame(p,index)
								var head=body.base.inverse()*(model.racket_center_world-model.position)
								var handle=head-model.racket_basis_current.y*ATHLETE.RACKET_CENTER
								for segment in [[shoulder,elbow,.04],[elbow,model.joint_points.hand_r,.03],[handle,head,.01],[head-model.racket_basis_current.x*.13,head+model.racket_basis_current.x*.13,.01]]:
									for sample in range(1,20):
										var local=body.chest_basis.inverse()*(segment[0].lerp(segment[1],sample/20.0)-body.chest)
										if local.y<-.40 or local.y>.07:continue
										var width=(.16 if avatar=="female" else .20)+segment[2]
										var depth_=(.12 if avatar=="female" else .14)+segment[2]
										record("torso_penetration",1-pow(local.x/width,2)-pow(local.z/depth_,2),label)

								record("racket_arm_straight",(elbow-shoulder).normalized().dot(forearm),label)
								var palm=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
								var upper=model.poses[model.bones.upperarm_r].basis*model.rests[model.bones.upperarm_r].basis.inverse()
								var free_basis=model.poses[model.bones.hand_l].basis*model.rests[model.bones.hand_l].basis.inverse()
								var free_lower=model.poses[model.bones.ace_forearm_l_4].basis*model.rests[model.bones.ace_forearm_l_4].basis.inverse()
								var free_direction=(model.joint_points.hand_l-model.joint_points.lowerarm_l).normalized()
								record("free_wrist_bend",rad_to_deg(acos(clampf((-free_basis.x).dot(free_direction),-1,1))),label)
								record("free_wrist_twist",rad_to_deg(absf(free_lower.y.signed_angle_to(free_basis.y,free_direction))),label)
								if tick<=24:
									# Authored palm normal is -Y; use its sign, not absolute roll.
									var facing=(-palm.y).dot(Vector3.DOWN if p.backhand else Vector3.UP)
									record("palm_wrong_way",-facing,label)
									var frame=ATHLETE.body_frame(p,index)
									var free_palm=frame.chest_basis.inverse()*(-free_basis.y)
									record("free_palm_up",free_palm.y,label)
									record("free_palm_not_forward",free_palm.z,label)
									var racket_local=frame.base.inverse()*(model.racket_center_world-model.position)
									var body_local=frame.chest_basis.inverse()*(racket_local-frame.chest)
									record("racket_wrong_side",body_local.x if p.backhand else -body_local.x,label)
									var free=frame.chest_basis.inverse()*(model.joint_points.hand_l-model.joint_points.upperarm_l)
									var arm_length=model.length_between("upperarm_l","lowerarm_l")+model.length_between("lowerarm_l","hand_l")
									record("free_reach",free.length()/arm_length,label)
									var free_upper=(model.joint_points.lowerarm_l-model.joint_points.upperarm_l).normalized()
									record("free_straight",free_upper.dot(free_direction),label)
									var local_contact=frame.chest_basis.inverse()*(Vector3(x,height,depth)-shoulder)
									if not p.backhand and local_contact.z<-.45 and height<shoulder.y+.05:
										var held=frame.chest_basis.inverse()*(model.joint_points.hand_r-shoulder)
										record("forehand_tucked",held.z,label)
									record("free_arm_closed",free.x/arm_length,label)
									record("free_arm_low",-free.y/arm_length,label)
								if forearm.dot(-upper.z)<=0:failures+=1;push_error("Reversed elbow: "+label)
								if tick==0:
									record("contact_error",model.contact_error,label)
									var ball_local=body.chest_basis.inverse()*(Vector3(x,height,depth)-body.chest)
									var close_body=absf(ball_local.x)<.40 and ball_local.z>-.35
									record("body_contact_error" if close_body else "regular_contact_error",model.contact_error,label)
								record("wrist_bend",rad_to_deg(acos(clampf(palm.x.dot(forearm),-1,1))),label)
								if tick>0:
									record("elbow_step",elbow.distance_to(last_elbow),label)
									record("racket_turn",rad_to_deg(last_basis.get_rotation_quaternion().angle_to(model.racket_basis_current.get_rotation_quaternion())),label)
									record("racket_step",model.racket_center_world.distance_to(last_center),label)
									record("free_arm_step",model.joint_points.hand_l.distance_to(last_left),label)
									record("free_hand_turn",rad_to_deg(last_left_basis.get_rotation_quaternion().angle_to(free_basis.get_rotation_quaternion())),label)
								last_elbow=elbow;last_basis=model.racket_basis_current;last_center=model.racket_center_world
								last_left=model.joint_points.hand_l
								last_left_basis=free_basis
	for bound in [["torso_penetration",0.0],["regular_contact_error",ATHLETE.NET_VISUAL_TOLERANCE],["body_contact_error",ATHLETE.NET_BODY_VISUAL_TOLERANCE],["wrist_bend",20.0],["elbow_step",.07],["racket_turn",25.0],["racket_step",.15],["palm_wrong_way",-.15],["racket_wrong_side",0.0],["forehand_tucked",-.15],["racket_arm_straight",cos(deg_to_rad(44.5))]]:
		if maxima[bound[0]]>bound[1]:failures+=1;push_error(bound[0]+": "+str(maxima[bound[0]])+" "+worst[bound[0]])
	for bound in [["free_reach",.88],["free_straight",.75],["free_arm_step",.07],["free_wrist_bend",5.0],["free_wrist_twist",5.0],["free_hand_turn",25.0],["free_palm_up",.40],["free_palm_not_forward",-.08]]:
		if maxima[bound[0]]>bound[1]:failures+=1;push_error(bound[0]+": "+str(maxima[bound[0]])+" "+worst[bound[0]])
	if cases<80:failures+=1;push_error("Insufficient playable net cases")
	# Close body balls retain a playable response through the existing queued
	# step: make room for the racket instead of accepting an inverted wrist.
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false
	for avatar in ["male","female"]:
		for index in [0,1]:
			game.start_game("ai");game.phase="rally";game.last_hit=1-index
			var side=1.0 if index==0 else -1.0
			var p:Dictionary=game.players[index]
			p.avatar=avatar;p.pos=Vector2(0,3*side);p.vel=Vector2.ZERO;p.jump=0;p.charge=-1;p.shot=1;p.buffer=.3
			FOOTWORK.reset(p);game.ball=Vector3(0,3*side,1.2);game.velocity=Vector3.ZERO
			var touched=false
			for tick in range(30):
				game._update_player(index,.008,false)
				if game._try_hit(index,1):touched=true;break
			if not touched or p.pos.distance_to(Vector2(0,3*side))>.6:
				failures+=1;push_error("Close net return must create room within one short step: "+avatar+" P"+str(index+1))
	game.queue_free()
	var file=FileAccess.open("res://artifacts/net-motion-test.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":cases,"frames_per_case":61,"failures":failures,"maxima":maxima,"worst":worst},"  ")+"\n")
	print("NET MOTION: ",cases," cases; ",failures," failures")
	quit(1 if failures else 0)

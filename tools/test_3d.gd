extends SceneTree
var game
var checks = 0
var failures = 0
func _initialize(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.start_game("ai")
	var accepted = 0
	var rejected = 0
	for avatar in ["male","female"]:
		for index in range(2):
			var p: Dictionary = game.players[index]
			var side = 1 if index==0 else -1
			var model = game.arena.athletes[index]
			p.avatar = avatar
			p.pos = Vector2(0,3.3*side)
			for jump in [0.0,.55]:
				for turn in [0.0,.85*side]:
					for x in [-1.6,-.5,.4,1.6]:
						for height in [.5,1.2,1.8,2.4,2.8,3.8]:
							game.FOOTWORK.reset(p)
							p.jump = jump
							p.body_turn = turn
							p.hip_turn = turn*.6
							p.stroke = "overhead" if height>1.8 else "lift"
							var contact = Vector3(x,3.0*side,height+jump)
							p.backhand = game.FOOTWORK.uses_backhand(p,index,contact)
							game.phase = "rally"
							game.last_hit = 1-index
							game.ball = contact
							if not game._can_hit(index):
								rejected += 1
								continue
							accepted += 1
							game.FOOTWORK.hit(p,index,contact,false)
							model.animate(p,index,contact,0)
							check(model.contact_error<(model.NET_CONTACT_TOLERANCE if p.stroke in ["net","lift"] else .002),"Contact stays within the visual allowance without distorting the rig")
							var thumb: Vector3 = model.poses[model.bones.thumb_01_r].origin
							var pinky: Vector3 = model.poses[model.bones.pinky_01_r].origin
							check((thumb-pinky).dot(model.racket_basis_current.y)>.025,"Thumb side points toward racket head for either avatar and camera side")
							var actual_racket: Transform3D = model.poses[model.bones.hand_r]*model.racket.transform
							check((model.position+model.basis*(actual_racket*Vector3(0,model.RACKET_CENTER,0))).distance_to(model.racket_center_world)<.001,"Rendered racket matches reported position")
							for limb in ["l","r"]:
								var points: Dictionary = model.joint_points
								var upper_id: int = model.bones["upperarm_"+limb]
								var arm_frame: Basis = model.poses[upper_id].basis*model.rests[upper_id].basis.inverse()
								var forearm: Vector3 = (points["hand_"+limb]-points["lowerarm_"+limb]).normalized()
								check(forearm.dot(-arm_frame.z)>0,"Forearm bends toward the authored elbow crease, never backward")
								check(absf(points["upperarm_"+limb].distance_to(points["lowerarm_"+limb])-model.length_between("upperarm_"+limb,"lowerarm_"+limb))<.001,"Upper arm length fixed")
								check(absf(points["lowerarm_"+limb].distance_to(points["hand_"+limb])-model.length_between("lowerarm_"+limb,"hand_"+limb))<.001,"Forearm length fixed")
								check(absf(points["thigh_"+limb].distance_to(points["calf_"+limb])-model.length_between("thigh_"+limb,"calf_"+limb))<.001,"Thigh length fixed")
								check(absf(points["calf_"+limb].distance_to(points["foot_"+limb])-model.length_between("calf_"+limb,"foot_"+limb))<.001,"Shin length fixed")
								check(absf(points["foot_"+limb].y-model.rest_at("foot_"+limb).y)<.002,"Planted foot stays on floor relative to jump")
			check(model.skeleton is Skeleton3D and model.skeleton.get_bone_count()>=65,"Real articulated skeleton")
	check(accepted>40 and rejected>40,"Reach suite includes valid and impossible contacts")
	game.start_game("ai")
	for index in range(2):
		game.server=index
		game._begin_serve()
		game.arena.sync(game)
		var p: Dictionary = game.players[index]
		check(p.pos.distance_to(Vector2(game.ball.x,game.ball.y))>.3,"Serve is held in front of athlete")
		check(not p.has("contact"),"New serve clears stale stroke contact")
	print("3D RIG: ",checks," checks; ",failures," failures; accepted=",accepted," rejected=",rejected)
	game.queue_free()
	quit(1 if failures else 0)

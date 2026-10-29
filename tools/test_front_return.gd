extends SceneTree
const A=preload("res://scripts/athlete_3d.gd")
const F=preload("res://scripts/footwork.gd")
var failures=0
var cases=0
var worst_turn=0.0
var worst_penetration=-INF
var worst_wrist=0.0
var minimum_flex=180.0
func check(ok:bool,label:String):
	if not ok:
		failures+=1
		if failures<12:push_error(label)
func _initialize():call_deferred("run")
func run():
	var model=A.new();root.add_child(model)
	for avatar in ["male","female"]:
		for index in [0,1]:
			var side=1.0 if index==0 else -1.0
			for stroke in ["net","lift","drive"]:
				for x in [-.8,-.35,0.0,.35,.8]:
					for height in [1.05,1.65,1.82]:
						for move in [Vector2.ZERO,Vector2(0,-4.5*side),Vector2(4.5*side,0)]:
							var p={"avatar":avatar,"pos":Vector2(0,1.7*side),"vel":move,"jump":0.0,"swing":0.0,"charge":-1,"shot":1,"buffer":0.0,"dash":0.0,"landing":0.0,"stroke":stroke}
							F.reset(p)
							var ball=Vector3(x*side,.9*side,height)
							p.backhand=F.uses_backhand(p,index,ball)
							if not A.can_reach(p,index,ball,stroke):continue
							F.hit(p,index,ball,false);cases+=1
							# Rendering may first see the stroke after several physics
							# steps; moving away must not invalidate the whole animation.
							for tick in range(4):
								p.swing-=1.0/120;p.pos+=move/120
								F.update(p,index,1.0/120,true,false,ball,false)
							model.animate(p,index,ball,0)
							check(model.stroke_solution.get("valid",false),"Delayed front return must have a natural visual solution")
							if stroke in ["net","lift"]:inspect_net(model,p,index)
							var previous=model.racket_basis_current
							var previous_elbow=model.joint_points.lowerarm_r
							for tick in range(1,58):
								p.swing=maxf(0,.48-(tick+4)/120.0);p.pos+=move/120
								F.update(p,index,1.0/120,true,false,ball,false)
								model.animate(p,index,ball,tick/120.0)
								if stroke in ["net","lift"]:inspect_net(model,p,index)
								var turn=rad_to_deg(previous.get_rotation_quaternion().angle_to(model.racket_basis_current.get_rotation_quaternion()))
								worst_turn=maxf(worst_turn,turn)
								check(turn<20,"Front return must not flip its racket: %s P%d %s x%s h%s move%s tick%d angle%.1f"%[avatar,index+1,stroke,x,height,move,tick,turn])
								check(previous_elbow.distance_to(model.joint_points.lowerarm_r)<.07,"Front return elbow stays on a continuous path")
								previous=model.racket_basis_current;previous_elbow=model.joint_points.lowerarm_r
	check(cases>=300,"Cover both genders, both ends, all front shots and moving contact")
	check(worst_penetration<=0,"Moving net strokes must stay outside the shirt")
	check(worst_wrist<20,"Moving net strokes keep a relaxed wrist")
	check(minimum_flex>44.5,"Moving net strokes retain a bent elbow")
	var result={"torso_penetration":worst_penetration,"wrist_bend_degrees":worst_wrist,"minimum_elbow_flex_degrees":minimum_flex,"cases":cases,"failures":failures,"max_racket_frame_turn_degrees":worst_turn}
	FileAccess.open("res://artifacts/front-return-test.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("FRONT RETURN: ",result);quit(1 if failures else 0)

func inspect_net(model,p,index):
	var frame=A.body_frame(p,index)
	var shoulder=model.joint_points.upperarm_r
	var elbow=model.joint_points.lowerarm_r
	var hand=model.joint_points.hand_r
	var lower=(hand-elbow).normalized()
	var palm=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
	worst_wrist=maxf(worst_wrist,rad_to_deg(acos(clampf(palm.x.dot(lower),-1,1))))
	minimum_flex=minf(minimum_flex,rad_to_deg((elbow-shoulder).angle_to(lower)))
	var head=frame.base.inverse()*(model.racket_center_world-model.position)
	var handle=head-model.racket_basis_current.y*A.RACKET_CENTER
	for segment in [[shoulder,elbow,.04],[elbow,hand,.03],[handle,head,.01],[head-model.racket_basis_current.x*.13,head+model.racket_basis_current.x*.13,.01]]:
		for sample in range(1,20):
			var local=frame.chest_basis.inverse()*(segment[0].lerp(segment[1],sample/20.0)-frame.chest)
			if local.y<-.40 or local.y>.07:continue
			var width=(.16 if p.avatar=="female" else .20)+segment[2]
			var depth_=(.12 if p.avatar=="female" else .14)+segment[2]
			worst_penetration=maxf(worst_penetration,1-pow(local.x/width,2)-pow(local.z/depth_,2))

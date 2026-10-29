extends SceneTree
const FOOTWORK=preload("res://scripts/footwork.gd")
const ATHLETE=preload("res://scripts/athlete_3d.gd")
var checks=0
var failures=0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func run():
	var model=ATHLETE.new();root.add_child(model)
	for avatar in ["male","female"]:
		for index in [0,1]:
			for speed in [2.0,4.5,10.5]:
				for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,-1).normalized(),Vector2(-1,-1).normalized(),Vector2(1,1).normalized(),Vector2(-1,1).normalized()]:
					var p={"avatar":avatar,"pos":Vector2.ZERO,"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":false}
					FOOTWORK.reset(p)
					var max_pitch=0.0
					for tick in range(120):
						p.vel=p.vel.move_toward(direction*speed,32.0/120);p.pos+=p.vel/120.0
						FOOTWORK.update(p,index,1.0/120,true,false,Vector3.ZERO,false)
						max_pitch=maxf(max_pitch,maxf(p.heel_l,p.heel_r))
						if tick%6!=0:continue
						model.animate(p,index,Vector3.ZERO,0)
						var frame=ATHLETE.body_frame(p,index)
						for side in ["l","r"]:
							var slot=side if index==0 else ("r" if side=="l" else "l")
							var world: Vector2=p["foot_"+slot]
							var anchor: Vector3=frame.base.inverse()*Vector3(world.x-p.pos.x,model.rest_at("foot_"+side).y+p["lift_"+slot],world.y-p.pos.y)
							var yaw: Basis=frame.foot_bases["toe_"+side]
							var expected=anchor+yaw*(model.rest_at("ball_"+side)-model.rest_at("foot_"+side))
							var toe: Transform3D=model.poses[model.bones["ball_"+side]]
							check(toe.origin.distance_to(expected)<.002,"Heel rise retains forefoot contact instead of lifting the whole shoe")
							var toe_basis=toe.basis*model.rests[model.bones["ball_"+side]].basis.inverse()
							check(toe_basis.y.dot(Vector3.UP)>.999,"Forefoot stays level while shoe bends at the ball joint")
							var ankle: Vector3=model.joint_points["foot_"+side]
							check(ankle.y>=anchor.y-.001,"Heel roll never drives the ankle below its neutral height")
							var hip:Vector3=model.joint_points["thigh_"+side]
							var knee:Vector3=model.joint_points["calf_"+side]
							var upper=(knee-hip).normalized()
							var lower=(ankle-knee).normalized()
							check(upper.angle_to(lower)>=deg_to_rad(17.9),"Running knee retains flexion instead of locking at full reach")
							var rest_upper=(model.rest_at("calf_"+side)-model.rest_at("thigh_"+side)).normalized()
							var rest_lower=(model.rest_at("foot_"+side)-model.rest_at("calf_"+side)).normalized()
							var rest_hinge=rest_upper.cross(rest_lower).normalized()
							var hinge=upper.cross(lower).normalized()
							for bone in ["thigh_"+side,"calf_"+side]:
								var rotation_:Basis=model.poses[model.bones[bone]].basis*model.rests[model.bones[bone]].basis.inverse()
								check((rotation_*rest_hinge).dot(hinge)>.9999,"Thigh and shin skin rotate about the same knee hinge")
							var axis=(ankle-hip).normalized()
							var knee_bend=(knee-hip-axis*(knee-hip).dot(axis)).normalized()
							var toe_forward=-yaw.z
							var expected_bend=(toe_forward-axis*toe_forward.dot(axis)).normalized()
							check(knee_bend.dot(expected_bend)>.9999,"Knee bends forward in the toe's plane, never inward or backward")
							var local_toe=Basis(Vector3.UP,float(frame.hip_turn)).inverse()*toe_forward
							check(local_toe.x*(-1 if side=="l" else 1)>.05,"Lateral reach does not turn toes inward")
						check(p.bounce>=-.015 and p.bounce<=.001,"Body spring stays small instead of bouncing vertically")
					check(max_pitch>.15 and max_pitch<=.4,"Locomotion includes a visible controlled heel rise")
					var copy=p.duplicate(true);FOOTWORK.reset(copy);FOOTWORK.receive(copy,FOOTWORK.snapshot(p))
					for tick in range(60):FOOTWORK.interpolate(copy,1.0/60)
					check(absf(copy.heel_l-p.heel_l)<.001 and absf(copy.heel_r-p.heel_r)<.001,"P2 receives both ankle phases")
					p.vel=Vector2.ZERO
					for tick in range(90):FOOTWORK.update(p,index,1.0/120,true,false,Vector3.ZERO,false)
					check(p.heel_l<.001 and p.heel_r<.001 and absf(p.bounce)<.001,"Stopping restores a grounded stance")
	print("FOREFOOT MOVEMENT: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

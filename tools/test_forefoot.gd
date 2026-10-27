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
				for direction in [Vector2.RIGHT,Vector2(0,-1),Vector2(0,1)]:
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

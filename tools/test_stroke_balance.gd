extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const FOOTWORK=preload("res://scripts/footwork.gd")
var failures=0
var checks=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1;push_error(label)
func run():
	for avatar in ["male","female"]:
		for index in [0,1]:
			var side=1.0 if index==0 else -1.0
			var p={"avatar":avatar,"pos":Vector2(0,5*side),"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":0,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":false}
			FOOTWORK.reset(p)
			var ball=Vector3(.3*side,4.8*side,2.4)
			for tick in range(120): FOOTWORK.update(p,index,1.0/120,true,true,ball,false)
			var start=ATHLETE.body_frame(p,index)
			check(start.pelvis.distance_squared_to(start.rf)<start.pelvis.distance_squared_to(start.lf),"Preparation loads anatomical right leg")
			var feet=[p.foot_l,p.foot_r]
			var previous: Vector3=start.pelvis
			p.charge=-1;p.stroke="overhead";FOOTWORK.hit(p,index,ball,false)
			for tick in range(90):
				p.swing=maxf(0,p.swing-1.0/120)
				FOOTWORK.update(p,index,1.0/120,true,false,ball,false)
				var frame=ATHLETE.body_frame(p,index)
				check(frame.pelvis.distance_to(previous)<.025,"Pelvis recovers without a positional snap")
				previous=frame.pelvis
				check(Vector2(frame.pelvis.x,frame.pelvis.z).length()<=.091,"Weight shift stays below nine centimetres")
				check(frame.pelvis.y>.80,"Grounded stroke keeps hips stable above the stance")
				if p.swing>0:
					check(p.foot_l.distance_to(feet[0])<.0001 and p.foot_r.distance_to(feet[1])<.0001,"Grounded stroke keeps both support anchors planted")
					check(p.lift_l<.001 and p.lift_r<.001,"Grounded stroke does not lift the receiving support leg")
				if tick in [24,32]:
					check(frame.pelvis.distance_squared_to(frame.lf)<frame.pelvis.distance_squared_to(frame.rf),"Follow-through transfers weight to anatomical left leg")
					var a=Vector2(frame.lf.x,frame.lf.z)
					var b=Vector2(frame.rf.x,frame.rf.z)
					var hip=Vector2(frame.pelvis.x,frame.pelvis.z)
					var t=(hip-a).dot(b-a)/(b-a).length_squared()
					check(t>.15 and t<.85 and hip.distance_to(a.lerp(b,t))<.02,"Pelvis remains inside the planted support base")
	print("STROKE BALANCE: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

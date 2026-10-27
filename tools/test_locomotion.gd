extends SceneTree
const FOOTWORK=preload("res://scripts/footwork.gd")
const ATHLETE=preload("res://scripts/athlete_3d.gd")
var failures=0
func _initialize():call_deferred("run")
func run():
	var report=[]
	for avatar in ["male","female"]:
		for index in [0,1]:
			for speed in [2.0,4.5,10.5]:
				for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
					var p={"avatar":avatar,"pos":Vector2.ZERO,"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":false}
					FOOTWORK.reset(p)
					var min_width=10.0;var min_hip=10.0;var max_offset=0.0;var max_mid=0.0;var max_foot_speed=0.0;var air=0;var plants=0;var contacts=0;var worst={}
					for frame in range(240):
						var previous=[p.foot_l,p.foot_r];var previous_lifts=[p.lift_l,p.lift_r]
						var requested=direction*speed if frame<120 else (-direction*speed if frame<180 else Vector2.ZERO)
						p.vel=p.vel.move_toward(requested,32.0/120)
						p.pos+=p.vel/120.0
						FOOTWORK.update(p,index,1.0/120,true,false,Vector3(0,0,2),false)
						var across=Vector2(cos(p.hip_turn),(1 if index==0 else -1)*sin(p.hip_turn))
						min_width=minf(min_width,(p.foot_r-p.foot_l).dot(across))
						min_hip=minf(min_hip,ATHLETE.body_frame(p,index).pelvis.y)
						max_offset=maxf(max_offset,maxf(p.foot_l.distance_to(p.pos),p.foot_r.distance_to(p.pos)))
						max_mid=maxf(max_mid,((p.foot_l+p.foot_r)*.5).distance_to(p.pos))
						var feet=[p.foot_l,p.foot_r];var lifts=[p.lift_l,p.lift_r]
						if lifts[0]>.005 and lifts[1]>.005:air+=1
						for leg in range(2):
							var foot_speed: float=feet[leg].distance_to(previous[leg])*120
							if foot_speed>max_foot_speed:worst={"frame":frame,"leg":leg,"old":str(previous[leg]),"new":str(feet[leg]),"body":str(p.pos),"velocity":str(p.vel),"phase":p.gait_phase,"style":p.footwork}
							max_foot_speed=maxf(max_foot_speed,foot_speed)
							if lifts[leg]<.001 and previous_lifts[leg]<.001:
								contacts+=1
								if feet[leg].distance_to(previous[leg])<.001:plants+=1
					var result={"avatar":avatar,"index":index,"speed":speed,"direction":[direction.x,direction.y],"min_width":min_width,"min_hip":min_hip,"max_offset":max_offset,"max_mid":max_mid,"max_foot_speed":max_foot_speed,"air_frames":air,"plant_ratio":float(plants)/maxi(1,contacts)}
					result.worst=worst
					report.append(result)
					if min_width<.17 or min_hip<.72 or max_offset>.60 or max_mid>.30 or max_foot_speed>3.6+speed*2 or float(plants)/maxi(1,contacts)<.75:
						failures+=1;print("GAIT FAIL ",result)
	FileAccess.open("res://artifacts/locomotion-test.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":report},"  "))
	print("LOCOMOTION: ",report.size()," movement / reversal / stop cases; failures=",failures)
	quit(1 if failures else 0)

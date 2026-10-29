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
	# Include the previously untested preparation -> first impact frame.
	# Transport the hinge with the arm's elevation to distinguish a legitimate
	# shoulder swing from an axial half-turn that inverts the visible elbow.
	for avatar in ["male","female"]:
		for index in [0,1]:
			var side=1.0 if index==0 else -1.0
			for x in [-.4,0.0,.4,.8]:
				for height in [1.95,2.1,2.3]:
					var p={"avatar":avatar,"pos":Vector2(0,5*side),"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":2,"shot":2,"buffer":0.0,"dash":0.0,"landing":0.0,"stroke":"overhead","backhand":false}
					FOOTWORK.reset(p)
					var ball=Vector3(x*side,4.7*side,height)
					for tick in range(30):FOOTWORK.update(p,index,.008,true,true,ball,false)
					model.animate(p,index,ball,0)
					var before=model.poses[model.bones.upperarm_r].basis*model.rests[model.bones.upperarm_r].basis.inverse()
					if not ATHLETE.can_reach(p,index,ball):continue
					FOOTWORK.hit(p,index,ball,false);model.animate(p,index,ball,0)
					var after=model.poses[model.bones.upperarm_r].basis*model.rests[model.bones.upperarm_r].basis.inverse()
					var transported=Basis(Quaternion(before.x,after.x))*before.y
					record("impact_elbow_axial_turn",rad_to_deg(absf(transported.signed_angle_to(after.y,after.x))),"%s P%d x%.2f h%.2f"%[avatar,index+1,x,height])
	for avatar in ["male","female"]:
		for index in [0,1]:
			var side=1.0 if index==0 else -1.0
			for x in [-.35,.35,.75]:
				for height in [2.05,2.35]:
					for jump in [0.0,.55]:
						var p={"avatar":avatar,"pos":Vector2(0,5*side),"vel":Vector2.ZERO,"jump":jump,"swing":0.0,"charge":-1,"shot":2,"buffer":0.0,"dash":0.0,"landing":0.0,"stroke":"overhead","backhand":false}
						FOOTWORK.reset(p);p.body_turn=.65*side;p.hip_turn=.4*side
						var ball=Vector3(x*side,4.7*side,height+jump)
						if not ATHLETE.can_reach(p,index,ball):continue
						FOOTWORK.hit(p,index,ball,false);cases+=1
						var last_elbow=Vector3.ZERO
						var last_basis=Basis.IDENTITY
						for tick in range(61):
							p.swing=.48*(1-float(tick)/60)
							if tick>0:FOOTWORK.update(p,index,.008,true,false,ball,false)
							model.animate(p,index,ball,0)
							var label="%s P%d x%.2f h%.2f jump%.2f frame%d"%[avatar,index+1,x,height,jump,tick]
							var frame=ATHLETE.body_frame(p,index)
							var elbow=model.joint_points.lowerarm_r
							var forearm=(model.joint_points.hand_r-elbow).normalized()
							var hand=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
							if tick==0:record("contact_error",model.contact_error,label)
							if tick==24:
								var left_shoulder=model.joint_points.upperarm_l
								record("shoulder_not_leading",frame.shoulder.z-left_shoulder.z,label)
								record("missing_chest_follow",frame.lean,label)
								var center=frame.chest_basis.inverse()*(frame.base.inverse()*(model.racket_center_world-model.position)-frame.chest)
								var shaft=frame.chest_basis.inverse()*model.racket_basis_current.y
								record("release_x",center.x,label);record("release_y",center.y,label)
								record("shaft_x",shaft.x,label);record("shaft_y",shaft.y,label)
								record("forearm_rotation",rad_to_deg(Vector3(model.stroke_solution.hand_relative.y).signed_angle_to(model.stroke_solution.release.relative.y,Vector3.RIGHT)),label)
								record("forearm_rotation_size",absf(rad_to_deg(Vector3(model.stroke_solution.hand_relative.y).signed_angle_to(model.stroke_solution.release.relative.y,Vector3.RIGHT))),label)
							record("wrist_bend",rad_to_deg(acos(clampf(hand.x.dot(forearm),-1,1))),label)
							if tick>0:
								record("elbow_step",elbow.distance_to(last_elbow),label)
								record("racket_turn",rad_to_deg(last_basis.get_rotation_quaternion().angle_to(model.racket_basis_current.get_rotation_quaternion())),label)
							last_elbow=elbow;last_basis=model.racket_basis_current
	for bound in [["contact_error",.003],["wrist_bend",55.0],["elbow_step",.07],["racket_turn",25.0],["release_x",-.25],["release_y",-.30],["shaft_x",-.1],["shaft_y",-.1],["shoulder_not_leading",-.10],["missing_chest_follow",-.04],["forearm_rotation",-8.0],["forearm_rotation_size",35.0],["impact_elbow_axial_turn",60.0]]:
		if maxima[bound[0]]>bound[1]:failures+=1;push_error(bound[0]+": "+str(maxima[bound[0]])+" "+worst[bound[0]])
	if cases<24:failures+=1;push_error("Insufficient playable overhead cases")
	var file=FileAccess.open("res://artifacts/overhead-release-test.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":cases,"frames_per_case":61,"failures":failures,"maxima":maxima,"worst":worst},"  ")+"\n")
	print("OVERHEAD RELEASE: ",cases," cases; ",failures," failures")
	quit(1 if failures else 0)

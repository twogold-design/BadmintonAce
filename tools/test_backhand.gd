extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const FOOTWORK=preload("res://scripts/footwork.gd")
var checks=0
var failures=0
var min_forward=1.0
var max_twist=0.0
var high_contacts=0
var max_contact_roll=0.0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func run():
	var model=ATHLETE.new();root.add_child(model)
	for avatar in ["male","female"]:
		for index in [0,1]:
			model.build(avatar,index)
			var side=1.0 if index==0 else -1.0
			for stroke in ["net","lift","drive","overhead"]:
				for offset in [-.35,-.65,-.85]:
					var p={"avatar":avatar,"pos":Vector2(0,3*side),"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":true,"stroke":stroke}
					FOOTWORK.reset(p)
					var height=2.2 if stroke=="overhead" else (1.5 if stroke=="drive" else 1.0)
					var contact=Vector3(offset*side,2.7*side,height)
					if not ATHLETE.can_reach(p,index,contact):continue
					FOOTWORK.hit(p,index,contact,false)
					check(absf(p.body_turn)>.6 and absf(p.hip_turn)>.3,"Backhand impact turns shoulder and pelvis toward the shuttle")
					for tick in range(21):
						p.swing=.48*(1-float(tick)/21)
						if tick>0:FOOTWORK.update(p,index,.48/21,true,false,contact,false)
						model.animate(p,index,contact,0)
						var forearm=(model.joint_points.hand_r-model.joint_points.lowerarm_r).normalized()
						var hand_frame=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
						var arm_frame=model.poses[model.bones.ace_forearm_r_4].basis*model.rests[model.bones.ace_forearm_r_4].basis.inverse()
						var forward=forearm.dot(hand_frame.x);min_forward=minf(min_forward,forward)
						var palm=hand_frame.y-forearm*hand_frame.y.dot(forearm)
						var twist=absf(arm_frame.y.signed_angle_to(palm.normalized(),forearm));max_twist=maxf(max_twist,twist)
						check(forward>cos(deg_to_rad(50.0)),"Backhand hand stays within 50 degrees of the forearm, never folds back")
						check(twist<.8,"Backhand wrist must not absorb a reversed forearm roll")
						var hand_scale=model.rest_at("hand_r").distance_to(model.rest_at("middle_01_r"))/.1165
						var expected=model.poses[model.bones.hand_r].origin+hand_frame*ATHLETE.PALM_ANCHOR*hand_scale
						var rendered=model.poses[model.bones.hand_r]*model.racket.transform
						check((rendered*Vector3(0,.035,0)).distance_to(expected)<.0005,"Actual handle centre stays inside the palm through the backhand")
						var previous=model.poses[model.bones.lowerarm_r].basis*model.rests[model.bones.lowerarm_r].basis.inverse()
						for segment in range(1,5):
							var id=model.bones["ace_forearm_r_"+str(segment)]
							var current=model.poses[id].basis*model.rests[id].basis.inverse()
							check(previous.get_rotation_quaternion().angle_to(current.get_rotation_quaternion())<PI/4+.002,"Forearm skin roll is distributed in small increments")
							previous=current

						if tick==0:
							check(model.contact_error<.002,"Backhand grip change preserves actual string-bed contact")
							var hinge=(model.joint_points.lowerarm_r-model.joint_points.upperarm_r).normalized().cross(forearm).normalized()
							var roll=absf(hinge.signed_angle_to(palm.normalized(),forearm));max_contact_roll=maxf(max_contact_roll,roll)
							check(roll<1.81,"Impact does not force a half-turn of the forearm")
							if stroke=="overhead":
								high_contacts+=1
								check(hand_frame.y.z<-.1,"High backhand presents the back of the hand to the net, not the palm")
	check(high_contacts>=4,"High backhands are actually tested for both genders and player slots")
	var report=FileAccess.open("res://artifacts/backhand-test.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"min_hand_forearm_dot":min_forward,"max_wrist_twist_degrees":rad_to_deg(max_twist),"max_contact_forearm_roll_degrees":rad_to_deg(max_contact_roll),"high_backhand_contacts":high_contacts,"coverage":"male/female, P1/P2, net/lift/drive/overhead, contact through follow-through, high backhand hand facing, palm grip position, distributed forearm skinning"},"  ")+"\n");report.close()
	print("BACKHAND WRIST: ",checks," checks; ",failures," failures; min hand/forearm dot=",min_forward," max wrist twist degrees=",rad_to_deg(max_twist))
	quit(1 if failures else 0)

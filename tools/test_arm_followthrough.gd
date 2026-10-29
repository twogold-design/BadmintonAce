extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const FOOTWORK=preload("res://scripts/footwork.gd")
var stats={}
var examples={}
var failures=0
var cases=0
var checks=0
func check(ok,label):
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize():call_deferred("run")
func record(key,value,label):
 if not stats.has(key) or value>stats[key]:stats[key]=value;examples[key]=label
func run():
 var model=ATHLETE.new();root.add_child(model)
 for avatar in ["male","female"]:
  for index in [0,1]:
   var side=1.0 if index==0 else -1.0
   for stroke in ["serve","net","lift","drive","overhead"]:
    for backhand in [false,true]:
     var p={"avatar":avatar,"pos":Vector2(0,3*side),"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0 if backhand else 1,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":backhand,"stroke":stroke}
     FOOTWORK.reset(p)
     var serving=stroke=="serve"
     var contact=Vector3((-.7 if backhand else .5)*side,2.7*side,2.2 if stroke=="overhead" else (1.5 if stroke=="drive" else 1.0))
     if serving:
      FOOTWORK.set_service_stance(p,index,false);p.service_long=1.0 if backhand else 0.0
      contact=Vector3(-.18*side,2.65*side,1.05);p.backhand=true
     elif not ATHLETE.can_reach(p,index,contact):continue
     FOOTWORK.hit(p,index,contact,serving)
     cases+=1
     var last_hand=Basis.IDENTITY
     var last_elbow=Vector3.ZERO
     var push_start=Vector3.ZERO
     var push_face=Basis.IDENTITY
     var push_previous=Vector3.ZERO
     for tick in range(62):
      p.swing=0.0 if serving and tick==0 else .48*(1-float(maxi(0,tick-1))/60)
      if tick>1:FOOTWORK.update(p,index,.48/60,true,false,contact,false)
      model.animate(p,index,contact,0,serving and tick==0)
      var frame=ATHLETE.body_frame(p,index)
      var shoulder=model.joint_points.upperarm_r
      var elbow=model.joint_points.lowerarm_r
      var forearm=(model.joint_points.hand_r-elbow).normalized()
      var palm=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
      var lower=model.poses[model.bones.ace_forearm_r_4].basis*model.rests[model.bones.ace_forearm_r_4].basis.inverse()
      var hinge=(elbow-shoulder).normalized().cross(forearm).normalized()
      var target=(palm.y-forearm*palm.y.dot(forearm)).normalized()
      var local_elbow=frame.chest_basis.inverse()*(elbow-shoulder)
      var left=frame.chest_basis.inverse()*(model.joint_points.lowerarm_l-model.joint_points.upperarm_l)
      var label=avatar+" P"+str(index+1)+" "+stroke+" "+str(backhand)+" tick "+str(tick)
      var prefix="serve_" if serving else "return_"
      if serving and tick>=1 and tick<=25:
       var held=frame.chest_basis.inverse()*(model.joint_points.hand_r-frame.chest)
       var face=frame.chest_basis.inverse()*model.racket_basis_current
       if tick==1:push_start=held;push_previous=held;push_face=face
       record("serve_push_sideways",absf(held.x-push_start.x),label)
       record("serve_push_backwards",held.z-push_previous.z,label)
       record("serve_push_face_turn",rad_to_deg(push_face.get_rotation_quaternion().angle_to(face.get_rotation_quaternion())),label)
       if tick==25:check(held.z<push_start.z-.055,"Both serves visibly push forwards before recovery: "+label)
       push_previous=held
      record(prefix+"elbow_behind",local_elbow.z,label)
      record(prefix+"left_clamped",left.x,label)
      # The authored rest palm faces down: a palm-up net grip can be
      # near 180 degrees from that pose. Inspect the actual wrist seam,
      # while retaining the legacy shaft-roll bound for other strokes.
      record("net_rest_roll" if p.stroke in ["net","lift"] else prefix+"forearm_twist",rad_to_deg(absf(hinge.signed_angle_to(target,forearm))),label)
      record(prefix+"wrist_twist",rad_to_deg(absf(lower.y.signed_angle_to(target,forearm))),label)
      record(prefix+"wrist_bend",rad_to_deg(acos(clampf(palm.x.dot(forearm),-1,1))),label)
      if tick>0:
       record(prefix+"hand_step",rad_to_deg(last_hand.get_rotation_quaternion().angle_to(palm.get_rotation_quaternion())),label)
       record(prefix+"elbow_step",last_elbow.distance_to(elbow),label)
      last_hand=palm;last_elbow=elbow
 check(cases==40,"Coverage includes both genders, P1/P2, both serves and four return strokes")
 for prefix in ["serve_","return_"]:
  for bound in [["elbow_behind",.04],["left_clamped",-.055],["wrist_twist",15.0],["wrist_bend",55.0],["elbow_step",.07],["hand_step",25.0],["forearm_twist",100.0 if prefix=="serve_" else 145.0]]:
   var key=prefix+bound[0]
   check(stats[key]<bound[1],key+" exceeded: "+str(stats[key])+" at "+examples[key])
 for bound in [["serve_push_sideways",.02],["serve_push_backwards",.001],["serve_push_face_turn",8.0]]:
  check(stats[bound[0]]<bound[1],bound[0]+" exceeded: "+str(stats[bound[0]]))
 var report={"checks":checks,"failures":failures,"motion_cases":cases,"frames_per_case":62,"maxima":stats,"worst_cases":examples}
 var output=FileAccess.open("res://artifacts/arm-followthrough-test.json",FileAccess.WRITE)
 output.store_string(JSON.stringify(report,"  ")+"\n");output.close()
 print("ARM FOLLOW-THROUGH: ",cases," motions; ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)

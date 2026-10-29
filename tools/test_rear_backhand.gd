extends SceneTree
const A=preload("res://scripts/athlete_3d.gd")
const F=preload("res://scripts/footwork.gd")
var failures=0
var checks=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:
  failures+=1
  if failures<15:push_error(label)
func _initialize():call_deferred("run")
func check_free_arm(model,frame):
 var upper:Vector3=model.joint_points.lowerarm_l-model.joint_points.upperarm_l
 var lower:Vector3=model.joint_points.hand_l-model.joint_points.lowerarm_l
 var hand:Basis=model.poses[model.bones.hand_l].basis*model.rests[model.bones.hand_l].basis.inverse()
 var forearm:Basis=model.poses[model.bones.ace_forearm_l_4].basis*model.rests[model.bones.ace_forearm_l_4].basis.inverse()
 check(upper.angle_to(lower)>deg_to_rad(55) and upper.angle_to(lower)<deg_to_rad(135),"Free elbow remains comfortably bent instead of hanging straight")
 check((frame.chest_basis.inverse()*upper).x<-.08,"Free elbow stays open beside the ribs")
 check((-hand.x).dot(lower.normalized())>.999,"Free wrist follows the forearm")
 check(hand.y.dot(forearm.y)>.999,"Free palm turn is distributed through forearm, not twisted at wrist")
func run():
 var model=A.new();root.add_child(model)
 var cases=0;var max_flip=0.0;var max_wrist=0.0;var max_racket_step=0.0
 for avatar in ["male","female"]:
  for index in [0,1]:
   var side=1.0 if index==0 else -1.0
   for x in [-.70,-.85,-1.0]:
    for depth in [-.3,.15,.4]:
     for height in [2.0,2.2,2.35]:
      var p={"avatar":avatar,"pos":Vector2(0,4*side),"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":true,"stroke":"overhead"}
      F.reset(p)
      var ball=Vector3(x*side,(4+depth)*side,height)
      var reachable=A.can_reach(p,index,ball)
      if x==-.7 and height==2.2 and depth==-.3:check(reachable,"Normal rear backhand remains reachable for both avatars and players")
      if not reachable:continue
      cases+=1
      p.preparation=1.0;p.body_turn=F.backhand_turn(p,index,ball);p.hip_turn=p.body_turn*.65
      model.animate(p,index,ball,0)
      var frame=A.body_frame(p,index)
      check_free_arm(model,frame)
      var prep_upper=(model.joint_points.lowerarm_r-model.joint_points.upperarm_r).normalized()
      var prep_lower=(model.joint_points.hand_r-model.joint_points.lowerarm_r).normalized()
      var prep_hinge=prep_upper.cross(prep_lower).normalized()
      check((frame.chest_basis.inverse()*prep_upper).y>.3,"Backhand preparation raises elbow")
      check(model.joint_points.hand_r.y<model.joint_points.lowerarm_r.y-.05,"Wrist trails below raised elbow before backhand extension")
      check(prep_upper.angle_to(prep_lower)>deg_to_rad(100),"Backhand preparation loads a bent elbow")
      F.hit(p,index,ball,false)
      var previous_racket=Basis.IDENTITY;var previous_elbow=Vector3.ZERO;var contact_elbow_y=0.0
      for tick in range(61):
       p.swing=.48*(1-float(tick)/60)
       if tick>0:F.update(p,index,.48/60,true,false,ball,false)
       model.animate(p,index,ball,0)
       frame=A.body_frame(p,index)
       check_free_arm(model,frame)
       var upper=(model.joint_points.lowerarm_r-model.joint_points.upperarm_r).normalized()
       var lower=(model.joint_points.hand_r-model.joint_points.lowerarm_r).normalized()
       var hinge=upper.cross(lower).normalized()
       var elbow_local=frame.chest_basis.inverse()*(model.joint_points.lowerarm_r-model.joint_points.upperarm_r)
       var hand:Basis=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
       var wrist=lower.angle_to(hand.x);max_wrist=maxf(max_wrist,wrist)
       check(wrist<deg_to_rad(50.1),"Rear backhand keeps wrist aligned throughout recovery")
       check(model.joint_points.lowerarm_r.distance_to(model.joint_points.upperarm_r)>0.22,"Upper arm never shortens during backhand")
       if tick==0:
        var flip=(Basis(Quaternion(prep_upper,upper))*prep_hinge).angle_to(hinge)
        max_flip=maxf(max_flip,flip)
        check(flip<deg_to_rad(60.1),"Backhand prep/contact retains the same elbow hinge branch")
        check(model.contact_error<.002,"Backhand retains precise shuttle contact")
        contact_elbow_y=elbow_local.y
       elif tick<60:
        var step=previous_racket.get_rotation_quaternion().angle_to(model.racket_basis_current.get_rotation_quaternion())
        max_racket_step=maxf(max_racket_step,step)
        check(step<deg_to_rad(20),"Backhand racket does not flip during follow-through")
        check(previous_elbow.distance_to(model.joint_points.lowerarm_r)<.06,"Backhand elbow moves continuously")
        if tick<24:check(elbow_local.y>contact_elbow_y-.04,"Short backhand follow-through retains the raised elbow")
       previous_racket=model.racket_basis_current;previous_elbow=model.joint_points.lowerarm_r
 # Enter and abandon rear preparation using actual footwork updates, rather
 # than only validating its final pose. Both arms must remain continuous.
 for avatar in ["male","female"]:
  for index in [0,1]:
   var side=1.0 if index==0 else -1.0
   var p={"avatar":avatar,"pos":Vector2(0,4*side),"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":true,"stroke":"overhead"}
   F.reset(p)
   var ball=Vector3(-.85*side,3.9*side,2.2)
   var previous_racket=Basis.IDENTITY;var previous_left=Vector3.ZERO
   for tick in range(160):
    F.update(p,index,1.0/120,true,tick<80,ball,false)
    model.animate(p,index,ball,0)
    check_free_arm(model,A.body_frame(p,index))
    var lower=(model.joint_points.hand_r-model.joint_points.lowerarm_r).normalized()
    var hand:Basis=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
    check(lower.dot(hand.x)>cos(deg_to_rad(35)),"Loading and cancelling backhand does not kink the wrist")
    if tick>0:
     check(previous_racket.get_rotation_quaternion().angle_to(model.racket_basis_current.get_rotation_quaternion())<deg_to_rad(20),"Preparation and cancellation do not flip the racket")
     check(previous_left.distance_to(model.joint_points.hand_l)<.065,"Free hand follows the turn continuously")
    previous_racket=model.racket_basis_current;previous_left=model.joint_points.hand_l
 check(cases>=32,"Rear backhand covers a range of heights and depths")
 var result={"cases":cases,"checks":checks,"failures":failures,"max_elbow_branch_turn_degrees":rad_to_deg(max_flip),"max_wrist_degrees":rad_to_deg(max_wrist),"max_racket_frame_turn_degrees":rad_to_deg(max_racket_step)}
 FileAccess.open("res://artifacts/rear-backhand-test.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("REAR BACKHAND: ",result)
 quit(1 if failures else 0)

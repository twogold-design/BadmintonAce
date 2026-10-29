extends SceneTree
const A=preload("res://scripts/athlete_3d.gd")
const F=preload("res://scripts/footwork.gd")
var failures=0
var cases=0
var maxima={}
var worst={}
func _initialize():call_deferred("run")
func check(ok,label):
 if not ok:
  failures+=1
  if failures<12:push_error(label)
func record(key,value,label):
 if not maxima.has(key) or value>maxima[key]:maxima[key]=value;worst[key]=label
func run():
 var m=A.new();root.add_child(m)
 for avatar in ["male","female"]:
  for index in [0,1]:
   var side=1.0 if index==0 else -1.0
   for mode in range(3):
    for x in [-.5,0.0,.5,.9]:
     for z in [-.6,-.3,0.0,.3]:
      for h in [2.0,2.25,2.5]:
       var move=Vector2(1.8,-2.5)*side if mode==1 else Vector2.ZERO
       var jump=.5 if mode==2 else 0.0
       var p={"avatar":avatar,"pos":Vector2(0,5*side),"vel":move,"jump":jump,"swing":0.0,"charge":0,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"stroke":"overhead","backhand":false}
       F.reset(p);p.body_turn=.65*side;p.hip_turn=.4*side
       var ball=Vector3(x*side,(5+z)*side,h+jump)
       if not A.can_reach(p,index,ball):continue
       F.hit(p,index,ball,false);cases+=1
       var previous=[]
       var start_tick=4 if mode>0 else 0
       for tick in range(61):
        p.swing=.48*(1-tick/60.0)
        if tick>0:
         p.pos+=move*.008;F.update(p,index,.008,true,false,ball,false)
        if tick<start_tick:continue
        m.animate(p,index,ball,tick*.008)
        var label="%s P%d mode%d x%.2f z%.2f h%.2f tick%d"%[avatar,index+1,mode,x,z,h,tick]
        var forearm=(m.joint_points.hand_r-m.joint_points.lowerarm_r).normalized()
        var palm=m.poses[m.bones.hand_r].basis*m.rests[m.bones.hand_r].basis.inverse()
        if tick==start_tick:
         check(m.stroke_solution.get("valid",false),"No valid forehand clear pose: "+label)
         record("reversed_impact_face",-m.racket_basis_current.z.z,label)
         record("reversed_impact_palm",-palm.y.z,label)
         if mode==0:record("contact_error",m.contact_error,label)
        record("wrist_bend",rad_to_deg(palm.x.angle_to(forearm)),label)
        # After contact the face rotates with the shoulder and unloading arm.
        # Check temporal continuity below, rather than forcing its impact
        # normal to remain world-fixed throughout a natural follow-through.
        var current=[]
        for bone in ["hand_r","ace_forearm_r_1","ace_forearm_r_2","ace_forearm_r_3","ace_forearm_r_4"]:
         current.append((m.poses[m.bones[bone]].basis*m.rests[m.bones[bone]].basis.inverse()).get_rotation_quaternion())
        if not previous.is_empty():
         for part in range(current.size()):record("skin_frame_turn",rad_to_deg(previous[part].angle_to(current[part])),label+" part"+str(part))
        previous=current
 for bound in [["reversed_impact_face",-.10],["reversed_impact_palm",-.05],["wrist_bend",55.0],["skin_frame_turn",25.0],["contact_error",A.OVERHEAD_CONTACT_TOLERANCE]]:
  check(maxima[bound[0]]<=bound[1],bound[0]+" "+str(maxima[bound[0]])+" "+worst[bound[0]])
 check(cases>=250,"Cover genders, player ends, jumping and delayed moving clears")
 FileAccess.open("res://artifacts/clear-face-test.json",FileAccess.WRITE).store_string(JSON.stringify({"cases":cases,"failures":failures,"maxima":maxima,"worst":worst},"  "))
 print("CLEAR FACE: ",cases," cases; ",failures," failures");quit(1 if failures else 0)

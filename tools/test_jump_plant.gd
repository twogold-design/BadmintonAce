extends SceneTree
const A=preload("res://scripts/athlete_3d.gd")
var failures=0
var checks=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:
  failures+=1
  if failures<20:push_error(label)
func _initialize():call_deferred("run")
func run():
 var game=load("res://main.tscn").instantiate();root.add_child(game)
 game.set_process(false);game.set_physics_process(false);game.sound_on=false
 var report=[]
 for avatar in ["male","female"]:
  for index in [0,1]:
   var side=1.0 if index==0 else -1.0
   for speed in [4.5,10.5]:
    for direction in [Vector2(0,-side),Vector2(side,-side).normalized()]:
     game.start_game("ai");game.phase="rally";game.last_hit=1-index
     var p:Dictionary=game.players[index]
     p.avatar=avatar;p.pos=Vector2(0,5*side);game.FOOTWORK.reset(p)
     game.ball=Vector3(0,0,1)
     var right="r" if index==0 else "l"
     var found=false
     for tick in range(120):
      p.vel=direction*speed;p.pos+=p.vel/120
      game.FOOTWORK.update(p,index,1.0/120,true,false,game.ball,false)
      if float(p["lift_"+right])>.025 and (p["foot_"+right]-p.pos).y*side<-.03:
       found=true;break
     check(found,"Reach a real forward swing of the anatomical right foot")
     if not found:continue
     var original_lift=float(p["lift_"+right]);var original_foot:Vector2=p["foot_"+right]
     p.stamina=100;game._jump(index);game._jump(index)
     check(p.stamina==88 and p.jump_settle>0 and p.jump_load==0,"Repeated input queues one jump after right-foot landing")
     check(p["foot_"+right]==original_foot and p["lift_"+right]==original_lift,"Jump input cannot snap the swing foot to the ground")
     p.buffer=.36;p.shot=2
     game.ball=Vector3(p.pos.x+.35*side,p.pos.y-.3*side,2.25)
     check(not game._try_hit(index,2) and p.swing==0,"Shot waits until the support foot is planted")
     var previous_foot=original_foot;var previous_lift=original_lift
     var support_time=-1.0;var takeoff=-1.0;var max_step=0.0;var max_lift_step=0.0
     var support_foot=Vector2.ZERO;var torso_min=10.0
     for tick in range(120):
      var was_settling=p.jump_settle>0
      game._update_player(index,1.0/120,false)
      max_step=maxf(max_step,previous_foot.distance_to(p["foot_"+right]))
      max_lift_step=maxf(max_lift_step,absf(float(p["lift_"+right])-previous_lift))
      if was_settling:
       check(p.jump==0 and p.jump_crouch==0 and p.jump_drive==0,"Finish foot placement before crouch, drive or takeoff")
       check(float(p["lift_"+right])<=previous_lift+.00001,"Swing foot descends continuously into its support")
      if p.jump_load>0:
       if support_time<0:support_time=float(tick+1)/120;support_foot=p["foot_"+right]
       check(p.lift_l==0 and p.lift_r==0,"Loading starts with both feet grounded")
       check(p.vel.length()<.3,"Body has stopped pulling away from the planted foot")
       check(support_foot.distance_to(p["foot_"+right])<.001,"Right support foot stays anchored throughout loading")
      if p.jump>0:
       takeoff=float(tick+1)/120
       break
      torso_min=minf(torso_min,float(A.body_frame(p,index).pelvis.y))
      previous_foot=p["foot_"+right];previous_lift=p["lift_"+right]
     check(support_time>0 and takeoff-support_time>=.13,"Takeoff follows a completed support and full loading phase")
     check(max_step<.065 and max_lift_step<.025,"Final step has no foot-position or height snap")
     check(torso_min>.64,"Settling does not stretch the legs into a collapsed squat")
     report.append({"avatar":avatar,"index":index,"speed":speed,"support_time":support_time,"takeoff":takeoff,"max_foot_step":max_step,"max_height_step":max_lift_step,"min_pelvis":torso_min})
     p.jump=0;p.jump_v=0;p.jump_load=0;p.lift_l=.08;p.lift_r=.08
     game._jump(index);game.phase="point";game._update_player(index,.02,false)
     check(p.jump_settle==0 and p.jump_load==0 and p.jump_v==0,"Point end cancels the queued plant and jump")
 game.start_game("ai");game.mode="local";game.phase="rally";game.last_hit=1;game.freeze=0
 var queued:Dictionary=game.players[0]
 queued.lift_r=.1;queued.buffer=.36;queued.shot=2
 game._jump(0);game.ball=Vector3(0,0,4);game.velocity=Vector3.ZERO
 game._physics_process(1.0/120)
 check(queued.buffer==.36 and queued.swing==0,"Real frame loop preserves queued-shot lifetime while the foot lands")
 var result={"checks":checks,"failures":failures,"cases":report}
 FileAccess.open("res://artifacts/jump-plant-test.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("JUMP PLANT: ",report.size()," cases; ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)

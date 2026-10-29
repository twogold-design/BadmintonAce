extends SceneTree
const A=preload("res://scripts/athlete_3d.gd")
var failures=0
var checks=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:
  failures+=1
  if failures<18:push_error(label)
func key(code:int,pressed:bool):
 var event=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed;Input.parse_input_event(event);Input.flush_buffered_events()
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
     game.mode="online" if index==1 else "ai"
     game.remote_move=direction
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
     check(found,"Exercise the real forward swing of the right foot")
     if not found:continue
     p.stamina=100;p.dash=.18 if speed>5 else 0.0;p.aim=direction
     var control=p.duplicate(true)
     game.FOOTWORK.reset(control)
     var original_foot:Vector2=p["foot_"+right];var original_lift=float(p["lift_"+right])
     game._jump(index);game._jump(index)
     check(p.stamina==88 and p.jump_load==game.FOOTWORK.JUMP_LOAD_TIME,"Moving jump starts the original load immediately and spends stamina once")
     check(p["foot_"+right]==original_foot and p["lift_"+right]==original_lift,"Input does not teleport the animated foot")
     game.players[index]=control;game._jump(index);game.players[index]=p
     if index==0:
      key(KEY_W,true)
      if direction.x>.1:key(KEY_D,true)
     var takeoff=-1.0;var max_relative_step=0.0;var worst_front=0.0;var max_physics_error=0.0
     var previous_relative:Vector2=p["foot_"+right]-p.pos
     for tick in range(65):
      game.players[index]=control;game._update_player(index,1.0/120,false)
      game.players[index]=p;game._update_player(index,1.0/120,false)
      max_physics_error=maxf(max_physics_error,p.pos.distance_to(control.pos)+p.vel.distance_to(control.vel)+absf(p.jump-control.jump))
      check(p.pos.distance_to(control.pos)<.00001 and p.vel.distance_to(control.vel)<.00001 and absf(p.jump-control.jump)<.00001,"Swing-foot state cannot change player movement or jump timing")
      if p.jump_load>0:check(p.vel.length()>2.0,"Holding movement continues through loading without forced braking")
      var relative:Vector2=p["foot_"+right]-p.pos
      max_relative_step=maxf(max_relative_step,relative.distance_to(previous_relative));previous_relative=relative
      var frame=A.body_frame(p,index)
      if p.jump>0 and takeoff<0:takeoff=float(tick+1)/120
      if p.jump>.20:
       var midpoint:Vector3=(frame.lf+frame.rf)*.5-frame.pelvis
       worst_front=maxf(worst_front,-midpoint.z)
       check(midpoint.z>-.06,"Airborne feet gather below hips rather than both reaching in front")
       check((frame.chest-frame.pelvis).z<-.015,"Airborne chest stays forward of hips")
     if index==0:key(KEY_W,false);key(KEY_D,false)
     check(takeoff>=.13 and takeoff<=.15,"Moving takeoff keeps the original 0.14 second load without a landing wait")
     check(max_relative_step<.08,"Cosmetic leg gathering remains continuous relative to the moving body")
     report.append({"avatar":avatar,"index":index,"speed":speed,"takeoff":takeoff,"max_physics_error":max_physics_error,"max_relative_foot_step":max_relative_step,"max_feet_ahead_of_hips":worst_front})
   # A playable shot must execute immediately even if a foot is still raised.
   game.start_game("ai");game.phase="rally";game.last_hit=1-index;game.phase_time=1.0
   var p:Dictionary=game.players[index]
   p.avatar=avatar;p.pos=Vector2(0,4*side);game.FOOTWORK.reset(p)
   p.lift_l=.06;p.lift_r=.08;p.shot=2;p.buffer=.36;p.charge_time=.2
   game.ball=Vector3(.35*side,3.7*side,2.2)
   game._jump(index)
   check(game._try_hit(index,2) and p.swing>0 and p.buffer==0,"Shot input executes in the same frame without waiting for planted feet")
   p.jump=0;p.jump_v=0;p.jump_load=0
   game._jump(index);game.phase="point";game._update_player(index,.02,false)
   check(p.jump_load==0 and p.jump_v==0,"Ending a rally still cancels ordinary jump loading")
 var result={"checks":checks,"failures":failures,"cases":report,"purpose":"Cosmetic foot gathering must not gate movement, jump or shot input"}
 FileAccess.open("res://artifacts/jump-plant-test.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("JUMP ANIMATION / INPUT: ",report.size()," cases; ",checks," checks; ",failures," failures")
 quit(1 if failures else 0)

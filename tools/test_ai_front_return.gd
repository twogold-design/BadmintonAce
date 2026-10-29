extends SceneTree
const A=preload("res://scripts/athlete_3d.gd")
var cases=0
var worst=0.0
var failures=0
var kinds={}
func _initialize():call_deferred("run")
func run():
 var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.set_physics_process(false);game.sound_on=false
 var model=A.new();root.add_child(model)
 for avatar in ["male","female"]:
  for trial in range(8):
   seed(trial+90);game.start_game("ai");game.phase="rally";game.last_hit=1
   var p=game.players[0];p.pos=Vector2(0,1.7);p.charge_time=.2;game.FOOTWORK.reset(p)
   var ai=game.players[1];ai.pos=Vector2(.3,-1.6);ai.avatar=avatar;game.FOOTWORK.reset(ai)
   game.ball=Vector3(.5,1.2,1.2);game.velocity=Vector3.ZERO
   if not game._try_hit(0,1):failures+=1;continue
   var returned=false;var previous=Basis.IDENTITY
   for tick in range(400):
    game._physics_process(1.0/120)
    if game.last_hit!=1:continue
    if tick%4!=0:continue
    model.animate(ai,1,game.ball,tick/120.0)
    if not returned:
     returned=true;cases+=1;kinds[ai.stroke]=int(kinds.get(ai.stroke,0))+1
     if not model.stroke_solution.get("valid",false):failures+=1
    else:
     var angle=rad_to_deg(previous.get_rotation_quaternion().angle_to(model.racket_basis_current.get_rotation_quaternion()))
     worst=maxf(worst,angle)
     if angle>65:failures+=1
    previous=model.racket_basis_current
    if ai.swing<=0:break
   if not returned:failures+=1
 var report={"actual_player_net_shots":16,"ai_returns":cases,"kinds":kinds,"failures":failures,"max_turn_per_30fps_frame":worst}
 FileAccess.open("res://artifacts/ai-front-return-test.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print(report);quit(1 if failures else 0)

extends SceneTree
var game
var failures = 0
var checks = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures+=1; push_error(label)
func touch(id: int, at: Vector2, pressed: bool, cancelled: bool=false):
	var event=InputEventScreenTouch.new()
	event.index=id; event.position=at; event.pressed=pressed; event.canceled=cancelled
	game.touch_controls._input(event)
func at(key: String) -> Vector2:
	var b: Vector3=game.touch_controls.buttons[key]
	return Vector2(b.x,b.y)
func run():
	root.size=Vector2i(844,390)
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false
	game.touch_controls.enabled=true
	game._enter_offline();game.start_game("practice")
	game.touch_controls._process(0)
	check(game.ui.get_child_count()==0,"Touch overlay replaces tiny desktop pause button")
	game.phase_time=.3
	var hits=game.total_hits
	touch(1,at("clear"),true)
	check(game.players[0].charge==0,"Clear touch starts original charge")
	touch(1,at("clear"),false)
	check(game.total_hits==hits+1,"Release serves exactly once")
	touch(1,at("clear"),false)
	check(game.total_hits==hits+1,"Duplicate release is ignored")
	game.phase="rally"
	var stick=game.touch_controls.stick
	touch(2,stick+Vector2(game.touch_controls.radius,0),true)
	touch(3,at("net"),true)
	check(game._local_movement().x>.95 and game.players[0].charge==1,"Move and charge with separate fingers")
	touch(4,at("smash"),true)
	check(game.players[0].charge==1,"Second stroke finger cannot override owned charge")
	touch(4,at("smash"),false)
	check(game.players[0].charge==1,"Ignored finger cannot release original stroke")
	var event=InputEventScreenDrag.new();event.index=2;event.position=stick-Vector2(game.touch_controls.radius,0)
	game.touch_controls._input(event)
	check(game._local_movement().x<-.95,"Joystick direction follows same owned finger")
	hits=game.total_hits
	touch(3,at("net"),false,true)
	check(game.players[0].charge==-1 and game.total_hits==hits,"Cancelled touch clears charge without firing")
	touch(2,Vector2.ZERO,false)
	check(game._local_movement()==Vector2.ZERO,"Release outside joystick stops movement")
	game.players[0].stamina=100
	touch(6,at("jump"),true)
	check(game.players[0].jump_load>0,"Jump follows existing preparation and stamina logic")
	touch(7,at("dash"),true)
	check(game.players[0].dash>0,"Dash uses existing skill")
	touch(8,at("clear"),true)
	touch(7,at("dash"),false,true)
	check(game.players[0].charge==0,"Cancelling an auxiliary finger must not cancel a different finger's shot")
	game._pause_menu()
	check(game.touch_controls.fingers.is_empty() and game.players[0].charge==-1 and game._local_movement()==Vector2.ZERO,"Pause clears all finger ownership")
	game._resume();game.net_preparing=true
	touch(9,at("clear"),true)
	check(game.players[0].charge==-1,"Countdown blocks touch shots")
	touch(11,at("pause"),true)
	check(game.paused,"Pause remains available during countdown")
	game._resume()
	game.net_preparing=false
	game.offline_mode=false;game.mode="online";game.net_role="host";game.net_match_closed=false
	game.players[1].charge=0;game.players[1].buffer=.2
	game._receive_peer_packet({"type":"input","action":"cancel_shot","match":game.net_match_id})
	check(game.players[1].charge==-1 and game.players[1].buffer==0,"P2 cancellation clears host state without a shot")
	game.mode="practice"
	touch(10,at("net"),true)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.touch_controls.fingers.is_empty() and game.players[0].charge==-1,"Focus loss cancels active touches")
	print("TOUCH INPUT: ",checks," checks, failures=",failures)
	game.queue_free();quit(0 if failures==0 else 1)

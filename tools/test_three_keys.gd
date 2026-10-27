extends SceneTree
var game
var failures=0
var checks=0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func setup_rally(height: float,index: int=0):
	game.start_game("ai")
	game.phase="rally";game.last_hit=1-index
	game.players[index].pos=Vector2(0,3 if index==0 else -3)
	game.FOOTWORK.reset(game.players[index])
	game.ball=Vector3(0,game.players[index].pos.y,height)
func press(code: int,down: bool):
	var event=InputEventKey.new();event.physical_keycode=code;event.pressed=down
	game._unhandled_key_input(event)
func run():
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false
	for example in [[KEY_J,2.4,0,"overhead"],[KEY_J,1.2,3,"lift"],[KEY_K,2.4,2,"overhead"],[KEY_K,1.2,2,"drive"],[KEY_L,2.4,1,"overhead"],[KEY_L,1.2,1,"net"]]:
		setup_rally(example[1]);press(example[0],true);press(example[0],false)
		check(game.total_hits==1,"Three-key input produces exactly one return")
		check(game.players[0].shot==example[2] and game.players[0].stroke==example[3],"Key and contact height choose the correct shot")
	setup_rally(3.4);press(KEY_J,true);press(KEY_J,false)
	check(game.total_hits==0 and game.players[0].buffer>0,"Early J release buffers the input")
	game.ball.z=1.2;game._physics_process(1.0/120)
	check(game.total_hits==1 and game.players[0].shot==3,"Buffered J chooses lift from height at contact, not key-down")
	setup_rally(2.4);press(KEY_I,true);press(KEY_I,false)
	check(game.total_hits==0 and game.players[0].charge==-1,"I is no longer a shot key")
	for pair in [[KEY_J,0],[KEY_L,1]]:
		game.start_game("ai");game.phase_time=.5;press(pair[0],true);press(pair[0],false)
		check(game.total_hits==1 and game.players[0].shot==pair[1],"J serves long and L serves short")
	for pair in [[0,1.2,3],[2,1.2,2],[1,2.4,1]]:
		setup_rally(pair[1],1);game.mode="online";game.net_role="host"
		game._receive_packet({"type":"input","action":"shot","shot":pair[0],"pressed":true})
		game._receive_packet({"type":"input","action":"shot","shot":pair[0],"pressed":false})
		check(game.total_hits==1 and game.players[1].shot==pair[2],"Guest three-key packet resolves on authoritative host")
	print("THREE-KEY INPUT: ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)

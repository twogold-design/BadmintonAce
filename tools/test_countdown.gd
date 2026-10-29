extends SceneTree

class DirectPeer extends RefCounted:
	var packets: Array[Dictionary] = []
	var writable = true
	func send(packet: Dictionary) -> bool:
		if not writable: return false
		packets.append(packet)
		return true

var failures = 0
func check(ok: bool, label: String) -> void:
	if not ok:
		push_error(label)
		failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	var direct = DirectPeer.new()
	game.peer = direct
	game.net_role = "host"
	game.net_match_id = "countdown-test"
	game.start_game("online",true)
	check(game.net_preparing and game.net_prepare_remaining==10,"Online entry starts a full ten-second preparation")
	var original: Vector2 = game.players[0].pos
	game.remote_move = Vector2.RIGHT
	game._physics_process(.5)
	check(game.match_time==0 and game.phase_time==0 and game.players[0].pos==original,"Preparation does not advance match time or physics")
	game.phase_time = 1
	check(not game._try_hit(0,0),"Host cannot serve during preparation")
	game._receive_packet({"type":"input","action":"shot","shot":0,"pressed":true})
	check(game.players[1].charge==-1,"Guest shots are ignored during preparation")
	for i in range(9): game._update_preparation(1)
	check(game.net_preparing and game.net_prepare_remaining==1,"Nine seconds cannot release the match early")
	game.paused = true
	game._update_preparation(3)
	check(game.net_prepare_remaining==1,"Pause preserves remaining preparation time")
	game.paused = false
	direct.writable = false
	game._update_preparation(1)
	check(game.net_preparing,"Host retries final release when channel is congested")
	direct.writable = true
	game._update_preparation(0)
	check(not game.net_preparing and game.remote_move==Vector2.ZERO,"Reliable release starts the match without stale movement")
	check(direct.packets.back().type=="prepare" and direct.packets.back().remaining==0,"Release uses the direct peer channel")
	check(game._can_hit(0),"Serving becomes available after preparation")
	game.net_role = "guest"
	game.start_game("online",true)
	game._update_preparation(12)
	check(game.net_preparing,"Guest cannot start solely from its local clock")
	game._receive_peer_packet({"type":"prepare","match":"wrong-match","remaining":0})
	check(game.net_preparing,"Old-match release is ignored")
	game._receive_peer_packet({"type":"prepare","match":game.net_match_id,"remaining":3})
	check(game.net_preparing and game.net_prepare_remaining==3,"Guest follows host countdown")
	game._receive_peer_packet({"type":"prepare","match":game.net_match_id,"remaining":0})
	check(not game.net_preparing,"Guest releases on host confirmation")
	game._receive_packet({"type":"rematch","match":"next-match"})
	check(game.net_preparing and game.net_prepare_remaining==10,"Rematch gives both players preparation time again")
	game.start_game("practice")
	check(not game.net_preparing,"Offline practice starts without an online countdown")
	print("ONLINE COUNTDOWN: ","PASS" if failures==0 else "FAILED")
	game.queue_free()
	quit(0 if failures==0 else 1)

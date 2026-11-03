extends SceneTree

class Sender extends "res://scripts/main.gd":
	var sent: Array = []
	var allow_send = true
	func _net_send(packet: Dictionary) -> bool:
		if not allow_send: return false
		sent.append(packet.duplicate(true))
		return true

func _initialize(): call_deferred("run")

func run():
	var game = Sender.new()
	game._send_movement(Vector2.ZERO)
	for tick in range(1200):
		game.move_refresh += 1.0/120.0
		game._send_movement(Vector2.ZERO)
	assert(game.sent.size()<=6,"Ten idle seconds should not send 100 duplicate stop commands")
	game.sent.clear()
	game._send_movement(Vector2.RIGHT)
	assert(game.sent.size()==1 and game.sent[-1].x==-1,"Direction changes send immediately")
	for tick in range(1200):
		game.move_refresh += 1.0/120.0
		game._send_movement(Vector2.RIGHT)
	assert(game.sent.size()<=21,"Held movement needs at most two refreshes per second")
	game.move_refresh = 0
	game._send_movement(Vector2.ZERO)
	assert(game.sent[-1].x==0 and game.last_sent_move==Vector2.ZERO,"Key release cannot wait for refresh interval")
	game.allow_send = false
	game._send_movement(Vector2.LEFT)
	assert(game.last_sent_move==Vector2.ZERO,"Congestion must not mark an unsent change as delivered")
	game.allow_send = true
	game._send_movement(Vector2.LEFT)
	assert(game.last_sent_move==Vector2.LEFT and game.sent[-1].x==1,"A skipped command retries on next frame")
	game.phase = "rally"
	assert(is_equal_approx(game._snapshot_interval(),1.0/30.0),"Rallies retain 30 Hz snapshots")
	game.paused = true
	assert(game._snapshot_interval()==2,"Frozen pause uses only a safety refresh")
	game.paused = false
	game.phase = "serve"
	game.net_preparing = true
	assert(game._snapshot_interval()==1,"Frozen preparation uses one snapshot per second")
	game.net_preparing = false
	assert(game._snapshot_interval()==.1,"Active serve positioning retains 10 Hz")
	game.phase = "end"
	assert(game._snapshot_interval()==2,"Result screen does not stream ten copies per second")
	game.free()
	print("PASS network schedule: immediate turns/releases, skipped-command retry, sparse duplicate refresh, unchanged rally frequency.")
	quit()

extends SceneTree

func _initialize(): call_deferred("run")

func run():
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.sound_on = false
	game.offline_mode = true
	game.ai_both = true
	seed(1947)
	game.shot_rng.seed = 1947
	game.start_game("ai")
	var batches = []
	var slowest = []
	for batch in range(6):
		var physics = []
		var animation = []
		for frame in range(1800):
			if game.phase == "end": game.start_game("ai")
			var start = Time.get_ticks_usec()
			game._physics_process(1.0/60)
			var middle = Time.get_ticks_usec()
			game.arena.sync(game)
			var finish = Time.get_ticks_usec()
			physics.append((middle-start)/1000.0)
			animation.append((finish-middle)/1000.0)
			if finish-start>16000:
				slowest.append({"physics_ms":physics.back(),"animation_ms":animation.back(),"hit":game.total_hits,"strokes":[game.players[0].stroke,game.players[1].stroke]})
		physics.sort()
		animation.sort()
		batches.append({"seconds":(batch+1)*30,"hits":game.total_hits,"points":game.stats.points,"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"memory":OS.get_static_memory_usage(),"physics_p95":physics[1710],"physics_max":physics.back(),"animation_p95":animation[1710],"animation_max":animation.back()})
		print(JSON.stringify(batches.back()))
		await process_frame
	var report = {"batches":batches,"slow_frames":slowest}
	var output = OS.get_environment("ACE_RALLY_REPORT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	quit()

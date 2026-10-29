extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false
	for avatar in ["male","female"]:
		game.start_game("ai");game.server=0;game._begin_serve()
		for p in game.players:p.avatar=avatar
		for tick in range(120):
			for i in range(2):game._update_player(i,1.0/120,false)
		game.arena.sync(game);game.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/ready-court-"+avatar+".png")
	quit()

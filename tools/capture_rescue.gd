extends SceneTree
var game
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.set_physics_process(false);game.sound_on=false
	for kind in ["net","smash"]:
		game.start_game("local");game.phase="rally";game.last_hit=1;game.total_hits=10
		var p=game.players[0];p.avatar="male" if kind=="net" else "female";p.pos=Vector2(0,3);game.FOOTWORK.reset(p);p.buffer=.36;p.shot=0
		game.ball=Vector3(-1.2,1.75,1.25) if kind=="net" else Vector3(-1.2,2.25,1.85)
		game.velocity=Vector3(0,.8,-1.2) if kind=="net" else Vector3(0,9,-5.5)
		for tick in range(40):
			game._update_player(0,1.0/120,false);game._step_ball(1.0/120)
			if game._try_hit(0,0):break
		game.arena.sync(game)
		game.arena.camera.position=Vector3(p.pos.x-3.0,1.9,p.pos.y-1.0)
		game.arena.camera.look_at(Vector3(p.pos.x-.15,.85,p.pos.y))
		game.arena.camera.fov=43
		await process_frame;await RenderingServer.frame_post_draw
		await process_frame;await RenderingServer.frame_post_draw
		game.arena.get_texture().get_image().save_png("res://artifacts/rescue-"+kind+".png")
	quit()

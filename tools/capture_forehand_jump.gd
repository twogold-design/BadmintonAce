extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
func _initialize():call_deferred("run")
func run():
	var plant="--plant" in OS.get_cmdline_user_args()
	root.size=Vector2i(1800,900);root.content_scale_size=Vector2i(1800,900)
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false;game.hide()
	var canvas=Control.new();root.add_child(canvas)
	var times=[0.0,.07,.13,.24,.48,.59,.94,1.20]
	var labels=["侧身准备","屈膝蓄力","蹬伸起跳","腾空引拍","高点触球","内旋随挥","落地缓冲","恢复准备"]
	if plant:
		times=[0.0,.10,.225,.29,.36,.43,.55,.80]
		labels=["右脚迈出","完成落脚","形成支撑","屈膝蓄力","蹬伸起跳","腾空","高点挥拍","收拍"]
	for i in range(16):
		var viewport=SubViewport.new();viewport.size=Vector2i(225,450);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var stage=Node3D.new();viewport.add_child(stage)
		var world=WorldEnvironment.new();stage.add_child(world)
		var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("1b2630")
		env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.7;world.environment=env
		var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-35,-30,0);light.light_energy=.85
		game.start_game("ai");game.phase="rally";game.last_hit=1
		var p: Dictionary=game.players[0]
		p.avatar="male" if i<8 else "female";p.pos=Vector2(0,5);p.vel=Vector2.ZERO
		game.FOOTWORK.reset(p);p.charge=2;p.charge_time=.5
		game.ball=Vector3(.3,4.7,2.25)
		for tick in range(30):game._update_player(0,1.0/120,false)
		if plant:
			p.charge=-1;game.FOOTWORK.reset(p)
			for tick in range(120):
				p.vel=Vector2(0,-4.5);p.pos+=p.vel/120
				game.FOOTWORK.update(p,0,1.0/120,true,false,Vector3.ZERO,false)
				if p.lift_r>.025 and p.foot_r.y-p.pos.y<-.03:break
			game.ball=Vector3(p.pos.x+.3,p.pos.y-.3,2.25)
		var model=ATHLETE.new();stage.add_child(model);model.build(p.avatar,0)
		model.animate(p,0,game.ball,0)
		if times[i%8]>0:
			game._jump(0)
			for tick in range(1,roundi(times[i%8]*120)+1):
				game._update_player(0,1.0/120,false)
				game.ball=Vector3(p.pos.x+.3,p.pos.y-.3,2.25+p.jump) if plant else Vector3(.3,4.7,2.25+p.jump)
				if tick==58:
					if not game._try_hit(0,2):push_error("Preview smash missed")
					p.charge=-1
				model.animate(p,0,game.ball,float(tick)/120)
		model.position=Vector3(0,p.jump,0);model.rotation.y=PI/2 if "--side" in OS.get_cmdline_user_args() else PI-.55
		var floor_=MeshInstance3D.new();floor_.mesh=PlaneMesh.new();floor_.mesh.size=Vector2(1.5,1.5);stage.add_child(floor_)
		floor_.material_override=ATHLETE.material(Color("263e44"))
		var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.9
		camera.position=Vector3(0,1.8,5);camera.look_at(Vector3(0,1.8,0));camera.current=true
		var picture=TextureRect.new();canvas.add_child(picture);picture.position=Vector2(i%8*225,int(i/8)*450);picture.size=Vector2(225,450);picture.texture=viewport.get_texture()
		var label=Label.new();canvas.add_child(label);label.position=picture.position+Vector2(12,15);label.text=("男 · " if i<8 else "女 · ")+labels[i%8]
		label.add_theme_font_override("font",load("res://assets/NotoSansSC.ttf"));label.add_theme_font_size_override("font_size",17)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/jump-plant-review.png" if plant else ("res://artifacts/forehand-jump-side.png" if "--side" in OS.get_cmdline_user_args() else "res://artifacts/forehand-jump-review.png"));quit()

extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const FOOTWORK=preload("res://scripts/footwork.gd")
func _initialize():call_deferred("run")
func run():
	var knees="--knees" in OS.get_cmdline_user_args()
	root.size=Vector2i(1440,1200)
	var canvas=Control.new();root.add_child(canvas)
	for i in range(12):
		var viewport=SubViewport.new();viewport.size=Vector2i(360,400);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var stage=Node3D.new();viewport.add_child(stage)
		var world=WorldEnvironment.new();stage.add_child(world)
		var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("1b2630")
		env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.65;world.environment=env
		var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-35,-30,0);light.light_energy=.8
		var p={"avatar":"male" if i<8 else "female","pos":Vector2.ZERO,"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":false}
		if knees:p.avatar="female" if i>=4 and i<8 else "male"
		FOOTWORK.reset(p)
		for frame in range(80+(i%4)*12):
			var velocity=Vector2(4.5,0) if i<4 else Vector2(0,-4.5)
			if knees:velocity=Vector2(4.5,0) if i<8 else Vector2(1,-1).normalized()*4.5
			p.vel=p.vel.move_toward(velocity,32.0/120)
			p.pos+=p.vel/120.0;FOOTWORK.update(p,0,1.0/120,true,false,Vector3(0,0,2),false)
		var model=ATHLETE.new();stage.add_child(model);model.build(p.avatar,0);model.animate(p,0,Vector3(0,0,2),1)
		model.position=Vector3.ZERO;model.rotation.y=0 if i<4 else PI/2;model.racket.visible=false
		var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.98
		camera.position=Vector3(0,.90,4);camera.look_at(Vector3(0,.90,0));camera.current=true
		if knees:
			model.rotation.y=0
			camera.size=1.55;camera.position=Vector3(1.5,2.4,4);camera.look_at(Vector3(0,.72,0))
		var picture=TextureRect.new();canvas.add_child(picture);picture.position=Vector2(i%4*360,int(i/4)*400);picture.size=Vector2(360,400);picture.texture=viewport.get_texture()
		var label=Label.new();canvas.add_child(label);label.position=picture.position+Vector2(15,12);label.text=("横向并步 · " if i<4 else ("男 · 向前跑（←） · " if i<8 else "女 · 向前跑（←） · "))+str(i%4+1)
		if knees:label.text=("男 · 横移 · " if i<4 else ("女 · 横移 · " if i<8 else "男 · 斜向跑 · "))+str(i%4+1)
		label.add_theme_font_override("font",load("res://assets/NotoSansSC.ttf"));label.add_theme_font_size_override("font_size",18)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/knee-motion-review.png" if knees else "res://artifacts/locomotion-review.png");quit()

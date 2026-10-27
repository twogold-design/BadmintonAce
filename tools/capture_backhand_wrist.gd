extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const FOOTWORK=preload("res://scripts/footwork.gd")
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var canvas=Control.new();root.add_child(canvas)
	for i in range(6):
		var viewport=SubViewport.new();viewport.size=Vector2i(480,450);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var stage=Node3D.new();viewport.add_child(stage)
		var world=WorldEnvironment.new();stage.add_child(world)
		var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("1b2630")
		env.ambient_light_color=Color("c7d3e5");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.65;world.environment=env
		var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-30,150,0);light.light_energy=.8
		var high=i%3==2
		var p={"avatar":"male" if i<3 else "female","pos":Vector2.ZERO,"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":true,"stroke":"overhead" if high else "lift"}
		FOOTWORK.reset(p)
		var contact=Vector3(-.35 if high else -.65,-.3,2.2 if high else 1.0)
		FOOTWORK.hit(p,0,contact,false)
		if i%3==1:p.swing=.48*.65
		var model=ATHLETE.new();stage.add_child(model);model.build(p.avatar,0);model.animate(p,0,contact,0)
		var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.42
		var focus=model.joint_points.hand_r
		camera.position=focus+Vector3(-1,.5,-3);camera.look_at(focus);camera.current=true
		var picture=TextureRect.new();canvas.add_child(picture);picture.position=Vector2(i%3*480,int(i/3)*450);picture.size=Vector2(480,450);picture.texture=viewport.get_texture()
		var label=Label.new();canvas.add_child(label);label.position=picture.position+Vector2(15,12);label.text=("男生 · " if i<3 else "女生 · ")+["反手低位触球","反手随挥回收","反手高位触球"][i%3]
		label.add_theme_font_override("font",load("res://assets/NotoSansSC.ttf"));label.add_theme_font_size_override("font_size",18)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/backhand-wrist-detail.png");quit()

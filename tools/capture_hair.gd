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
		var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("707b85")
		env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.7;world.environment=env
		var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-35,-40,0);light.light_energy=.8
		var model=ATHLETE.new();stage.add_child(model);model.build("female",0)
		var p={"avatar":"female","pos":Vector2.ZERO,"jump":0.0,"swing":0.0,"vel":Vector2.ZERO,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":false}
		FOOTWORK.reset(p)
		if i>=3:p.body_turn=.7;p.hip_turn=.4;p.vel=Vector2(5,-5)
		model.animate(p,0,Vector3(0,0,2),3.4);model.racket.visible=false
		model.rotation.y=[PI,PI/2,0][i%3]+(.7 if i>=3 else 0.0)
		var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.49
		camera.position=Vector3(0,1.59,3);camera.look_at(Vector3(0,1.59,0));camera.current=true
		var picture=TextureRect.new();canvas.add_child(picture);picture.position=Vector2(i%3*480,int(i/3)*450)
		picture.size=Vector2(480,450);picture.texture=viewport.get_texture()
		var label=Label.new();canvas.add_child(label);label.position=picture.position+Vector2(16,12)
		label.text=("转身跑动 · " if i>=3 else "站立 · ")+["正面","侧面","背面"][i%3]
		label.add_theme_font_override("font",load("res://assets/NotoSansSC.ttf"));label.add_theme_font_size_override("font_size",20)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/hair-attachment-review.png")
	quit()

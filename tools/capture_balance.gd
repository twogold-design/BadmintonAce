extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const FOOTWORK=preload("res://scripts/footwork.gd")
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var canvas=Control.new();root.add_child(canvas)
	for i in range(8):
		var viewport=SubViewport.new();viewport.size=Vector2i(360,450);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var stage=Node3D.new();viewport.add_child(stage)
		var world=WorldEnvironment.new();stage.add_child(world)
		var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("1b2630")
		env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.65;world.environment=env
		var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-35,-30,0);light.light_energy=.8
		var p={"avatar":"male" if i<4 else "female","pos":Vector2.ZERO,"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":false}
		FOOTWORK.reset(p)
		p.charge=0
		var ball=Vector3(.3,-.2,2.4)
		for frame in range(120): FOOTWORK.update(p,0,1.0/120,true,true,ball,false)
		if i%4>0:
			p.charge=-1;p.stroke="overhead";FOOTWORK.hit(p,0,ball,false)
			for frame in range([0,12,32,80][i%4]):
				p.swing=maxf(0,p.swing-1.0/120);FOOTWORK.update(p,0,1.0/120,true,false,ball,false)
		var model=ATHLETE.new();stage.add_child(model);model.build(p.avatar,0);model.animate(p,0,ball,1)
		model.position=Vector3.ZERO;model.rotation.y=-.3

		var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.65
		camera.position=Vector3(0,1.18,4);camera.look_at(Vector3(0,1.18,0));camera.current=true
		var picture=TextureRect.new();canvas.add_child(picture);picture.position=Vector2(i%4*360,int(i/4)*450);picture.size=Vector2(360,450);picture.texture=viewport.get_texture()
		var label=Label.new();canvas.add_child(label);label.position=picture.position+Vector2(15,12);label.text=("男生 · " if i<4 else "女生 · ")+["架拍 60°","右脚蹬转","左腿承重","回中站稳"][i%4]
		label.add_theme_font_override("font",load("res://assets/NotoSansSC.ttf"));label.add_theme_font_size_override("font_size",18)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/stroke-balance-review.png");quit()

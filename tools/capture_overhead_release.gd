extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const FOOTWORK=preload("res://scripts/footwork.gd")
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1800,1200)
	root.content_scale_size=Vector2i(1800,1200)
	var canvas=Control.new();root.add_child(canvas)
	for i in range(24):
		var viewport=SubViewport.new();viewport.size=Vector2i(300,300);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var stage=Node3D.new();viewport.add_child(stage)
		var world=WorldEnvironment.new();stage.add_child(world)
		var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("1b2630")
		env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.65;world.environment=env
		var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-35,-30,0);light.light_energy=.8
		var p={"avatar":"male" if i<12 else "female","pos":Vector2.ZERO,"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":false}
		FOOTWORK.reset(p)
		var serving=false
		var backhand=false
		var ball=Vector3(-.18,-.35,1.05) if serving else Vector3(.35,-.30,2.20)
		p.backhand=backhand;p.stroke="overhead"
		p.shot=2
		p.body_turn=.65;p.hip_turn=.4
		if serving:FOOTWORK.set_service_stance(p,0,false);p.service_long=1.0
		var model=ATHLETE.new();stage.add_child(model);model.build(p.avatar,0)
		var phase=[0.0,.12,.28,.40,.70,1.0][i%6]
		if i%6==0 and serving:
			model.animate(p,0,ball,0,true)
		else:
			FOOTWORK.hit(p,0,ball,serving)
			for tick in range(61):
				if float(tick)/60>phase:break
				p.swing=.48*(1-float(tick)/60)
				if tick>0:FOOTWORK.update(p,0,.48/60,true,false,ball,false)
				model.animate(p,0,ball,0)
		model.rotation.y=PI-.55 if int(i/6)%2==0 else -.55

		var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.6
		camera.position=Vector3(0,1.35,4);camera.look_at(Vector3(0,1.35,0));camera.current=true
		var picture=TextureRect.new();canvas.add_child(picture);picture.position=Vector2(i%6*300,int(i/6)*300);picture.size=Vector2(300,300);picture.texture=viewport.get_texture()
		var label=Label.new();canvas.add_child(label);label.position=picture.position+Vector2(15,12);label.text=("男 " if i<12 else "女 ")+("正面杀球 " if int(i/6)%2==0 else "背面杀球 ")+["高点触球","内旋随挥","左下卸力","完成随挥","回收","准备接球"][i%6]
		label.add_theme_font_override("font",load("res://assets/NotoSansSC.ttf"));label.add_theme_font_size_override("font_size",18)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/overhead-release-review.png");quit()

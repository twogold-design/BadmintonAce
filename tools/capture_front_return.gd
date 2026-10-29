extends SceneTree
const A=preload("res://scripts/athlete_3d.gd")
const F=preload("res://scripts/footwork.gd")
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1800,1200);root.content_scale_size=root.size
	var canvas=Control.new();root.add_child(canvas)
	var samples=[["male","drive",.35,-.4,1.82],["female","drive",.35,-.4,1.82],["female","drive",-.35,-.15,1.65],["female","net",.8,-.8,1.05]]
	for i in range(24):
		var sample=samples[i/6]
		var viewport=SubViewport.new();viewport.size=Vector2i(300,300);viewport.own_world_3d=true
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
		var stage=Node3D.new();viewport.add_child(stage)
		var world=WorldEnvironment.new();stage.add_child(world)
		var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("1b2630")
		env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_energy=.75;world.environment=env
		var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-35,-30,0)
		var p={"avatar":sample[0],"pos":Vector2(0,-1.7),"vel":Vector2(4.5,0) if i>=18 else Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":2,"buffer":0.0,"dash":0.0,"landing":0.0,"stroke":sample[1]}
		F.reset(p)
		var ball=Vector3(-sample[2],-1.7-sample[3],sample[4])
		p.backhand=F.uses_backhand(p,1,ball);F.hit(p,1,ball,false)
		var model=A.new();stage.add_child(model)
		for tick in range([0,5,15,25,40,58][i%6]+1):
			p.swing=maxf(0,.48-tick/120.0)
			if tick>0:p.pos+=p.vel/120;F.update(p,1,1.0/120,true,false,ball,true)
			if i<18 or tick>=4:model.animate(p,1,ball,tick/120.0)
		if i>=18 and i%6==0:
			for tick in range(4):p.swing-=1.0/120;p.pos+=p.vel/120;F.update(p,1,1.0/120,true,false,ball,true)
			model.animate(p,1,ball,0)
		model.position=Vector3.ZERO
		var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.15
		camera.position=Vector3(0,1.25,4);camera.look_at(Vector3(0,1.25,0));camera.current=true
		var picture=TextureRect.new();canvas.add_child(picture);picture.position=Vector2(i%6*300,int(i/6)*300);picture.size=Vector2(300,300);picture.texture=viewport.get_texture()
		var label=Label.new();canvas.add_child(label);label.position=picture.position+Vector2(12,10)
		label.text=["男 · 正手推挡","女 · 正手推挡","女 · 反手推挡","移动放网"][i/6]+[" 触球"," 送拍"," 随挥"," 回收"," 回位"," 准备"][i%6]
		label.add_theme_font_override("font",load("res://assets/NotoSansSC.ttf"));label.add_theme_font_size_override("font_size",17)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/front-return-review.png");quit()

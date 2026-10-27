extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const FOOTWORK=preload("res://scripts/footwork.gd")
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var stage=Node3D.new();root.add_child(stage)
	var world=WorldEnvironment.new();stage.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("101c28")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("d7e0e7");env.ambient_light_energy=.5;world.environment=env
	var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=.8
	var fill=DirectionalLight3D.new();stage.add_child(fill);fill.rotation_degrees=Vector3(-15,145,0);fill.light_energy=.3
	var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.55
	camera.position=Vector3(0,1.4,7);camera.look_at(Vector3(0,1.4,0));camera.current=true
	var overlay=CanvasLayer.new();root.add_child(overlay)
	var font=load("res://assets/NotoSansSC.ttf")
	for i in range(6):
		var model=ATHLETE.new();stage.add_child(model)
		var p={"avatar":"male" if i<3 else "female","pos":Vector2.ZERO,"jump":0.0,"swing":0.0,"vel":Vector2.ZERO,"charge":0,"shot":0,"buffer":0.0,"dash":0.0,"landing":0.0,"backhand":false}
		FOOTWORK.reset(p)
		var ball=Vector3(.35,-.25,2.35)
		for k in range(45):FOOTWORK.update(p,0,1.0/120,true,true,ball,false)
		if i%3>0:
			p.charge=-1;p.stroke="overhead";FOOTWORK.hit(p,0,ball,false)
			for k in range(24 if i%3==2 else 0):
				p.swing=maxf(0,p.swing-1.0/120);FOOTWORK.update(p,0,1.0/120,true,false,ball,false)
		model.build(p.avatar,0 if i<3 else 1)
		model.animate(p,0,ball,0)
		model.position.x=(i-2.5)*.87;model.rotation.y=PI+.35
		var label=Label.new();overlay.add_child(label);label.text=("男 · " if i<3 else "女 · ")+["引拍","触球","随挥"][i%3]
		label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",20);label.position=Vector2(100+i*220,840)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/motion-reference-sheet.png")
	quit()

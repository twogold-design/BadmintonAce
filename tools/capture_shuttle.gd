extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,600)
	var stage=Node3D.new();root.add_child(stage)
	var world=WorldEnvironment.new();stage.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("18262f")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("dce5eb");env.ambient_light_energy=.65;world.environment=env
	var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-35,-25,0);light.light_energy=.8
	for i in range(3):
		var shuttle=Node3D.new();stage.add_child(shuttle);shuttle.position.x=(i-1)*.11
		preload("res://scripts/shuttle_3d.gd").build(shuttle)
		if i==1:shuttle.rotation.z=-.65
		if i==2:shuttle.rotation.x=PI/2
	var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.15
	camera.position=Vector3(0,.03,1);camera.look_at(Vector3(0,.03,0));camera.current=true
	var overlay=CanvasLayer.new();root.add_child(overlay)
	var label=Label.new();overlay.add_child(label);label.position=Vector2(24,20);label.text="羽毛球结构特写（放大显示） · 16 片薄羽片 / 羽轴 / 绑线 / 球头"
	label.add_theme_font_override("font",load("res://assets/NotoSansSC.ttf"));label.add_theme_font_size_override("font_size",22)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/shuttle-review.png");quit()

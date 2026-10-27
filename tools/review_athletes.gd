extends SceneTree
func _initialize(): call_deferred("run")
func global_rest(s: Skeleton3D, id: int) -> Transform3D:
	var parent=s.get_bone_parent(id)
	return global_rest(s,parent)*s.get_bone_rest(id) if parent>=0 else s.get_bone_rest(id)
func run():
	root.size=Vector2i(1440,900)
	var stage=Node3D.new();root.add_child(stage)
	var world=WorldEnvironment.new();stage.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("101c28")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("d7e0e7");env.ambient_light_energy=.45;world.environment=env
	var light=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=.8
	var fill=DirectionalLight3D.new();stage.add_child(fill);fill.rotation_degrees=Vector3(-15,145,0);fill.light_energy=.25
	var camera=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.30
	camera.position=Vector3(0,.95,7);camera.look_at(Vector3(0,.95,0));camera.current=true
	for i in range(6):
		var model=load("res://assets/athletes/"+("male" if i<3 else "female")+".glb").instantiate()
		stage.add_child(model);model.position.x=(i-2.5)*.59;model.rotation.y=[PI,PI/2,0][i%3]
		load("res://scripts/athlete_materials.gd").apply(model,0 if i<3 else 1,i>=3)
		var s: Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
		for side in ["l","r"]:
			var id=s.find_bone("upperarm_"+side)
			var lower=s.find_bone("lowerarm_"+side)
			var rest=global_rest(s,id);var parent=global_rest(s,s.get_bone_parent(id))
			var direction=(global_rest(s,lower).origin-rest.origin).normalized()
			var target=Vector3(-.10 if side=="l" else .10,-.995,0).normalized()
			var basis_=Basis(Quaternion(direction,target))*rest.basis
			s.set_bone_pose_rotation(id,(parent.basis.inverse()*basis_).get_rotation_quaternion())
		for part in model.find_children("*","MeshInstance3D",true,false):
			for surface in range(part.mesh.get_surface_count()):
				var mat=part.mesh.surface_get_material(surface)
				if mat and mat.resource_name.begins_with("Ace_Jersey"):
					var tint=mat.duplicate();tint.albedo_color=Color("a7c963") if i<3 else Color("d98576");part.set_surface_override_material(surface,tint)
	var overlay=CanvasLayer.new();root.add_child(overlay)
	var font=load("res://assets/NotoSansSC.ttf")
	for i in range(6):
		var label=Label.new();overlay.add_child(label);label.text=("男" if i<3 else "女")+" · "+["正面","侧面","背面"][i%3]
		label.add_theme_font_override("font",font);label.add_theme_font_size_override("font_size",20);label.position=Vector2(90+i*230,835)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/athlete-neutral-review.png")
	quit()

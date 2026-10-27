extends RefCounted
const KIT=preload("res://scripts/athlete_kit.gdshader")
static func apply(model: Node3D, index: int, female: bool) -> void:
	for part in model.find_children("*","MeshInstance3D",true,false):
		for surface in range(part.mesh.get_surface_count()):
			var original: Material=part.mesh.surface_get_material(surface)
			if original and original.resource_name.begins_with("MI_Superhero"):
				var kit=ShaderMaterial.new();kit.shader=KIT
				kit.set_shader_parameter("skin_texture",original.albedo_texture)
				kit.set_shader_parameter("jersey_color",Color("a7c963") if index==0 else Color("d98576"))
				kit.set_shader_parameter("waist",.9368 if female else .9541)
				kit.set_shader_parameter("neck_height",1.4849 if female else 1.5205)
				kit.set_shader_parameter("sleeve",.2116 if female else .342)
				part.set_surface_override_material(surface,kit)

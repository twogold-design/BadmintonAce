extends RefCounted
const KIT=preload("res://scripts/athlete_kit.gdshader")
const JERSEY=preload("res://scripts/jersey.gdshader")
static func apply(model: Node3D, index: int, female: bool) -> void:
	for part in model.find_children("*","MeshInstance3D",true,false):
		for surface in range(part.mesh.get_surface_count()):
			var original: Material=part.mesh.surface_get_material(surface)
			if original and original.resource_name.begins_with("MI_Superhero"):
				var kit=ShaderMaterial.new();kit.shader=KIT
				kit.set_shader_parameter("skin_texture",original.albedo_texture)
				kit.set_shader_parameter("jersey_color",Color("a7c963") if index==0 else Color("d98576"))
				kit.set_shader_parameter("waist",.96 if female else .98)
				part.set_surface_override_material(surface,kit)
			elif original and original.resource_name.begins_with("Ace_Jersey"):
				var jersey=ShaderMaterial.new();jersey.shader=JERSEY
				jersey.set_shader_parameter("jersey_color",Color("a7c963") if index==0 else Color("d98576"))
				jersey.set_shader_parameter("neck_height",1.4849 if female else 1.5205)
				jersey.set_shader_parameter("sleeve",.2766 if female else .337)
				part.set_surface_override_material(surface,jersey)

			elif original is StandardMaterial3D and original.resource_name in ["Ace_Shoes", "Ace_Sole"]:
				var shoe = original.duplicate() as StandardMaterial3D
				shoe.disable_receive_shadows = true
				part.set_surface_override_material(surface,shoe)

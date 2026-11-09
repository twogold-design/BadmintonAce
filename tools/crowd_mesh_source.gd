extends RefCounted
## Offline crowd source extraction. Simplify the rest topology once, then reuse
## these vertices and skin weights for every baked animation pose.

static func extract(person: Node3D) -> Dictionary:
	var records: Array = []
	var output_indices = PackedInt32Array()
	var images: Dictionary = {}
	var model: Node3D = person.get_child(0)
	var source_triangles = 0
	for part in model.find_children("*","MeshInstance3D",true,false):
		if not part.mesh or not part.skin: continue
		var part_transform: Transform3D = model.global_transform.affine_inverse()*part.global_transform
		var normal_transform = part_transform.basis.inverse().transposed()
		for surface_id in range(part.mesh.get_surface_count()):
			var arrays: Array = part.mesh.surface_get_arrays(surface_id)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var source_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var source_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2]!=null else PackedVector2Array()
			var material: Material = part.mesh.surface_get_material(surface_id)
			var material_name = material.resource_name if material else ""
			var budget = _triangle_budget(part.name,material_name)
			source_triangles += source_indices.size()/3
			# Match the athlete skin shader: original feet are hidden inside shoes.
			# Remove only wholly covered triangles from the offline copy.
			if material_name.begins_with("MI_Superhero") and not uv2.is_empty():
				var visible_indices = PackedInt32Array()
				for triangle in range(0,source_indices.size(),3):
					var a = source_indices[triangle]
					var b = source_indices[triangle+1]
					var c = source_indices[triangle+2]
					if maxf(uv2[a].y,maxf(uv2[b].y,uv2[c].y))<.075: continue
					visible_indices.append_array(PackedInt32Array([a,b,c]))
				arrays = arrays.duplicate()
				arrays[Mesh.ARRAY_INDEX] = visible_indices
			var indices = _simplified_indices(arrays,budget)
			var remap: Dictionary = {}
			var skin_stride = source_bones.size()/positions.size()
			var image: Image
			if material is StandardMaterial3D and material.albedo_texture:
				var texture: Texture2D = material.albedo_texture
				if not images.has(texture.get_instance_id()):
					var source_image = texture.get_image()
					if source_image.is_compressed(): source_image.decompress()
					images[texture.get_instance_id()] = source_image
				image = images[texture.get_instance_id()]
			for index in indices:
				if not remap.has(index):
					var bones = PackedInt32Array()
					var weights = PackedFloat32Array()
					for channel in range(skin_stride):
						var bind_index = source_bones[index*skin_stride+channel]
						var bone_name: StringName = part.skin.get_bind_name(bind_index)
						var bone_index: int = person.bones.get(bone_name,part.skin.get_bind_bone(bind_index))
						if bone_index<0:
							push_error("Unknown crowd source bone: "+str(bone_name))
							bone_index = 0
						bones.append(bone_index)
						weights.append(source_weights[index*skin_stride+channel])
					var paint = _vertex_color(material,image,uv[index] if not uv.is_empty() else Vector2.ZERO)
					var position: Vector3 = part_transform*positions[index]
					if str(part.name).begins_with("Hair_"):
						# Decimated head/scalp surfaces must not intersect each other.
						# A small radial clearance preserves the source hair silhouette.
						var skull_center: Vector3 = person.rest_at("Head")+Vector3(0,.10,0)
						position += (position-skull_center).normalized()*.004
					var garment = Vector2(uv2[index].y if not uv2.is_empty() else 0.0,1.0 if material_name.begins_with("MI_Superhero") else 0.0)
					remap[index] = records.size()
					records.append({"position":position,"normal":(normal_transform*normals[index]).normalized(),"color":paint.color,"shirt":paint.shirt,"garment":garment,"bones":bones,"weights":weights})
				output_indices.append(remap[index])
			print("CROWD SOURCE ",person.gender," / ",part.name," / ",material_name,": ",source_indices.size()/3," -> ",indices.size()/3," triangles")
	print("CROWD SOURCE TOTAL ",person.gender,": ",source_triangles," -> ",output_indices.size()/3," triangles; ",records.size()," vertices")
	return {"vertices":records,"indices":output_indices}

static func _triangle_budget(part_name: String, material_name: String) -> int:
	if material_name.begins_with("MI_Superhero"): return 3200
	if material_name.begins_with("Ace_Jersey"): return 1300
	if "Eye" in material_name or "Face" in part_name: return 160
	if part_name.begins_with("Hair_"): return 2200
	if "Hair" in material_name or "hair" in part_name.to_lower() or "Ponytail" in part_name: return 500
	if material_name.begins_with("Ace_Shoes") or material_name.begins_with("Ace_Sole"): return 180
	return 300

static func _simplified_indices(source_arrays: Array, triangle_budget: int) -> PackedInt32Array:
	var source: PackedInt32Array = source_arrays[Mesh.ARRAY_INDEX]
	if source.size()<=triangle_budget*3: return source
	var arrays = source_arrays.duplicate(true)
	arrays[Mesh.ARRAY_BONES] = null
	arrays[Mesh.ARRAY_WEIGHTS] = null
	var importer = ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays)
	importer.generate_lods(60.0,60.0,[])
	var selected = source
	var closest_distance = absf(log(float(source.size())/(triangle_budget*3)))
	for lod in range(importer.get_surface_lod_count(0)):
		var candidate = importer.get_surface_lod_indices(0,lod)
		if candidate.is_empty(): continue
		var distance = absf(log(float(candidate.size())/(triangle_budget*3)))
		if distance<closest_distance:
			closest_distance = distance
			selected = candidate
	return selected

static func _vertex_color(material: Material, image: Image, uv: Vector2) -> Dictionary:
	var name_ = material.resource_name if material else ""
	if name_.begins_with("Ace_Jersey"):
		return {"color":Color.WHITE,"shirt":1.0}
	var color = material.albedo_color if material is StandardMaterial3D else Color.WHITE
	# Match athlete_kit, which samples the skin texture directly and ignores
	# any material tint. Garment boundaries are applied per fragment at runtime.
	if name_.begins_with("MI_Superhero"): color = Color.WHITE
	if image and not image.is_empty():
		var x = clampi(int(fposmod(uv.x,1.0)*image.get_width()),0,image.get_width()-1)
		var y = clampi(int(fposmod(uv.y,1.0)*image.get_height()),0,image.get_height()-1)
		color *= image.get_pixel(x,y)
	return {"color":color.srgb_to_linear(),"shirt":0.0}

extends RefCounted
## Small supporter props authored around a grip origin, with the handle along +Y.
## The crowd baker attaches these rigid vertices to the spectator's hand poses.

static func append(data: Dictionary, kind: String) -> void:
	if kind=="flag":
		_flag(data)
	elif kind=="horn":
		_horn(data)

static func _vertex(data: Dictionary, position: Vector3, normal: Vector3, color: Color) -> int:
	var index: int = data.vertices.size()
	data.vertices.append({"position":position,"normal":normal,"color":color.srgb_to_linear(),"shirt":0.0,"garment":Vector2.ZERO,"bones":PackedInt32Array(),"weights":PackedFloat32Array(),"prop":true})
	return index

static func _primitive(data: Dictionary, shape: PrimitiveMesh, offset: Vector3, color: Color, inside: bool = false) -> void:
	var arrays = shape.get_mesh_arrays()
	var first: int = data.vertices.size()
	for i in range(arrays[Mesh.ARRAY_VERTEX].size()):
		_vertex(data,arrays[Mesh.ARRAY_VERTEX][i]+offset,arrays[Mesh.ARRAY_NORMAL][i]*(-1.0 if inside else 1.0),color)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in range(0,indices.size(),3):
		data.indices.append(first+indices[i])
		data.indices.append(first+indices[i+2 if inside else i+1])
		data.indices.append(first+indices[i+1 if inside else i+2])

static func _cylinder(bottom: float, top: float, height: float, segments: int, caps: bool = true) -> CylinderMesh:
	var shape = CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = segments
	shape.rings = 1
	shape.cap_top = caps
	shape.cap_bottom = caps
	return shape

static func _triangle(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, color: Color, double_sided: bool = false) -> void:
	# Godot uses clockwise front faces; normals face away from that winding.
	var normal = (c-a).cross(b-a).normalized()
	data.indices.append(_vertex(data,a,normal,color))
	data.indices.append(_vertex(data,b,normal,color))
	data.indices.append(_vertex(data,c,normal,color))
	if double_sided:
		data.indices.append(_vertex(data,a,-normal,color))
		data.indices.append(_vertex(data,c,-normal,color))
		data.indices.append(_vertex(data,b,-normal,color))

static func _cloth_point(x: int, y: int) -> Vector3:
	var px = .008+x*.05
	var py = .27+y*.09
	return Vector3(px,py,.015*sin(float(x)*1.15+float(y)*.7)*float(x)/6.0)

static func _flag(data: Dictionary) -> void:
	_primitive(data,_cylinder(.008,.008,.63,8),Vector3(0,.235,0),Color("ddd4b7"))
	for x in range(6):
		for y in range(3):
			# A simple cream diagonal accent, not a national or sponsor flag.
			var color = Color("efe5ca") if x==y+2 else Color("c96950")
			var a = _cloth_point(x,y)
			var b = _cloth_point(x+1,y)
			var c = _cloth_point(x,y+1)
			var d = _cloth_point(x+1,y+1)
			_triangle(data,a,c,b,color,true)
			_triangle(data,b,c,d,color,true)

static func _horn(data: Dictionary) -> void:
	var yellow = Color("d7a449")
	var coral = Color("bd6249")
	# Mouthpiece and short grip lead into a genuinely hollow flared bell.
	_primitive(data,_cylinder(.018,.018,.17,12,false),Vector3(0,.015,0),coral)
	_primitive(data,_cylinder(.023,.023,.025,12),Vector3(0,-.065,0),yellow)
	_primitive(data,_cylinder(.018,.075,.20,16,false),Vector3(0,.20,0),yellow)
	_primitive(data,_cylinder(.012,.067,.19,16,false),Vector3(0,.205,0),Color("735021"),true)
	# Annular rim leaves the dark interior open instead of capping the horn.
	for i in range(16):
		var a = i*TAU/16.0
		var b = (i+1)*TAU/16.0
		var inner_a = Vector3(cos(a)*.067,.30,sin(a)*.067)
		var outer_a = Vector3(cos(a)*.075,.30,sin(a)*.075)
		var inner_b = Vector3(cos(b)*.067,.30,sin(b)*.067)
		var outer_b = Vector3(cos(b)*.075,.30,sin(b)*.075)
		_triangle(data,inner_a,outer_a,inner_b,coral)
		_triangle(data,outer_a,outer_b,inner_b,coral)

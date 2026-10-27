extends RefCounted
## Metre-scale shuttle: cork nose, sixteen thin vanes, quills and binding rings.
const LENGTH=.086
const SKIRT_RADIUS=.0325
const FEATHERS=16
static func material(color: Color, double_sided: bool=false) -> StandardMaterial3D:
	var mat=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.86
	if double_sided:mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	return mat
static func surface(parent: Node3D, mesh_: Mesh, mat: Material) -> void:
	var part=MeshInstance3D.new();part.mesh=mesh_;part.material_override=mat;parent.add_child(part)
static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal=(b-a).cross(c-a).normalized()
	# Godot uses clockwise front faces. Keep outward lighting normals while
	# winding the visible side clockwise, including double-sided feather vanes.
	for point in [a,c,b]:st.set_normal(normal);st.add_vertex(point)
static func tube(st: SurfaceTool, points: Array, radius: float, sides: int=6) -> void:
	for k in range(points.size()-1):
		var axis: Vector3=(points[k+1]-points[k]).normalized()
		var across=axis.cross(Vector3.RIGHT).normalized()
		if across.length()<.1:across=axis.cross(Vector3.UP).normalized()
		var other=axis.cross(across)
		for j in range(sides):
			var a=TAU*j/sides;var b=TAU*(j+1)/sides
			var u=radius*(across*cos(a)+other*sin(a));var v=radius*(across*cos(b)+other*sin(b))
			triangle(st,points[k]+u,points[k]+v,points[k+1]+v)
			triangle(st,points[k]+u,points[k+1]+v,points[k+1]+u)
static func build(parent: Node3D) -> void:
	var cork=SphereMesh.new();cork.radius=.013;cork.height=.026;cork.radial_segments=32;cork.rings=16
	surface(parent,cork,material(Color("f4f0e4")))
	var band=CylinderMesh.new();band.top_radius=.0125;band.bottom_radius=.0125;band.height=.003;band.radial_segments=32
	var band_node=MeshInstance3D.new();parent.add_child(band_node);band_node.mesh=band;band_node.position.y=.009
	band_node.material_override=material(Color("284c48"))
	var vanes=SurfaceTool.new();vanes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ribs=SurfaceTool.new();ribs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for feather in range(FEATHERS):
		var angle=TAU*feather/FEATHERS
		var centers=[]
		var rows=[]
		for k in range(25):
			var t=k/24.0;var a=angle+.085*t
			var radial=Vector3(cos(a),0,sin(a));var tangent=Vector3(-sin(a),0,cos(a))
			var center=radial*lerpf(.009,SKIRT_RADIUS,t)+Vector3(0,lerpf(.012,.073,t),0)
			centers.append(center)
			var leaf_t=clampf((t-.22)/.78,0,1)
			var width=.0045*smoothstep(0,.24,leaf_t)
			if leaf_t>.82:width*=sqrt(maxf(0,1-pow((leaf_t-.82)/.18,2)))
			# A fine ridge along the quill and a shallow cupped vane, not a solid petal.
			var row=[center-tangent*width,center+radial*.00055,center+tangent*width]
			rows.append(row)
			if k>5:
				for strip in range(2):
					triangle(vanes,rows[k-1][strip],row[strip],row[strip+1])
					triangle(vanes,rows[k-1][strip],row[strip+1],rows[k-1][strip+1])
		tube(ribs,centers,.00032)
	for y in [.020,.027]:
		var radius=lerpf(.009,SKIRT_RADIUS,(y-.012)/.061)
		var points=[]
		for j in range(65):points.append(Vector3(cos(TAU*j/64)*radius,y,sin(TAU*j/64)*radius))
		tube(ribs,points,.00045)
	surface(parent,vanes.commit(),material(Color("f4f3e9"),true))
	surface(parent,ribs.commit(),material(Color("d8d6c8")))

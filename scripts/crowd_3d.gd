extends Node3D
## Simplified crowd and held props share offline poses, instancing and dim lights.
var sections: Array[MultiMeshInstance3D] = []
var elapsed = 0.0
var excitement = 0.0
var last_phase = ""
var last_score = 0
var was_active = false
var crowd_materials: Array[ShaderMaterial] = []
const KINDS = ["plain","flag","horn"]

static func prop_kind(index: int, section_id: int) -> String:
 var pick = (index+section_id*3)%12
 return "flag" if pick in [1,7] else ("horn" if pick==4 else "plain")

static func is_female(index: int, section_id: int) -> bool:
 return (index+section_id*5)%24 in [0,3,4,7,9,10,13,14,17,19,21,22]

func setup() -> void:
 var colors = [Color("754f49"),Color("456871"),Color("96886b"),Color("526a86"),Color("76677c"),Color("607768"),Color("b4b2a6"),Color("394750")]
 for gender in ["male","female"]:
  for kind in KINDS:
   var stem = gender+("" if kind=="plain" else "-"+kind)
   var material = ShaderMaterial.new()
   material.shader = preload("res://scripts/crowd.gdshader")
   material.set_shader_parameter("pose_texture",load("res://assets/crowd/"+stem+"-poses.res"))
   crowd_materials.append(material)
 for section_id in range(4):
  var side = -1.0 if section_id%2==0 else 1.0
  for gender_id in range(2):
   for kind_id in range(KINDS.size()):
    var kind: String = KINDS[kind_id]
    var members: Array[int] = []
    for i in range(24):
     if int(is_female(i,section_id))==gender_id and prop_kind(i,section_id)==kind: members.append(i)
    if members.is_empty(): continue
    var section = MultiMeshInstance3D.new()
    section.name = "Fans%d_%d_%s" % [section_id,gender_id,kind]
    var instances = MultiMesh.new()
    instances.transform_format = MultiMesh.TRANSFORM_3D
    instances.use_custom_data = true
    instances.use_colors = true
    var stem = ("male" if gender_id==0 else "female")+("" if kind=="plain" else "-"+kind)
    instances.mesh = load("res://assets/crowd/"+stem+".res")
    instances.instance_count = members.size()
    section.multimesh = instances
    section.material_override = crowd_materials[gender_id*3+kind_id]
    section.layers = 2
    section.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    section.custom_aabb = AABB(Vector3(-10,-.2,-14),Vector3(20,5,28))
    add_child(section)
    sections.append(section)
    section.set_meta("baseline_side",side if section_id<2 else 0.0)
    section.set_meta("prop_kind",kind)
    for slot in range(members.size()):
     var i = members[slot]
     var row = i/12
     var column = i%12
     var at: Vector3
     var yaw: float
     if section_id<2:
      at = Vector3((column-5.5)*.71,.15+row*.48,side*(10.25+row*1.05))
      yaw = (0.0 if side>0 else PI)+side*(column-5.5)*.018
     else:
      at = Vector3(side*(6.9+row*1.05),.15+row*.48,(column-5.5)*1.1)
      yaw = side*PI/2-side*(column-5.5)*.025
     var id = section_id*24+i
     var height = .94+float((id*7)%11)*.010
     var width = .94+float((id*3)%7)*.022
     instances.set_instance_transform(slot,Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(width,height,width)),at))
     var tint: Color = colors[(id*3+row*2)%colors.size()]
     instances.set_instance_color(slot,Color.WHITE)
     instances.set_instance_custom_data(slot,Color(tint.r,tint.g,tint.b,float(id)))

func sync(game: Node2D, dt: float) -> void:
 visible = game.screen=="game"
 if not visible:
  was_active = false
  excitement = 0.0
  return
 for section in sections:
  var baseline_side = float(section.get_meta("baseline_side"))
  section.visible = baseline_side==0.0 or baseline_side!=game._view_sign()
 var score_total = int(game.score[0])+int(game.score[1])
 if not was_active or score_total<last_score:
  last_phase = game.phase
  last_score = score_total
  excitement = 0.0
 was_active = true
 if game.paused: return
 elapsed += maxf(dt,0.0)
 excitement = move_toward(excitement,0.0,maxf(dt,0.0)/2.5)
 if (game.phase in ["point","end"] and game.phase!=last_phase) or score_total>last_score:
  excitement = 1.0
 last_phase = game.phase
 last_score = score_total
 for material in crowd_materials:
  material.set_shader_parameter("crowd_time",elapsed)
  material.set_shader_parameter("excitement",excitement)

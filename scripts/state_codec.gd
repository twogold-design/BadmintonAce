extends RefCounted
## Full independent snapshots: no delta chains, so packet loss cannot corrupt a
## later frame. Gameplay coordinates/velocity keep float32 precision.
const FOOTWORK = preload("res://scripts/footwork.gd")
const VERSION = 3
# Only cosmetic pose weights/angles are quantized (maximum error 1/8192).
# Ball, velocity, player/foot positions and contact points remain float32.
const POSE_SCALE = 4096.0
const PHASES = ["serve","rally","point","end"]
const STROKES = ["overhead","net","drive","lift","serve"]
const STYLES = ["ready","adjust","chasse","rear_chasse","run","scissor","lunge","serve_short","serve_long","receive_ready","jump_load"]
const SCALARS = ["stamina","jump","swing","landing","dash","buffer","charge_time","step","last_drop_x"]

static func encode(packet: Dictionary, version: int = VERSION) -> PackedByteArray:
	if version>=3:
		for p in packet.players:
			for key in FOOTWORK.POSE_VALUES:
				var value = float(p.get("motion",{}).get(key,0))
				# Future poses outside the compact range retain full precision.
				if not is_finite(value) or value< -8.0 or value>32767.0/POSE_SCALE:
					version = 2
	var out = StreamPeerBuffer.new()
	var pose_keys=FOOTWORK.POSE_VALUES.slice(0,17) if version==1 else FOOTWORK.POSE_VALUES
	out.put_u8(186)
	out.put_u8(version)
	out.put_utf8_string(str(packet.get("match","")))
	out.put_u32(int(packet.get("seq",0)))
	out.put_double(float(packet.time))
	for key in ["ball","velocity"]:
		for value in packet[key]: out.put_float(float(value))
	out.put_u8(maxi(0,PHASES.find(packet.phase)))
	for value in packet.score: out.put_u8(int(value))
	for key in ["server","last_hit","winner","last_winner"]: out.put_8(int(packet.get(key,0)))
	for key in ["rally","longest","hits","perfect"]: out.put_u32(int(packet.get(key,0)))
	out.put_u16(int(packet.get("speed",0)))
	out.put_u8(1 if packet.get("paused",false) else 0)
	for value in packet.get("shots",[0,0,0,0]): out.put_u16(int(value))
	out.put_utf8_string(str(packet.get("reason","")))
	for p in packet.players:
		for key in ["pos","vel","shot_aim"]:
			for value in p.get(key,[0,0]): out.put_float(float(value))
		for key in SCALARS: out.put_float(float(p.get(key,0)))
		out.put_u8(int(p.shot))
		out.put_8(int(p.charge))
		out.put_u16(int(p.get("drop_count",0)))
		out.put_u8(1 if p.backhand else 0)
		out.put_u8(maxi(0,STROKES.find(p.stroke)))
		var motion: Dictionary = p.get("motion",{})
		out.put_u8(maxi(0,STYLES.find(motion.get("style","ready"))))
		for key in ["left","right"]:
			for value in motion.get(key,p.pos): out.put_float(float(value))
		for key in pose_keys:
			if version>=3: out.put_16(roundi(float(motion.get(key,0))*POSE_SCALE))
			else: out.put_float(float(motion.get(key,0)))
		out.put_u8(1 if motion.has("contact") else 0)
		if motion.has("contact"):
			for value in motion.contact: out.put_float(float(value))
	return out.data_array

static func sequence(bytes: PackedByteArray) -> int:
	# Inspect only the fixed header before discarding a backlog of old snapshots.
	if bytes.size()<48 or bytes.size()>1200 or bytes[0]!=186 or int(bytes[1])<1 or int(bytes[1])>VERSION: return -1
	if bytes.decode_u32(2)!=36: return -1
	return bytes.decode_u32(42)

static func decode(bytes: PackedByteArray) -> Dictionary:
	# All supported frames are smaller than one UDP MTU. Reject malformed lengths
	# before reading variable-size fields; never deserialize peer objects.
	if bytes.size()<116 or sequence(bytes)<0: return {}
	var pose_keys=FOOTWORK.POSE_VALUES.slice(0,17) if bytes[1]==1 else FOOTWORK.POSE_VALUES
	var input = StreamPeerBuffer.new()
	input.data_array = bytes
	input.seek(2)
	var match_size = input.get_u32()
	if match_size!=36: return {}
	var match_id = input.get_utf8_string(match_size)
	var packet = {"type":"state","match":match_id,"seq":input.get_u32(),"time":input.get_double()}
	for key in ["ball","velocity"]:
		packet[key] = [input.get_float(),input.get_float(),input.get_float()]
	var phase = input.get_u8()
	if phase>=PHASES.size(): return {}
	packet.phase = PHASES[phase]
	packet.score = [input.get_u8(),input.get_u8()]
	for key in ["server","last_hit","winner","last_winner"]: packet[key] = input.get_8()
	for key in ["rally","longest","hits","perfect"]: packet[key] = input.get_u32()
	packet.speed = input.get_u16()
	packet.paused = input.get_u8()!=0
	packet.shots = [input.get_u16(),input.get_u16(),input.get_u16(),input.get_u16()]
	var reason_size = input.get_u32()
	var player_bytes=84+pose_keys.size()*(2 if bytes[1]>=3 else 4)
	if reason_size>128 or input.get_available_bytes()<reason_size+player_bytes*2: return {}
	packet.reason = input.get_utf8_string(reason_size)
	packet.players = []
	for i in range(2):
		if input.get_available_bytes()<player_bytes: return {}
		var p = {}
		for key in ["pos","vel","shot_aim"]: p[key] = [input.get_float(),input.get_float()]
		for key in SCALARS: p[key] = input.get_float()
		p.shot = input.get_u8()
		p.charge = input.get_8()
		p.drop_count = input.get_u16()
		p.backhand = input.get_u8()!=0
		var stroke = input.get_u8()
		var style = input.get_u8()
		if stroke>=STROKES.size() or style>=STYLES.size(): return {}
		p.stroke = STROKES[stroke]
		p.motion = {"style":STYLES[style]}
		for key in ["left","right"]: p.motion[key] = [input.get_float(),input.get_float()]
		for key in pose_keys: p.motion[key] = input.get_16()/POSE_SCALE if bytes[1]>=3 else input.get_float()
		if input.get_u8()!=0:
			if input.get_available_bytes()<12: return {}
			p.motion.contact = [input.get_float(),input.get_float(),input.get_float()]
		packet.players.append(p)
	if input.get_available_bytes()!=0: return {}
	return packet

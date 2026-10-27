extends RefCounted
## Render received snapshots on one short, buffered host timeline.
## Ball and velocity must describe the same instant for stable flight guides.

const DELAY = .066
var frames: Array[Dictionary] = []
var playhead = -1.0
var shown_hit = -1

func reset() -> void:
	frames.clear()
	playhead = -1.0
	shown_hit = -1

func push(packet: Dictionary) -> void:
	if not frames.is_empty():
		if float(packet.time)<float(frames.back().time)-.2: reset()
		elif float(packet.time)<=float(frames.back().time):
			frames[frames.size()-1] = packet
			return
	frames.append(packet)
	while frames.size()>20: frames.pop_front()
	if playhead<0: playhead = float(packet.time)-DELAY

func render(game: Node2D, dt: float) -> void:
	if frames.is_empty(): return
	var newest = float(frames.back().time)
	var lag = newest-playhead
	# Small clock corrections avoid visible jumps when packet spacing varies.
	var rate = 1.03 if lag>.12 else (.97 if lag<.025 else 1.0)
	playhead = minf(playhead+dt*rate,newest+.04)
	while frames.size()>1 and float(frames[1].time)<=playhead: frames.pop_front()
	var a: Dictionary = frames[0]
	var b: Dictionary = frames[1] if frames.size()>1 else a
	var span = float(b.time)-float(a.time)
	var blend = clampf((playhead-float(a.time))/span,0,1) if span>.0001 else 0.0
	var elapsed = clampf(playhead-float(a.time),0,.10)
	var origin = Vector3(float(a.ball[0]),float(a.ball[1]),float(a.ball[2]))
	var speed = Vector3(float(a.velocity[0]),float(a.velocity[1]),float(a.velocity[2]))
	if a.phase=="rally":
		var decay = exp(-game.DRAG*elapsed)
		game.ball = origin+Vector3(speed.x*(1-decay)/game.DRAG,speed.y*(1-decay)/game.DRAG,speed.z*elapsed-.5*game.G*elapsed*elapsed)
		game.ball.z = maxf(0,game.ball.z)
		game.velocity = Vector3(speed.x*decay,speed.y*decay,speed.z-game.G*elapsed)
	else:
		game.ball = origin
		game.velocity = speed
	game.last_hit = int(a.last_hit)
	if shown_hit!=int(a.hits):
		shown_hit = int(a.hits)
		game.ball_trail.clear()
	if a.phase=="rally" and game.phase=="rally":
		game.ball_trail.push_front(game.ball)
		if game.ball_trail.size()>32: game.ball_trail.pop_back()
	else: game.ball_trail.clear()
	for i in range(2):
		var p: Dictionary = game.players[i]
		var pa: Dictionary = a.players[i]
		var pb: Dictionary = b.players[i]
		p.pos = vector(pa.pos).lerp(vector(pb.pos),blend)
		p.vel = vector(pa.vel).lerp(vector(pb.vel),blend)
		for key in ["jump","landing","step","dash","buffer","charge_time"]:
			p[key] = lerpf(float(pa.get(key,0)),float(pb.get(key,0)),blend)
		p.swing = lerpf(float(pa.swing),float(pb.swing),blend) if a.hits==b.hits else float(pa.swing)
		for key in ["stroke","shot","charge","backhand"]: p[key] = pa[key]
		var ma: Dictionary = pa.get("motion",{})
		if ma.has("contact"): p.contact = Vector3(float(ma.contact[0]),float(ma.contact[1]),float(ma.contact[2]))
		else: p.erase("contact")
		var mb: Dictionary = pb.get("motion",ma)
		if ma.has("left") and mb.has("left"):
			p.foot_l = vector(ma.left).lerp(vector(mb.left),blend)
			p.foot_r = vector(ma.right).lerp(vector(mb.right),blend)
			p.footwork = str(ma.get("style","ready"))
			for key in game.FOOTWORK.POSE_VALUES:
				p[key] = lerpf(float(ma.get(key,0)),float(mb.get(key,0)),blend)

static func vector(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

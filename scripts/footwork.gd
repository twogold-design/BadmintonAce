extends RefCounted
## Cosmetic foot plants and a hip-led stroke; never changes shot physics or input.

const SWING_TIME = .48
const POSE_VALUES = ["body_turn","hip_turn","weight_shift","split","lift_l","lift_r","lunge","preparation"]

static func reset(p: Dictionary) -> void:
	p.merge({"foot_l":p.pos+Vector2(-.16,0),"foot_r":p.pos+Vector2(.16,0),
		"lift_l":0.0,"lift_r":0.0,"step_leg":-1,"next_leg":0,"step_t":0.0,
		"step_from":p.pos,"step_to":p.pos,"body_turn":0.0,"hip_turn":0.0,
		"weight_shift":0.0,"split":0.0,"lunge":0.0,"preparation":0.0,"footwork":"ready",
		"stroke_side":1.0,"swing_from":0.0,"reach_dir":Vector2.ZERO},true)
	p.erase("motion_target")
	p.erase("contact")

static func hit(p: Dictionary, index: int, shuttle: Vector3, serving: bool) -> void:
	p.stroke_side = (1.0 if index==0 else -1.0) * (-1.0 if p.backhand else 1.0)
	p.swing_from = p.body_turn
	p.reach_dir = (Vector2(shuttle.x,shuttle.y)-p.pos).limit_length(1)
	p.swing = SWING_TIME
	p.contact = shuttle
	if serving: p.stroke = "serve"

static func update(p: Dictionary, index: int, dt: float, rally: bool, incoming: bool, shuttle: Vector3, is_ai: bool) -> void:
	var side = 1.0 if index==0 else -1.0
	var speed: float = p.vel.length()
	var move: Vector2 = p.vel.normalized() if speed>.1 else Vector2.ZERO
	var selected_shot = int(p.charge) if p.charge>=0 else int(p.shot)
	var overhead = rally and (p.charge>=0 or p.buffer>0) and selected_shot in [0,1,2] and shuttle.z>1.8
	if is_ai and rally and incoming and shuttle.z>2.2: overhead = true
	if p.swing>0: overhead = false
	p.preparation = move_toward(p.preparation,1.0 if overhead else 0.0,dt*6)
	var retreating = p.vel.y*side>.6
	var toward_net = p.vel.y*side<-.6
	# Both athletes are right-handed: a forehand coil does not flip when the ball crosses the head.
	var target_turn = side*(.85*p.preparation if p.preparation>.01 else (.40 if retreating else 0.0))
	var target_hip = target_turn*.63
	var shift = 0.0
	var striking: bool = p.swing>0 and p.stroke!="serve"
	if striking and p.stroke=="overhead":
		var t = clampf(1-p.swing/SWING_TIME,0,1)
		var from: float = p.swing_from
		# Hips open first, shoulders follow, then both return to face the net.
		target_hip = lerpf(from*.63,-p.stroke_side*.12,smoothstep(0,.20,t))
		target_turn = lerpf(from,-p.stroke_side*.30,smoothstep(.03,.38,t))
		var recovery = smoothstep(.58,1,t)
		target_hip = lerpf(target_hip,0,recovery)
		target_turn = lerpf(target_turn,0,recovery)
		shift = sin(t*PI)
	p.body_turn = move_toward(p.body_turn,target_turn,dt*7.5)
	p.hip_turn = move_toward(p.hip_turn,target_hip,dt*9.0)
	p.weight_shift = move_toward(p.weight_shift,shift,dt*10)
	p.split = maxf(0,p.split-dt)
	var net_reach = striking and p.stroke in ["net","lift"] and absf(p.pos.y)<3.2
	var lunging = p.dash>0 or net_reach or (toward_net and absf(p.pos.y)<2.1)
	p.lunge = move_toward(p.lunge,1.0 if lunging else 0.0,dt*(8 if lunging else 4))
	p.footwork = "lunge" if p.lunge>.25 else ("rear_chasse" if retreating else ("chasse" if absf(p.vel.x)>absf(p.vel.y)*1.25 and speed>1.2 else ("run" if speed>2.5 else ("adjust" if speed>.15 else "ready"))))
	if p.jump>.1: p.footwork = "scissor" if striking and p.stroke=="overhead" else "jump"
	var stagger = absf(p.body_turn)*.28
	var spread = .15 + sin(clampf(p.split/.18,0,1)*PI)*.025
	var left = Vector2(-spread*cos(p.hip_turn),-stagger)
	var right = Vector2(spread*cos(p.hip_turn),stagger)
	# Racket-side foot starts behind; mirror the stance for the far athlete.
	if p.weight_shift>0:
		left.y += p.weight_shift*.10
		right.y -= p.weight_shift*.10
	if p.lunge>0:
		var reach: Vector2 = p.reach_dir if net_reach else move
		if reach.length()<.1: reach = Vector2(0,-side)
		if side>0:
			right += reach*.28*p.lunge
			left -= reach*.14*p.lunge
		else:
			left += reach*.28*p.lunge
			right -= reach*.14*p.lunge
	var targets = [p.pos+left,p.pos+right]
	p.lift_l = 0.0
	p.lift_r = 0.0
	if p.jump>.08:
		# Airborne scissor kick exchanges the fore/aft positions without sliding a planted foot.
		var scissor = p.weight_shift*.18
		p.foot_l = targets[0]+Vector2(0,scissor)
		p.foot_r = targets[1]-Vector2(0,scissor)
		p.step_leg = -1
		return
	if p.landing>0 and p.step_leg<0:
		p.foot_l = targets[0]
		p.foot_r = targets[1]
		return
	if p.step_leg<0:
		var distances = [p.foot_l.distance_to(targets[0]),p.foot_r.distance_to(targets[1])]
		var chosen: int = p.next_leg
		if maxf(distances[0],distances[1])<.12 and absf(p.vel.x)>.2:
			chosen = 1 if p.vel.x>0 else 0
		if distances[1-chosen]>distances[chosen]+.18: chosen = 1-chosen
		if distances[chosen]>.12 or (speed>.6 and rally):
			p.step_leg = chosen
			p.step_t = 0.0
			p.step_from = p.foot_l if chosen==0 else p.foot_r
			# Aim where the moving body will be when this foot lands, not where it was.
			var step_duration = lerpf(.20,.13,minf(1,speed/4.5))
			p.step_to = targets[chosen]+move*minf(.75,speed*step_duration*1.15)
			p.next_leg = 1-chosen
	if p.step_leg>=0:
		var duration = lerpf(.20,.13,minf(1,speed/4.5))
		p.step_t = minf(1,p.step_t+dt/duration)
		var foot: Vector2 = p.step_from.lerp(p.step_to,smoothstep(0,1,p.step_t))
		var lift = sin(p.step_t*PI)*(.022 if p.footwork in ["chasse","adjust","rear_chasse"] else .045)
		if p.step_leg==0:
			p.foot_l = foot
			p.lift_l = lift
		else:
			p.foot_r = foot
			p.lift_r = lift
		if p.step_t>=1: p.step_leg = -1
	# Safety reach limit only for long dashes; normal stance foot remains planted.
	p.foot_l = p.pos+(p.foot_l-p.pos).limit_length(.65)
	p.foot_r = p.pos+(p.foot_r-p.pos).limit_length(.65)
	if p.footwork in ["chasse","rear_chasse","ready","adjust"]:
		# Chasse closes and opens the stance; the feet must not cross through each other.
		if p.step_leg==0: p.foot_l.x = minf(p.foot_l.x,p.foot_r.x-.07)
		else: p.foot_r.x = maxf(p.foot_r.x,p.foot_l.x+.07)

static func snapshot(p: Dictionary) -> Dictionary:
	var data = {"left":[p.foot_l.x,p.foot_l.y],"right":[p.foot_r.x,p.foot_r.y],"style":p.footwork}
	for key in POSE_VALUES: data[key] = p[key]
	if p.has("contact"): data.contact = [p.contact.x,p.contact.y,p.contact.z]
	return data

static func receive(p: Dictionary, data: Dictionary) -> void:
	if not data.has("left") or not data.has("right"): return
	p.motion_target = data
	p.footwork = str(data.get("style","ready"))

static func interpolate(p: Dictionary, dt: float) -> void:
	if not p.has("motion_target"): return
	var target: Dictionary = p.motion_target
	var weight = 1-exp(-28*dt)
	p.foot_l = p.foot_l.lerp(Vector2(float(target.left[0]),float(target.left[1])),weight)
	p.foot_r = p.foot_r.lerp(Vector2(float(target.right[0]),float(target.right[1])),weight)
	for key in POSE_VALUES: p[key] = lerpf(float(p[key]),float(target.get(key,0)),weight)

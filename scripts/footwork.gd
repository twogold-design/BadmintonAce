extends RefCounted
## Cosmetic foot plants and a hip-led stroke; never changes shot physics or input.

const SWING_TIME = .48
const POSE_VALUES = ["body_turn","hip_turn","weight_shift","split","lift_l","lift_r","lunge","preparation","service_ready","receive_ready","service_long","heel_l","heel_r","bounce","rescue_weight","rescue_x","rescue_y"]

static func reset(p: Dictionary) -> void:
	p.merge({"foot_l":p.pos+Vector2(-.16,0),"foot_r":p.pos+Vector2(.16,0),
		"lift_l":0.0,"lift_r":0.0,"step_leg":-1,"next_leg":0,"step_t":0.0,
		"step_from":p.pos,"step_to":p.pos,"body_turn":0.0,"hip_turn":0.0,
		"weight_shift":0.0,"split":0.0,"lunge":0.0,"preparation":0.0,"footwork":"ready",
		"stroke_side":1.0,"swing_from":0.0,"reach_dir":Vector2.ZERO},true)
	p.rescue_time=0.0;p.rescue_budget=.74;p.rescue_used=-1;p.rescue_hold=0.0
	p.rescue_weight=0.0;p.rescue_x=0.0;p.rescue_y=0.0
	p.gait_phase = 0.0
	p.service_ready = 0.0
	p.receive_ready = 0.0
	p.service_long = 0.0
	p.heel_l=0.0;p.heel_r=0.0;p.bounce=0.0
	p.gait_active = false
	p.gait_blend = 0.0
	p.gait_support = [true,false]
	p.gait_from = [p.foot_l,p.foot_r]
	p.erase("motion_target")
	p.erase("contact")

static func service_targets(p: Dictionary, index: int, receiving: bool) -> Array:
	# Anatomical left/right, mirrored into world slots for the far player.
	var long_serve = float(p.service_long)
	var left_depth = -.20 if receiving else lerpf(.12,-.20,long_serve)
	var right_depth = .18 if receiving else lerpf(-.14,.18,long_serve)
	var side = 1.0 if index==0 else -1.0
	var left: Vector2 = p.pos+Vector2(-.19,left_depth)*side
	var right: Vector2 = p.pos+Vector2(.19,right_depth)*side
	return [left,right] if index==0 else [right,left]

static func set_service_stance(p: Dictionary, index: int, receiving: bool) -> void:
	p.service_ready = 0.0 if receiving else 1.0
	p.receive_ready = 1.0 if receiving else 0.0
	p.service_long = 0.0
	p.body_turn = (1.0 if index==0 else -1.0)*(.30 if receiving else .08)
	p.hip_turn = p.body_turn*.6
	var feet = service_targets(p,index,receiving)
	p.foot_l=feet[0];p.foot_r=feet[1]
	p.footwork = "receive_ready" if receiving else "serve_short"

static func backhand_turn(p: Dictionary, index: int, shuttle: Vector3) -> float:
	var side=1.0 if index==0 else -1.0
	var local=(Vector2(shuttle.x,shuttle.y)-p.pos)*side
	var facing=atan2(-local.x,-local.y)
	var high=shuttle.z-float(p.jump)>1.9
	var angle=clampf(facing+(1.05 if high else 0.0),1.9 if high else .65,2.6 if high else 1.45)
	return -side*angle

static func hit(p: Dictionary, index: int, shuttle: Vector3, serving: bool) -> void:
	p.stroke_side = (1.0 if index==0 else -1.0) * (-1.0 if p.backhand else 1.0)
	if p.backhand and not serving:
		p.body_turn=backhand_turn(p,index,shuttle)
		p.hip_turn=p.body_turn*.65
		p.preparation=0.0
	p.swing_from = p.body_turn
	p.reach_dir = (Vector2(shuttle.x,shuttle.y)-p.pos).limit_length(1)
	p.swing = SWING_TIME
	p.contact = shuttle
	if serving: p.stroke = "serve"

static func update(p: Dictionary, index: int, dt: float, rally: bool, incoming: bool, shuttle: Vector3, is_ai: bool, service_role: int = 0) -> void:
	var side = 1.0 if index==0 else -1.0
	var speed: float = p.vel.length()
	var move: Vector2 = p.vel.normalized() if speed>.1 else Vector2.ZERO
	# Settle naturally when stopping, serving or lunging; never lock onto toes.
	p.heel_l=move_toward(float(p.heel_l),0,dt*2)
	p.heel_r=move_toward(float(p.heel_r),0,dt*2)
	p.bounce=move_toward(float(p.bounce),0,dt*.12)
	p.service_ready = move_toward(float(p.service_ready),1.0 if service_role==1 else 0.0,dt*7)
	p.receive_ready = move_toward(float(p.receive_ready),1.0 if service_role==2 else 0.0,dt*7)
	if service_role==1 and p.charge>=0:
		p.service_long = move_toward(float(p.service_long),1.0 if p.charge==0 else 0.0,dt*5)
	var selected_shot = int(p.charge) if p.charge>=0 else int(p.shot)
	var overhead = rally and (p.charge>=0 or p.buffer>0) and selected_shot in [0,1,2] and shuttle.z>1.8
	if is_ai and rally and incoming and shuttle.z>2.2: overhead = true
	# Read an incoming rear-court high ball before the player holds a shot key.
	var rear_ready = rally and incoming and p.pos.y*side>3.6 and shuttle.y*side>1.0 and shuttle.z>1.9
	if rear_ready: overhead = true
	if p.swing>0: overhead = false
	var preparation_target = (0.8 if rear_ready and p.charge<0 and p.buffer<=0 and not is_ai else 1.0) if overhead else 0.0
	p.preparation = move_toward(p.preparation,preparation_target,dt*6)
	var retreating = p.vel.y*side>.6
	# Both athletes are right-handed: a forehand coil does not flip when the ball crosses the head.
	var target_turn = side*(.85*p.preparation if p.preparation>.01 else (.40 if retreating else 0.0))
	if service_role>0: target_turn = side*(.30 if service_role==2 else lerpf(.08,.58,p.service_long))
	var target_hip = target_turn*.63
	# Fast lateral travel is a turned running step; keeping the hips square to
	# the net while translating at sprint speed makes both legs trail sideways.
	if speed>2.4 and not overhead and not retreating and p.swing<=0:
		var local_move=move*side
		var heading=clampf(atan2(local_move.x,-local_move.y),-1.48,1.48)
		var amount=smoothstep(2.4,3.8,speed)
		target_hip=lerpf(target_hip,side*heading,amount)
		target_turn=lerpf(target_turn,side*heading*.72,amount)
	var rescue_turn = p.rescue_time>0 or p.rescue_hold>0
	if rescue_turn:
		var rescue_direction=Vector2(p.rescue_x,p.rescue_y)*side
		var heading=clampf(atan2(rescue_direction.x,-rescue_direction.y),-1.45,1.45)
		target_turn=side*heading*.85
		target_hip=target_turn*.65
	var backhand_ready = rally and incoming and not (p.swing>0) and shuttle.y*side>.2 and (shuttle.x-p.pos.x)*side<-.25 and p.pos.distance_to(Vector2(shuttle.x,shuttle.y))<2.3
	if backhand_ready:
		target_turn=backhand_turn(p,index,shuttle)
		target_hip=target_turn*.65
	var shift = 0.0
	var striking: bool = p.swing>0 and p.stroke!="serve"
	if striking and p.backhand:
		var t=clampf(1-p.swing/SWING_TIME,0,1)
		var recovery=smoothstep(.40,1,t)
		target_turn=lerpf(float(p.swing_from),0,recovery)
		target_hip=target_turn*.65
	elif striking and p.stroke=="overhead":
		var t = clampf(1-p.swing/SWING_TIME,0,1)
		var from: float = p.swing_from
		# Hips open first, shoulders follow, then both return to face the net.
		target_hip = lerpf(from*.63,-p.stroke_side*.12,smoothstep(0,.20,t))
		target_turn = lerpf(from,-p.stroke_side*.18,smoothstep(.03,.38,t))
		var recovery = smoothstep(.58,1,t)
		target_hip = lerpf(target_hip,0,recovery)
		target_turn = lerpf(target_turn,0,recovery)
		# Transfer onto the front/left leg, hold through the follow-through,
		# then ease back to centre instead of rocking straight back again.
		shift = smoothstep(0,.40,t)*(1-smoothstep(.65,1,t))
	p.body_turn = move_toward(p.body_turn,target_turn,dt*(12 if rescue_turn or backhand_ready else 7.5))
	p.hip_turn = move_toward(p.hip_turn,target_hip,dt*(3.0 if speed<.6 and not striking else 9.0))
	p.weight_shift = move_toward(p.weight_shift,shift,dt*10)
	p.split = maxf(0,p.split-dt)
	var net_reach = striking and p.stroke in ["net","lift"] and absf(p.pos.y)<3.2
	var rescue = p.rescue_time>0 or p.rescue_hold>0
	p.rescue_weight=move_toward(float(p.rescue_weight),1.0 if rescue else 0.0,dt*(12 if rescue else 5))
	var lunging = p.dash>0 or net_reach or rescue
	p.lunge = move_toward(p.lunge,1.0 if lunging else 0.0,dt*(8 if lunging else 4))
	p.footwork = "lunge" if p.lunge>.25 else ("rear_chasse" if retreating else ("chasse" if absf(p.vel.x)>absf(p.vel.y)*1.25 and speed>.4 and speed<=2.6 else ("run" if speed>2.5 else ("adjust" if speed>.15 else "ready"))))
	var chasse_target=(1-smoothstep(2.2,3.2,speed)) if absf(p.vel.x)>absf(p.vel.y)*1.25 and speed>.4 else 0.0
	p.gait_blend=move_toward(float(p.gait_blend),chasse_target,dt*4)
	if p.jump>.1: p.footwork = "scissor" if striking and p.stroke=="overhead" else "jump"
	# A modest front/back stagger retains a broad support base after turning
	# back toward the net; the old long stagger visually crossed the legs.
	var stagger = absf(p.body_turn)*.13*maxf(p.preparation,p.weight_shift)
	var spread = .18 + sin(clampf(p.split/.18,0,1)*PI)*.025
	spread += .03*maxf(p.preparation,p.weight_shift)
	spread+=.10*p.gait_blend
	var across=Vector2(cos(p.hip_turn),side*sin(p.hip_turn))
	var left = -across*spread+across.orthogonal()*stagger
	var right = across*spread-across.orthogonal()*stagger
	if p.lunge>0:
		var reach: Vector2 = Vector2(p.rescue_x,p.rescue_y) if p.rescue_weight>.1 else (p.reach_dir if net_reach else move)
		if reach.length()<.1: reach = Vector2(0,-side)
		var right_leads=side>0
		if p.rescue_weight>.1 and absf(reach.dot(across))>.35:right_leads=reach.dot(across)>0
		if right_leads:
			right += reach*.28*p.lunge
			left -= reach*.14*p.lunge
		else:
			left += reach*.28*p.lunge
			right -= reach*.14*p.lunge
	var targets = [p.pos+left,p.pos+right]
	if service_role>0:
		targets = service_targets(p,index,service_role==2)
		p.footwork = "receive_ready" if service_role==2 else ("serve_long" if p.service_long>.5 else "serve_short")
	var old_lifts=[p.lift_l,p.lift_r]
	p.lift_l = 0.0
	p.lift_r = 0.0
	if p.jump>.08:
		# Airborne scissor kick exchanges the fore/aft positions without sliding a planted foot.
		var scissor = p.weight_shift*.18
		p.foot_l = targets[0]+Vector2(0,scissor)
		p.foot_r = targets[1]-Vector2(0,scissor)
		p.step_leg = -1
		p.gait_active = false
		return
	if striking and p.stroke=="overhead" and speed<=.35 and p.lunge<.1:
		# Rotate over the established stance. Moving the supporting left foot
		# to follow every hip angle made the body look as if it was falling.
		p.lift_l = move_toward(float(old_lifts[0]),0,dt*.6)
		p.lift_r = move_toward(float(old_lifts[1]),0,dt*.6)
		p.step_leg = -1
		p.gait_active = false
		return
	if speed>.35:
		moving_feet(p,dt,targets,across)
		return
	if p.gait_active:
		p.gait_active=false
		p.step_leg=-1
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
		if distances[chosen]>.045:
			p.step_leg = chosen
			p.step_t = 0.0
			p.step_from = p.foot_l if chosen==0 else p.foot_r
			p.step_from_lift=old_lifts[chosen]
			# Recover one foot at a time into the turning ready stance.
			p.step_to = targets[chosen]
			p.next_leg = 1-chosen
	if p.step_leg>=0:
		var duration = lerpf(.20,.13,minf(1,speed/4.5))
		p.step_t = minf(1,p.step_t+dt/duration)
		p.step_to=targets[p.step_leg]
		var foot: Vector2 = p.step_from.lerp(p.step_to,smoothstep(0,1,p.step_t))
		var lift = sin(p.step_t*PI)*.055+float(p.get("step_from_lift",0))*(1-p.step_t)
		if p.step_leg==0:
			p.foot_l = foot
			p.lift_l = lift
		else:
			p.foot_r = foot
			p.lift_r = lift
		if p.step_t>=1: p.step_leg = -1
	var separation: float=(p.foot_r-p.foot_l).dot(across)
	if separation<.18:
		if p.lift_l>=p.lift_r:p.foot_l-=across*(.18-separation)
		else:p.foot_r+=across*(.18-separation)

static func moving_feet(p: Dictionary, dt: float, targets: Array, across: Vector2) -> void:
	var speed: float=p.vel.length()
	var direction: Vector2=p.vel.normalized()
	var blend: float=p.gait_blend
	var duty=lerpf(lerpf(.42,.34,smoothstep(5.5,7,speed)),.52,blend)
	# Leaving the receiving stance at walking/chasse speed must keep support
	# while the wider running cycle blends in.
	duty=lerpf(.52,duty,smoothstep(2.4,3.2,speed))
	var period=clampf(.46-speed*.028,.22,.46)
	period=lerpf(period,clampf(.27/(speed*duty),.25,.58),blend)
	# Stride follows ground speed and contact time. The short flight between
	# running contacts avoids dragging a planted leg beyond its actual reach.
	var half_stride=minf(.38,speed*period*duty*.5)
	half_stride=lerpf(half_stride,minf(.16,half_stride),blend)
	if not p.gait_active:
		p.gait_active=true
		p.gait_phase=0.0 if p.vel.x>=0 else .5
		if maxf(float(p.get("service_ready",0)),float(p.get("receive_ready",0)))>.01:
			# The split stance already places a foot behind the centre: shorten
			# this first support interval so it does not overextend before landing.
			p.gait_phase+=.12
		p.gait_support=[p.gait_phase<duty,fmod(p.gait_phase+.5,1.0)<duty]
		p.gait_from=[p.foot_l,p.foot_r]
	p.gait_phase=fmod(p.gait_phase+dt/period,1.0)
	var feet=[p.foot_l,p.foot_r]
	var previous=[p.foot_l,p.foot_r]
	var lifts=[0.0,0.0]
	var heels=[0.0,0.0]
	for leg in range(2):
		var phase=fmod(p.gait_phase+leg*.5,1.0)
		var supporting=phase<duty
		if supporting:
			# Keep the last touchdown in world space throughout stance.
			p.gait_from[leg]=feet[leg]
			var support_t=phase/duty
			heels[leg]=lerpf(.18,.08,smoothstep(0,.35,support_t))+.27*smoothstep(.45,1,support_t)
		else:
			if p.gait_support[leg]:p.gait_from[leg]=feet[leg]
			var t=(phase-duty)/(1.0-duty)
			var remaining=(1.0-phase)*period
			var landing: Vector2=targets[leg]+direction*half_stride+p.vel*remaining
			feet[leg]=p.gait_from[leg].lerp(landing,smoothstep(0,1,t))
			lifts[leg]=sin(t*PI)*lerpf(.095,.055,blend)
			heels[leg]=lerpf(.35,.12,smoothstep(0,.40,t))+.06*smoothstep(.70,1,t)
		p.gait_support[leg]=supporting
	for leg in range(2):
		feet[leg]=previous[leg].move_toward(feet[leg],dt*(3.5+speed*2.0))
		var offset: Vector2=feet[leg]-p.pos
		if offset.length()>.55:
			# An abrupt dash/reversal releases an overextended stance immediately.
			feet[leg]=p.pos+offset.limit_length(.55)
			p.gait_support[leg]=false
			p.gait_from[leg]=feet[leg]
			lifts[leg]=maxf(lifts[leg],.035)
	# Each foot keeps its own lane. Pairwise pushing would switch the correction
	# between feet midway through flight and produce a visible sideways snap.
	for leg in range(2):
		var sign_= -1.0 if leg==0 else 1.0
		var lateral: float=(feet[leg]-p.pos).dot(across)*sign_
		if lateral<.095:
			feet[leg]+=across*sign_*(.095-lateral)
			lifts[leg]=maxf(lifts[leg],.035)
	p.foot_l=feet[0];p.foot_r=feet[1]
	p.lift_l=lifts[0];p.lift_r=lifts[1]
	var spring=(1-float(p.lunge))*(1-smoothstep(.05,.15,float(p.jump)))
	p.heel_l=lerpf(float(p.heel_l),heels[0]*lerpf(1,.85,blend)*spring,1-exp(-40*dt))
	p.heel_r=lerpf(float(p.heel_r),heels[1]*lerpf(1,.85,blend)*spring,1-exp(-40*dt))
	p.bounce=lerpf(float(p.bounce),-.014*pow(sin(TAU*p.gait_phase),2)*spring,1-exp(-24*dt))
	p.step_leg=0 if lifts[0]>lifts[1] else 1

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

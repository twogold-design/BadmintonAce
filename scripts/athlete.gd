extends RefCounted
## Articulated, shaded vector athletes; the local player faces away from the camera.

static func oval(c: Node2D, at: Vector2, radius: Vector2, color: Color, angle: float = 0.0) -> void:
	var points = PackedVector2Array()
	for k in range(32):
		points.append(at + (Vector2(cos(k * TAU / 32), sin(k * TAU / 32)) * radius).rotated(angle))
	c.draw_colored_polygon(points, color)

static func segment(c: Node2D, a: Vector2, b: Vector2, ra: float, rb: float, color: Color) -> void:
	var side = (b - a).normalized().orthogonal()
	c.draw_colored_polygon(PackedVector2Array([a+side*ra,b+side*rb,b-side*rb,a-side*ra]),color)
	c.draw_circle(a,ra,color)
	c.draw_circle(b,rb,color)
	c.draw_line(a-side*ra*.42,b-side*rb*.42,color.lightened(.16),maxf(.7,ra*.4),true)

static func shoe(c: Node2D, at: Vector2, s: float, back: bool, tilt: float, accent: Color) -> void:
	var toe = at + Vector2(tilt, -4 if back else 4)*s
	oval(c, toe+Vector2(0,2)*s, Vector2(8,4)*s,Color("091c25"),tilt*.035)
	oval(c, toe,Vector2(7.8,4.4)*s,Color("e6eee8"),tilt*.035)
	c.draw_line(toe+Vector2(-5,1)*s,toe+Vector2(5,1)*s,Color("a5bab5"),1.4*s,true)
	c.draw_line(toe+Vector2(-4,-1.2)*s,toe+Vector2(2,-2.3)*s,accent,1.9*s,true)
	for k in range(3):
		c.draw_line(toe+Vector2(-1.5,-3+k*1.6)*s,toe+Vector2(2,-3+k*1.6)*s,Color("fafbf4"),.7*s,true)

static func racket(c: Node2D, hand: Vector2, angle: float, s: float, accent: Color) -> void:
	var axis = Vector2.from_angle(angle)
	var side = axis.orthogonal()
	var shaft = hand + axis*26*s
	c.draw_line(hand,shaft,Color("081b25"),3.5*s,true)
	c.draw_line(hand,shaft,Color("b7d0d2"),1.7*s,true)
	c.draw_line(hand,hand+axis*8*s,Color("24343f"),4*s,true)
	for k in range(4):
		var pos = hand+axis*(1+k*1.8)*s
		c.draw_line(pos-side*1.5*s,pos+side*1.5*s,Color("657d82"),.65*s,true)
	var center = shaft+axis*12.5*s
	oval(c,center,Vector2(14.7,10.2)*s,Color(.02,.10,.13,.22),angle)
	var edge = PackedVector2Array()
	for k in range(49): edge.append(center+Vector2(cos(k*TAU/48)*14.7,sin(k*TAU/48)*10.2).rotated(angle)*s)
	c.draw_polyline(edge,Color("112a35"),3.5*s,true)
	c.draw_polyline(edge,accent,2*s,true)
	for k in range(-3,4):
		var off = k*2.5
		var length = 14*sqrt(maxf(0,1-pow(off/10,2)))
		c.draw_line(center+(axis*-length+side*off)*s,center+(axis*length+side*off)*s,Color(.88,.98,.93,.55),.65*s,true)
	for k in range(-4,5):
		var off = k*2.7
		var length = 9.5*sqrt(maxf(0,1-pow(off/14.7,2)))
		c.draw_line(center+(axis*off-side*length)*s,center+(axis*off+side*length)*s,Color(.88,.98,.93,.55),.65*s,true)
	c.draw_line(center+Vector2(8,-8).rotated(angle)*s,center+Vector2(12,-5).rotated(angle)*s,Color("ffffff"),1.4*s,true)

static func paint(c: Node2D, p: Dictionary, index: int, ground: Vector2, s: float, time: float) -> void:
	var in_match = c.screen=="game" and not p.get("preview",false)
	var view_sign: float = c._view_sign() if in_match else 1.0
	var back = index == (c._local_player_index() if in_match else 0)
	var turn: float = float(p.get("body_turn",0))*view_sign if in_match else 0.0
	var hip_turn: float = float(p.get("hip_turn",0))*view_sign if in_match else 0.0
	var female = p.get("avatar","male")=="female"
	var limb_scale = .88 if female else 1.0
	var hand_side = 1.0 if back else -1.0
	var accent = Color("cdf578") if index==0 else Color("ff947e")
	var skin = Color("dba476") if index==0 else Color("d9a282")
	var shade = skin.darkened(.18)
	var speed: float = minf(1.0,p.vel.length()/4.5)
	var stride = sin(float(p.step)*2)
	var stride2 = cos(float(p.step)*2)
	var breath = sin(time*3.5+index)*.65
	var lunge: float = float(p.get("lunge",0)) if in_match else 0.0
	var jump: float = p.jump
	var stroke: String = p.get("stroke","overhead")
	var progress: float = clampf(1-p.swing/.48,0,1)
	var follow: float = sin(progress*PI) if p.swing>0 else 0.0
	var ready = p.charge>=0 or p.buffer>0
	var lean: float = p.vel.x*view_sign*1.4 + follow*hand_side*(7 if stroke=="overhead" else 4)
	var tuck: float = minf(1,jump)*7
	var pos = ground-Vector2(0,jump*55*s)
	var split_crouch = sin(clampf(float(p.get("split",0))/.18,0,1)*PI)*4 if in_match else 0.0
	var crouch: float = split_crouch + lunge*5 + sin(clampf(float(p.get("landing",0))/.18,0,1)*PI)*6 + (2.5 if ready else 0)
	var bob = absf(stride2)*1.2*speed + breath-crouch
	var hips = pos + Vector2(lean*.25,-36-bob+lunge*6)*s
	var chest = pos + Vector2(lean,-64-bob+lunge*11)*s
	chest.x += sin(turn)*4*s
	var head = chest + Vector2(lean*.16,-20)*s
	var hair_sway: float = sin(time*4.5+float(p.step))*3 + p.vel.x*1.1 + follow*hand_side*5
	if female:
		# Tied hair follows movement; rendered behind the body in the front view.
		ponytail(c,head,s,hair_sway,accent,back)
	var foot_l = pos+Vector2(-12+stride*7*speed,-maxf(0,stride)*5*speed-tuck)*s
	var foot_r = pos+Vector2(12-stride*7*speed,-maxf(0,-stride)*5*speed-tuck*1.4)*s
	if in_match and p.has("foot_l"):
		var left_world: Vector2 = p.foot_l if view_sign>0 else p.foot_r
		var right_world: Vector2 = p.foot_r if view_sign>0 else p.foot_l
		var left_lift: float = p.lift_l if view_sign>0 else p.lift_r
		var right_lift: float = p.lift_r if view_sign>0 else p.lift_l
		foot_l = c._floor(left_world)-Vector2(0,jump*55*s+left_lift*75*s)
		foot_r = c._floor(right_world)-Vector2(0,jump*55*s+right_lift*75*s)
	var hip_l = body_point(hips,Vector2(-6,0),s,hip_turn)
	var hip_r = body_point(hips,Vector2(6,0),s,hip_turn)
	var knee_l = knee(hip_l,foot_l-Vector2(0,5)*s,17*s,18*s,-1)
	var knee_r = knee(hip_r,foot_r-Vector2(0,5)*s,17*s,18*s,1)
	# Contact shadow / ambient occlusion, separate from the airborne body.
	oval(c,ground,Vector2(29,8)*s,Color(0,0,0,.12))
	oval(c,ground,Vector2(22,5.5)*s,Color(0,0,0,.20))
	for leg in [[hip_l,knee_l,foot_l],[hip_r,knee_r,foot_r]]:
		segment(c,leg[0],leg[1],5.9*s*limb_scale,4.4*s*limb_scale,shade)
		segment(c,leg[1],leg[2]-Vector2(0,5)*s,4.3*s*limb_scale,2.8*s*limb_scale,skin)
		oval(c,leg[1]+Vector2(0,-1)*s,Vector2(3.1,2.4)*s,skin.lightened(.08))
		segment(c,leg[2]-Vector2(0,10)*s,leg[2]-Vector2(0,3)*s,3.3*s,3.6*s,Color("e6eee7"))
		c.draw_line(leg[2]+Vector2(-3,-8)*s,leg[2]+Vector2(3,-8)*s,accent,1.5*s,true)
	shoe(c,foot_l,s,back,-2.0+sin(hip_turn)*4,accent)
	shoe(c,foot_r,s,back,2.0+sin(hip_turn)*4,accent)
	# Athletic shorts, split hems and fabric folds.
	var shorts = PackedVector2Array([body_point(hips,Vector2(-12,-5),s,hip_turn),body_point(hips,Vector2(12,-5),s,hip_turn),body_point(hips,Vector2(15,12),s,hip_turn),body_point(hips,Vector2(3,14),s,hip_turn),body_point(hips,Vector2(0,5),s,hip_turn),body_point(hips,Vector2(-3,14),s,hip_turn),body_point(hips,Vector2(-15,12),s,hip_turn)])
	c.draw_colored_polygon(shorts,Color("142c38"))
	c.draw_line(body_point(hips,Vector2(-11,-2),s,hip_turn),body_point(hips,Vector2(-12,10),s,hip_turn),accent.darkened(.15),2*s,true)
	c.draw_line(body_point(hips,Vector2(11,-2),s,hip_turn),body_point(hips,Vector2(12,10),s,hip_turn),accent.darkened(.15),2*s,true)
	c.draw_line(body_point(hips,Vector2(-6,2),s,hip_turn),body_point(hips,Vector2(-8,10),s,hip_turn),Color("35505a"),1*s,true)
	c.draw_line(body_point(hips,Vector2(6,2),s,hip_turn),body_point(hips,Vector2(8,10),s,hip_turn),Color("35505a"),1*s,true)
	if female:
		# Full-coverage sports skort over the existing fitted shorts.
		var hem_sway = stride*1.8*speed
		c.draw_colored_polygon(PackedVector2Array([body_point(hips,Vector2(-11,-4),s,hip_turn),body_point(hips,Vector2(11,-4),s,hip_turn),body_point(hips,Vector2(18+hem_sway,17),s,hip_turn),body_point(hips,Vector2(0,19),s,hip_turn),body_point(hips,Vector2(-18+hem_sway,17),s,hip_turn)]),Color("183b47"))
		c.draw_line(body_point(hips,Vector2(-17+hem_sway,16),s,hip_turn),body_point(hips,Vector2(0,18),s,hip_turn),accent,2*s,true)
		c.draw_line(body_point(hips,Vector2(0,18),s,hip_turn),body_point(hips,Vector2(17+hem_sway,16),s,hip_turn),accent,2*s,true)
		for fold in [-1,0,1]:
			c.draw_line(body_point(hips,Vector2(fold*7,1),s,hip_turn),body_point(hips,Vector2(fold*12+hem_sway,15),s,hip_turn),Color("365666"),1*s,true)
	# Non-racket arm balances the stroke; on the back view it is behind the torso.
	var free_shoulder = body_point(chest,Vector2(-hand_side*13,3),s,turn)
	var free_elbow = body_point(chest,Vector2(-hand_side*(23+lunge*4),17-stride*3*speed),s,turn)
	var free_hand = body_point(chest,Vector2(-hand_side*26,24-stride*5*speed),s,turn)
	if (ready and int(p.charge) in [0,2]) or (p.swing>.20 and stroke=="overhead"):
		free_elbow = body_point(chest,Vector2(-hand_side*22,-8),s,turn)
		free_hand = body_point(chest,Vector2(-hand_side*18,-20),s,turn)
	segment(c,free_shoulder,free_elbow,4.5*s*limb_scale,3.6*s*limb_scale,shade)
	segment(c,free_elbow,free_hand,3.6*s*limb_scale,2.8*s*limb_scale,skin)
	oval(c,free_hand,Vector2(3.3,4)*s,skin)
	# Contoured jersey with side panels, shoulder piping, collar and seams.
	var torso = PackedVector2Array([body_point(chest,Vector2(-12,-3),s,turn),body_point(chest,Vector2(-17,4),s,turn),body_point(chest,Vector2(-12,13),s,turn),body_point(hips,Vector2(-11,0),s,hip_turn),body_point(hips,Vector2(11,0),s,hip_turn),body_point(chest,Vector2(12,13),s,turn),body_point(chest,Vector2(17,4),s,turn),body_point(chest,Vector2(12,-3),s,turn)])
	if female:
		torso = PackedVector2Array([body_point(chest,Vector2(-10,-3),s,turn),body_point(chest,Vector2(-12,4),s,turn),body_point(chest,Vector2(-10,12),s,turn),body_point(hips,Vector2(-10,0),s,hip_turn),body_point(hips,Vector2(10,0),s,hip_turn),body_point(chest,Vector2(10,12),s,turn),body_point(chest,Vector2(12,4),s,turn),body_point(chest,Vector2(10,-3),s,turn)])
	c.draw_colored_polygon(torso,accent.darkened(.07))
	c.draw_colored_polygon(PackedVector2Array([body_point(chest,Vector2(-10,-2),s,turn),body_point(chest,Vector2(3,-1),s,turn),body_point(hips,Vector2(3,-1),s,hip_turn),body_point(hips,Vector2(-7,0),s,hip_turn)]),accent)
	c.draw_colored_polygon(PackedVector2Array([body_point(chest,Vector2(9,5),s,turn),body_point(chest,Vector2(13,8),s,turn),body_point(hips,Vector2(11,0),s,hip_turn),body_point(hips,Vector2(7,-1),s,hip_turn)]),accent.darkened(.28))
	c.draw_line(body_point(chest,Vector2(-11,-2),s,turn),body_point(chest,Vector2(-15,4),s,turn),Color("f4f7eb"),2*s,true)
	c.draw_line(body_point(chest,Vector2(11,-2),s,turn),body_point(chest,Vector2(15,4),s,turn),Color("f4f7eb"),2*s,true)
	if female:
		for side in [-1,1]:
			c.draw_line(body_point(chest,Vector2(side*10,-2),s,turn),body_point(chest,Vector2(side*11,10),s,turn),Color("f4f7eb"),2*s,true)
		if not back:
			c.draw_line(body_point(chest,Vector2(-8,7),s,turn),body_point(chest,Vector2(0,11),s,turn),Color("f4f7eb"),1.5*s,true)
			c.draw_line(body_point(chest,Vector2(0,11),s,turn),body_point(chest,Vector2(8,7),s,turn),Color("f4f7eb"),1.5*s,true)
	c.draw_line(body_point(hips,Vector2(-10,-1),s,hip_turn),body_point(hips,Vector2(10,-1),s,hip_turn),accent.darkened(.4),1.4*s,true)
	c.draw_line(body_point(hips,Vector2(-6,-7),s,hip_turn),body_point(hips,Vector2(5,-5),s,hip_turn),accent.darkened(.2),.8*s,true)
	segment(c,body_point(chest,Vector2(0,-3),s,turn),head+Vector2(0,9)*s,4.5*s,4*s,shade)
	c.draw_arc(body_point(chest,Vector2(0,-3),s,turn),6*s,0,PI,16,Color("163139"),2.5*s,true)
	if back:
		c._center(body_point(chest,Vector2(0,8),s,turn),"ACE",int(6.5*s),Color("203c31"))
		c._center(body_point(chest,Vector2(0,24),s,turn),"01" if index==0 else "02",int(15*s),Color("203c31"))
	else:
		c._center(body_point(chest,Vector2(0,19),s,turn),"ACE",int(9*s),Color("492d2b"))
		c.draw_circle(body_point(chest,Vector2(-7,5),s,turn),2*s,Color("f6e6c6"))
	# Right-handed athlete: the far player's racket is on screen-left.
	var shoulder = body_point(chest,Vector2(hand_side*14,3),s,turn)
	var elbow = body_point(chest,Vector2(hand_side*23,13),s,turn)
	var hand = body_point(chest,Vector2(hand_side*29,7),s,turn)
	var angle = -.90 if back else -2.24
	if ready:
		var overhead_ready = int(p.charge) in [0,2] or (p.buffer>0 and int(p.shot) in [0,2])
		elbow = body_point(chest,Vector2(hand_side*23,-8 if overhead_ready else 17),s,turn)
		hand = body_point(chest,Vector2(hand_side*17,-23 if overhead_ready else 24),s,turn)
		angle = -1.7-hand_side*.35 if overhead_ready else -.3*hand_side
	if p.swing > 0:
		var t: float = progress
		var sweep = 1.0-pow(1.0-t,2.4)
		var swing = lerpf(-1.65,.95,sweep)
		if stroke=="serve": swing = lerpf(.6,-1.0,sweep)
		elif stroke=="net": swing = lerpf(-.35,-1.05,sweep)
		elif stroke=="lift": swing = lerpf(.65,-1.5,sweep)
		elif stroke=="drive": swing = lerpf(-.4,.45,sweep)
		angle = swing if back else PI-swing
		if p.backhand: angle = PI-angle
		hand = shoulder+Vector2.from_angle(angle)*29*s
		elbow = shoulder+Vector2.from_angle(angle-hand_side*.4)*16*s
		if t < .65:
			c.draw_arc(shoulder,55*s,angle-.34,angle+.34,24,Color(accent,.20),6*s,true)
			c.draw_arc(shoulder,55*s,angle-.22,angle+.22,20,Color(accent,.55),2*s,true)
	segment(c,shoulder,elbow,4.6*s*limb_scale,3.5*s*limb_scale,skin)
	segment(c,elbow,hand,3.7*s*limb_scale,2.7*s*limb_scale,skin)
	var wrist = hand.lerp(elbow,.16)
	c.draw_line(wrist-(hand-elbow).normalized().orthogonal()*3.5*s,wrist+(hand-elbow).normalized().orthogonal()*3.5*s,Color("f1f3e8"),4*s,true)
	racket(c,hand,angle,s,accent)
	oval(c,hand,Vector2(3.3,4)*s,skin.lightened(.07),angle)
	# Distinct front/back heads: no eyes or face are rendered on P1's rear view.
	oval(c,head+Vector2(-8.8,1)*s,Vector2(2,3.6)*s,shade)
	oval(c,head+Vector2(8.8,1)*s,Vector2(2,3.6)*s,shade)
	if back:
		oval(c,head+Vector2(0,3)*s,Vector2(8.2,9.5)*s,shade)
		oval(c,head+Vector2(0,-2)*s,Vector2(10.2,11.5)*s,Color("101e29"))
		oval(c,head+Vector2(-2,-5)*s,Vector2(7.5,6.5)*s,Color("213747"))
		for k in range(5):
			c.draw_line(head+Vector2(-6+k*2.7,-10)*s,head+Vector2(-5+k*2.5,-3)*s,Color("2b4250"),.8*s,true)
		c.draw_arc(head+Vector2(0,-1)*s,9.5*s,0,PI,20,Color("ecf3e9"),2.4*s,true)
		c.draw_colored_polygon(PackedVector2Array([head+Vector2(3,7)*s,head+Vector2(8,7)*s,head+Vector2(9,17)*s,head+Vector2(5,12)*s]),Color("d3e3db"))
		c.draw_line(head+Vector2(-4,9)*s,head+Vector2(4,9)*s,Color("172c36"),2*s,true)
		if female:
			oval(c,head+Vector2(0,-3)*s,Vector2(10,11)*s,Color("302b32"))
			for strand in [-1,0,1]:
				c.draw_line(head+Vector2(strand*4,-12)*s,head+Vector2(strand*2,0)*s,Color("51434a"),1*s,true)
			ponytail(c,head,s,hair_sway,accent,true)
	else:
		oval(c,head,Vector2(9.3,11.8)*s,skin)
		oval(c,head+Vector2(-3,-1)*s,Vector2(5.7,8.4)*s,skin.lightened(.12))
		c.draw_arc(head+Vector2(0,-4)*s,8.4*s,PI,TAU,24,Color("14232e"),5.4*s,true)
		c.draw_colored_polygon(PackedVector2Array([head+Vector2(-9,-7)*s,head+Vector2(5,-12)*s,head+Vector2(10,-4)*s,head+Vector2(3,-6)*s,head+Vector2(-3,-3)*s]),Color("14232e"))
		c.draw_line(head+Vector2(-7,-2)*s,head+Vector2(-2,-1)*s,Color("503f37"),1.3*s,true)
		c.draw_line(head+Vector2(2,-1)*s,head+Vector2(7,-2)*s,Color("503f37"),1.3*s,true)
		for x in [-4,4]:
			oval(c,head+Vector2(x,1)*s,Vector2(2,1.2)*s,Color("fff3dc"))
			c.draw_circle(head+Vector2(x,1.4)*s,.9*s,Color("172a35"))
		c.draw_line(head+Vector2(.7,2)*s,head+Vector2(1.4,5)*s,shade,1*s,true)
		c.draw_line(head+Vector2(-2,7.5)*s,head+Vector2(2,7.5)*s,Color("926350"),1*s,true)
		c.draw_circle(head+Vector2(9,-7)*s,4*s,Color("172a35"))
		if female:
			c.draw_arc(head+Vector2(0,-4)*s,8.7*s,PI,TAU,24,Color("302b32"),5*s,true)
			c.draw_colored_polygon(PackedVector2Array([head+Vector2(-9,-6)*s,head+Vector2(-1,-13)*s,head+Vector2(8,-9)*s,head+Vector2(3,-5)*s,head+Vector2(-6,-1)*s]),Color("302b32"))
			c.draw_line(head+Vector2(-7,-7)*s,head+Vector2(-3,-3)*s,Color("69515a"),1.1*s,true)
			c.draw_line(head+Vector2(8,-5)*s,head+Vector2(8,5)*s,Color("302b32"),2.6*s,true)

static func ponytail(c: Node2D, head: Vector2, s: float, sway: float, accent: Color, back: bool) -> void:
	var tie = head+Vector2(2 if back else 7,-7)*s
	var bend = tie+Vector2(10+sway*.4,11)*s
	var tip = tie+Vector2(13+sway,30)*s
	segment(c,tie,bend,5*s,5.5*s,Color("302b32"))
	segment(c,bend,tip,5.5*s,1.5*s,Color("302b32"))
	c.draw_line(tie+Vector2(2,-1)*s,bend+Vector2(2,-1)*s,Color("69515a"),1.4*s,true)
	c.draw_line(bend+Vector2(2,-1)*s,tip,Color("51434a"),1.1*s,true)
	oval(c,tie,Vector2(5,2.4)*s,accent)

static func body_point(origin: Vector2, offset: Vector2, scale: float, yaw: float) -> Vector2:
	return origin+Vector2(offset.x*cos(yaw),offset.y+offset.x*sin(yaw)*.4)*scale

static func knee(hip: Vector2, ankle: Vector2, upper: float, lower: float, bend: float) -> Vector2:
	var delta = ankle-hip
	# Perspective changes projected leg length; keep a soft knee on long steps.
	var stretch = maxf(1.0,delta.length()/(upper+lower)*1.025)
	upper *= stretch
	lower *= stretch
	var distance = clampf(delta.length(),.01,upper+lower-.01)
	var axis = delta.normalized()
	var along = (upper*upper-lower*lower+distance*distance)/(2*distance)
	var height = sqrt(maxf(0,upper*upper-along*along))
	return hip+axis*along+axis.orthogonal()*height*bend

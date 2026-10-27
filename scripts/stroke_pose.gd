extends RefCounted
## Angles for upper arm, forearm, racket, and the balancing arm.
## The ball is hit at swing=SWING_TIME: the animation starts at contact,
## follows across the body, and returns to ready without replaying a backswing.

const READY = [58.0,-75.0,-68.0,115.0,25.0]
const COIL = [-25.0,-125.0,65.0,-145.0,-100.0]

static func mix_pose(a: Array, b: Array, weight: float) -> Array:
	var result = []
	for i in range(5): result.append(lerpf(float(a[i]),float(b[i]),weight))
	return result

static func sample(p: Dictionary, preparation: float) -> Array:
	var ready = READY.duplicate()
	var travel = minf(1,p.vel.length()/4.5)
	ready[3] += sin(float(p.step)*1.2)*8*travel
	ready[4] -= sin(float(p.step)*1.2)*10*travel
	if p.swing<=0: return mix_pose(ready,COIL,preparation)
	var t = clampf(1-p.swing/.48,0,1)
	var contact: Array
	var follow: Array
	var settle: Array
	match str(p.get("stroke","overhead")):
		"overhead":
			contact = [-85.0,-78.0,-82.0,110.0,-30.0]
			follow = [130.0,155.0,132.0,100.0,-25.0]
			settle = [85.0,155.0,160.0,115.0,25.0]
			if p.get("backhand",false):
				contact = [-125.0,-65.0,-65.0,115.0,25.0]
				follow = [20.0,-5.0,-10.0,130.0,40.0]
				settle = [65.0,-40.0,-40.0,115.0,25.0]
		"net":
			contact = [42.0,-12.0,-12.0,155.0,155.0]
			follow = [35.0,-18.0,-20.0,145.0,150.0]
			settle = [50.0,-40.0,-38.0,125.0,65.0]
		"drive":
			contact = [12.0,-8.0,-8.0,120.0,45.0]
			follow = [62.0,-145.0,-155.0,115.0,25.0]
			settle = [75.0,-110.0,-110.0,115.0,25.0]
		"lift", "serve":
			contact = [65.0,35.0,12.0,115.0,25.0]
			follow = [22.0,-45.0,-55.0,120.0,40.0]
			settle = [40.0,-62.0,-60.0,115.0,25.0]
		_:
			return ready
	if t<.30: return mix_pose(contact,follow,smoothstep(0,.30,t))
	if t<.58: return mix_pose(follow,settle,smoothstep(.30,.58,t))
	return mix_pose(settle,ready,smoothstep(.58,1,t))

static func direction(degrees: float, mirror: float) -> Vector2:
	var angle = deg_to_rad(degrees)
	return Vector2(cos(angle)*mirror,sin(angle))

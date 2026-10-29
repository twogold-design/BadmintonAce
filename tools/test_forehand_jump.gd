extends SceneTree
const ATHLETE=preload("res://scripts/athlete_3d.gd")
const CODEC=preload("res://scripts/state_codec.gd")
var checks=0
var failures=0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.sound_on=false
	var max_dip=0.0
	for avatar in ["male","female"]:
		for index in [0,1]:
			game.start_game("ai");game.phase="rally";game.last_hit=1-index
			var p: Dictionary=game.players[index]
			p.avatar=avatar;p.vel=Vector2.ZERO;p.pos=Vector2(0,5 if index==0 else -5)
			game.FOOTWORK.reset(p);p.stamina=100
			game.ball=Vector3(0,0,1)
			var start=ATHLETE.body_frame(p,index)
			check(start.pelvis.y<ATHLETE.measured(avatar,"pelvis").y-.06,"Ready stance lowers hips without sitting down")
			check(start.pelvis.y>ATHLETE.measured(avatar,"pelvis").y-.13,"Ready stance remains light and mobile")
			game._jump(index)
			game._jump(index)
			check(p.stamina==88 and p.jump_v==0,"Repeated jump input spends stamina once and begins grounded loading")
			var lowest=start.pelvis.y
			var takeoff=-1.0
			var peak=0.0
			var saw_drive=false
			for tick in range(150):
				game._update_player(index,1.0/120,false)
				var frame=ATHLETE.body_frame(p,index)
				if p.jump_load>0:
					lowest=minf(lowest,frame.pelvis.y)
					check(p.jump==0 and p.lift_l==0 and p.lift_r==0,"Both feet support the loading phase")
					if p.jump_drive>.4:saw_drive=true
				if p.jump>0 and takeoff<0:takeoff=float(tick+1)/120
				if p.jump>.20:
					check(frame.lean<-.06 and frame.lean>-.20,"Airborne chest stays slightly forward without falling back")
					check((frame.chest-frame.pelvis).z<-.015,"Airborne shoulders remain ahead of hips")
					var foot_mid=(frame.lf+frame.rf)*.5-frame.pelvis
					check(foot_mid.z>-.03 and foot_mid.z<.20,"Airborne feet tuck under or behind hips, not out in front")
				peak=maxf(peak,p.jump)
			check(start.pelvis.y-lowest>.08,"Visible knee and hip compression precedes takeoff")
			max_dip=maxf(max_dip,start.pelvis.y-lowest)
			check(takeoff>=.12 and takeoff<=.16 and saw_drive,"Short load leads to leg drive, not an immediate float upward")
			check(peak>.85 and peak<1.0,"Jump retains its established flight height")
			check(p.jump==0 and p.jump_load==0 and p.jump_crouch==0,"Landing clears all jump preparation")
			# Interrupting the rally must not launch a delayed jump during service.
			game._jump(index);game.phase="point";game._update_player(index,.02,false)
			check(p.jump_load==0 and p.jump_v==0,"Point ending cancels pending takeoff")
			game.phase="rally"
			var side=1.0 if index==0 else -1.0
			p.pos=Vector2(0,5*side);p.jump=0;p.jump_v=0;p.landing=0
			game.FOOTWORK.reset(p);p.backhand=false;p.shot=2;p.stroke="overhead"
			var contact=Vector3(.35*side,4.7*side,2.3)
			check(ATHLETE.can_reach(p,index,contact),"Forehand grip keeps high balls playable")
			game.FOOTWORK.hit(p,index,contact,false)
			var model=game.arena.athletes[index]
			for tick in range(31):
				p.swing=.48*(1-float(tick)/32)
				if tick>0:game.FOOTWORK.update(p,index,.48/32,true,false,contact,false)
				model.animate(p,index,contact,0)
				var palm=model.poses[model.bones.hand_r].basis*model.rests[model.bones.hand_r].basis.inverse()
				var relative=model.racket_basis_current.inverse()*palm
				var bevel=relative*ATHLETE.HAND_GRIP.inverse()
				check(bevel.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)>deg_to_rad(20),"Forehand retains its side angle instead of a square panhandle grip")
				check((-palm.y).dot(-model.racket_basis_current.z)>cos(deg_to_rad(20)),"Overhead uses the same handshake grip as the ready stance")
				var forearm=(model.joint_points.hand_r-model.joint_points.lowerarm_r).normalized()
				check(palm.x.dot(forearm)>cos(deg_to_rad(55)),"Power rotation does not fold the wrist: "+avatar+" frame "+str(tick)+" angle "+str(rad_to_deg(acos(clampf(palm.x.dot(forearm),-1,1)))))
				if tick==0:check(model.contact_error<model.OVERHEAD_CONTACT_TOLERANCE,"Forehand visual contact stays within its bounded allowance")
	# Snapshot layout supports both old peers and the extra jump poses.
	game.net_match_id="12345678-1234-1234-1234-123456789abc"
	var packet={"type":"state","match":game.net_match_id,"time":0.0,"ball":[0,0,1],"velocity":[0,0,0],"phase":"rally","score":[0,0],"players":[]}
	for p in game.players:
		p.jump_crouch=.8;p.jump_drive=.4
		packet.players.append({"pos":[p.pos.x,p.pos.y],"vel":[0,0],"shot":0,"charge":-1,"backhand":false,"stroke":"overhead","motion":game.FOOTWORK.snapshot(p)})
	var encoded=CODEC.encode(packet)
	var decoded=CODEC.decode(encoded)
	check(absf(decoded.players[1].motion.jump_crouch-.8)<.0001,"P2 receives the same crouch depth")
	check(not CODEC.decode(CODEC.encode(packet,1)).is_empty(),"Older snapshot format remains decodable")
	for count in range(encoded.size()):
		check(CODEC.decode(encoded.slice(0,count)).is_empty(),"Truncated jump snapshot is rejected")
	var report={"checks":checks,"failures":failures,"max_loading_dip_m":max_dip,"snapshot_bytes":encoded.size()}
	var output=FileAccess.open("res://artifacts/forehand-jump-test.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")+"\n");output.close()
	print("FOREHAND / JUMP LOAD: ",checks," checks; ",failures," failures; dip=",max_dip)
	quit(1 if failures else 0)

extends SceneTree
const ATHLETE = preload("res://scripts/athlete_3d.gd")
const FOOTWORK = preload("res://scripts/footwork.gd")

func _initialize(): call_deferred("run")

func run():
	var reference_path = OS.get_environment("ACE_BENCHMARK_REFERENCE")
	var athlete = ATHLETE if reference_path.is_empty() else load(reference_path)
	var timings = []
	var impact_timings = []
	var results = []
	var model = athlete.new()
	root.add_child(model)
	for avatar in ["male","female"]:
		for index in [0,1]:
			var side = 1.0 if index==0 else -1.0
			for height in [.65,1.5,2.2]:
				for x in [-.9,-.3,.35,.85]:
					var p = {"avatar":avatar,"pos":Vector2(0,3.3*side),"vel":Vector2.ZERO,"jump":0.0,"swing":0.0,"charge":-1,"shot":1,"buffer":0.0,"dash":0.0,"landing":0.0,"stroke":"net" if height<1.9 else "overhead","backhand":false}
					FOOTWORK.reset(p)
					var ball = Vector3(x*side,2.9*side,height)
					var started = Time.get_ticks_usec()
					var reachable = athlete.can_reach(p,index,ball)
					timings.append((Time.get_ticks_usec()-started)/1000.0)
					results.append(reachable)
					model.animate(p,index,ball,0.0)
					if reachable:
						FOOTWORK.hit(p,index,ball,false)
						started = Time.get_ticks_usec()
						model.animate(p,index,ball,0.0)
						impact_timings.append((Time.get_ticks_usec()-started)/1000.0)
	var sorted = timings.duplicate()
	sorted.sort()
	var total = 0.0
	for value in timings: total+=value
	var report = {"cases":results.size(),"accepted":results,"reach_ms_mean":total/timings.size(),"reach_ms_p95":sorted[int(sorted.size()*.95)],"reach_ms_max":sorted.back()}
	impact_timings.sort()
	total=0.0
	for value in impact_timings: total+=value
	report.impact_ms_mean=total/impact_timings.size()
	report.impact_ms_max=impact_timings.back()
	print(JSON.stringify(report))
	var output = OS.get_environment("ACE_BENCHMARK_REPORT")
	if not output.is_empty(): FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	quit()

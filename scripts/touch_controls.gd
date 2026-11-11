extends Node2D
## Finger ownership is independent for movement, stroke and auxiliary buttons.
## Coordinates are viewport pixels, not the scaled desktop interface canvas.
var game: Node2D
var enabled = false
var movement = Vector2.ZERO
var fingers: Dictionary = {}
var buttons: Dictionary = {}
var stick = Vector2.ZERO
var radius = 54.0
var unit = 1.0
var previous_size = Vector2.ZERO
var active = false
var portrait = false

func setup(owner_game: Node2D) -> void:
	game = owner_game
	enabled = DisplayServer.is_touchscreen_available()
	if OS.has_feature("web"):
		enabled = bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 0"))
	_layout()

func _layout() -> void:
	var size = get_viewport_rect().size
	var pixel_ratio = 1.0
	if OS.has_feature("web"):
		var css_width = float(JavaScriptBridge.eval("document.getElementById('canvas').clientWidth || innerWidth"))
		if css_width>0: pixel_ratio = size.x/css_width
	var css_size = size/pixel_ratio
	unit = clampf(css_size.y/390.0,.85,1.3)*pixel_ratio
	portrait = size.y>size.x
	var margin = maxf(22*unit,size.x*.055)
	radius = 54*unit
	stick = Vector2(margin+radius,size.y-24*unit-radius)
	buttons = {
		"net": Vector3(size.x-margin-164*unit,size.y-54*unit,30*unit),
		"smash": Vector3(size.x-margin-96*unit,size.y-86*unit,32*unit),
		"clear": Vector3(size.x-margin-28*unit,size.y-54*unit,30*unit),
		"jump": Vector3(size.x-margin-132*unit,size.y-158*unit,25*unit),
		"dash": Vector3(size.x-margin-62*unit,size.y-158*unit,25*unit),
		"pause": Vector3(size.x-margin-28*unit,38*unit,25*unit)
	}
	previous_size = size

func _process(_dt: float) -> void:
	if game==null: return
	if get_viewport_rect().size!=previous_size:
		reset()
		_layout()
		# Do not leave a live match running behind the rotate-device cover.
		if enabled and portrait and game.screen=="game" and not game.paused: game._pause_menu()
	var now_active = enabled and game.screen=="game" and not game.paused and game.phase!="end" and not game.net_preparing and not portrait
	if active and not now_active: reset()
	active = now_active
	visible = enabled and game.screen=="game" and not game.paused and game.phase!="end" and not portrait
	queue_redraw()

func reset() -> void:
	var had_shot = fingers.values().any(func(action): return action in ["net","smash","clear"])
	fingers.clear()
	movement = Vector2.ZERO
	if game!=null:
		if had_shot: game._cancel_touch_shot()
		if game.mode=="online" and game.net_role=="guest" and game.screen=="game": game._send_movement(Vector2.ZERO)

func _set_stick(at: Vector2) -> void:
	var offset = (at-stick)/radius
	movement = Vector2.ZERO if offset.length()<.16 else offset.limit_length(1)
	# The normal frame input path sends the latest direction, avoiding a burst
	# of network messages from high-frequency touch sampling. Release is immediate.

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag): return
	if not enabled:
		enabled = true
		_layout()
	if game==null: return
	if event is InputEventScreenTouch and event.pressed and not event.canceled and game.screen=="game" and not game.paused and game.phase!="end" and not portrait:
		var pause_area: Vector3 = buttons.pause
		if event.position.distance_to(Vector2(pause_area.x,pause_area.y))<=pause_area.z:
			get_viewport().set_input_as_handled()
			game._pause_menu()
			return
	var usable = game.screen=="game" and not game.paused and game.phase!="end" and not game.net_preparing and not portrait
	if not usable: return
	if event is InputEventScreenDrag:
		if fingers.has(event.index):
			if fingers[event.index]=="move": _set_stick(event.position)
			get_viewport().set_input_as_handled()
		return
	if event.pressed and not event.canceled:
		if fingers.has(event.index): return
		var action = ""
		if event.position.distance_to(stick)<=radius*1.35 and not fingers.values().has("move"):
			action = "move"
		else:
			for key in buttons:
				var area: Vector3 = buttons[key]
				if event.position.distance_to(Vector2(area.x,area.y))<=area.z:
					action = key
					break
		if action.is_empty(): return
		get_viewport().set_input_as_handled()
		if action=="pause": game._pause_menu(); return
		if fingers.values().has(action): return
		# Never mix two simultaneously held stroke types into a stuck charge.
		if action in ["net","smash","clear"] and fingers.values().any(func(a): return a in ["net","smash","clear"]): return
		fingers[event.index] = action
		if action=="move": _set_stick(event.position)
		else: game._touch_action(action,true)
	elif fingers.has(event.index):
		var action: String = fingers[event.index]
		fingers.erase(event.index)
		get_viewport().set_input_as_handled()
		if action=="move":
			movement = Vector2.ZERO
			if game.mode=="online" and game.net_role=="guest": game._send_movement(Vector2.ZERO)
		elif action in ["net","smash","clear"]:
			if event.canceled: game._cancel_touch_shot()
			else: game._touch_action(action,false)

func _label(at: Vector2, text: String, font_size: int, color: Color) -> void:
	var font: Font = game.FONT
	var pixels = maxi(10,roundi(font_size*unit))
	var width = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x
	draw_string(font,at-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels,color)

func _draw() -> void:
	if game==null or not visible: return
	var white = Color("eef6ed")
	var lime = Color("cdf578")
	var margin = maxf(22*unit,previous_size.x*.055)
	for i in range(2):
		var row = Vector2(margin,(10+25*i)*unit)
		draw_rect(Rect2(row,Vector2(146,23)*unit),Color(.05,.16,.17,.8))
		var name_text: String = game._player_display_name(i)
		var font_size = 12
		while font_size>8 and game.FONT.get_string_size(name_text,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(font_size*unit)).x>109*unit: font_size-=1
		draw_string(game.FONT,row+Vector2(7,16)*unit,name_text,HORIZONTAL_ALIGNMENT_LEFT,109*unit,roundi(font_size*unit),white)
		_label(row+Vector2(129,17)*unit,str(game.score[i]),16,lime)
		if game.server==i: draw_circle(row+Vector2(117,11)*unit,2*unit,lime)
	var meter = Vector2(previous_size.x-margin-191*unit,18*unit)
	_label(meter+Vector2(53,0)*unit,"体力",11,white)
	draw_rect(Rect2(meter+Vector2(0,7)*unit,Vector2(106,5)*unit),Color(.05,.12,.15,.8))
	draw_rect(Rect2(meter+Vector2(0,7)*unit,Vector2(106*game.players[game._local_player_index()].stamina/100,5)*unit),lime)
	var hint = "回合 %d · %d km/h" % [game.rally,game.last_speed]
	if game.phase=="serve": hint = "" if game.server==game._local_player_index() else "对手准备发球"
	if game.net_preparing: hint = "双方准备中"
	draw_string(game.FONT,Vector2(margin,77*unit),hint,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(11*unit),white)
	if game._show_serve_prompt():
		var prompt_at = Vector2(previous_size.x*.5,62*unit)
		var prompt_box = Rect2(prompt_at-Vector2(156,0)*unit,Vector2(312,50)*unit)
		draw_rect(prompt_box,Color(.04,.10,.13,.94))
		draw_rect(prompt_box,lime,false,unit)
		_label(prompt_at+Vector2(0,21)*unit,"按住「放网」或「高远」，松开发球",15,lime)
		_label(prompt_at+Vector2(0,40)*unit,"轮到你发球 · 放网发短球 / 高远发长球",11,white)
	draw_circle(stick,radius,Color(.035,.10,.13,.58))
	draw_arc(stick,radius,0,TAU,64,Color(white,.55),1.5*unit,true)
	draw_line(stick-Vector2(radius*.6,0),stick+Vector2(radius*.6,0),Color(white,.15),unit,true)
	draw_line(stick-Vector2(0,radius*.6),stick+Vector2(0,radius*.6),Color(white,.15),unit,true)
	draw_circle(stick+movement*radius*.65,21*unit,Color(lime,.8 if movement.length()>.1 else .4))
	_label(stick+Vector2(0,-radius-10*unit),"移动",12,white)
	var titles = {"net":["放网","吊球"],"smash":["杀球","平抽"],"clear":["高远","挑球"],"jump":["起跳"],"dash":["蹬步"],"pause":["暂停"]}
	for action in buttons:
		var area: Vector3 = buttons[action]
		var at = Vector2(area.x,area.y)
		var held = fingers.values().has(action)
		draw_circle(at,area.z,Color(.28,.38,.14,.85) if held else Color(.025,.10,.14,.72))
		draw_arc(at,area.z,0,TAU,48,lime if held else Color(white,.65),1.5*unit,true)
		var lines: Array = titles[action]
		for i in range(lines.size()): _label(at+Vector2(0,(5 if lines.size()==1 else -3+15*i)*unit),lines[i],12,white)
	_label(Vector2(previous_size.x*.5,previous_size.y-12*unit),"按住蓄力 · 松手击球",12,white)

func diagnostics() -> Dictionary:
	var result = {"enabled":enabled,"active":active,"portrait":portrait,"movement":[movement.x,movement.y],"stick":[stick.x,stick.y,radius],"buttons":{}}
	for key in buttons:
		var b: Vector3 = buttons[key]
		result.buttons[key] = [b.x,b.y,b.z]
	return result

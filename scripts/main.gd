extends Node2D
## Game rules, UI, procedural sound and shuttle simulation with a 3D arena.

const ATHLETE = preload("res://scripts/athlete.gd")
const ARENA_3D = preload("res://scripts/arena_3d.gd")
var arena: SubViewport
const FOOTWORK = preload("res://scripts/footwork.gd")
const REMOTE_VIEW = preload("res://scripts/remote_view.gd")
var remote_view = REMOTE_VIEW.new()
const FONT_SOURCE = preload("res://assets/NotoSansSC.ttf")
var FONT = FontVariation.new()
var FONT_BOLD = FontVariation.new()
const INK = Color("0b1721")
const PANEL = Color("112532")
const LINE = Color("29424c")
const WHITE = Color("edf3e9")
const MUTED = Color("829b9e")
const LIME = Color("cdf578")
const TEAL = Color("62dbc6")
const CORAL = Color("ff947e")
const G = 10.8
const DRAG = 0.20
const SHOTS = ["高远球", "放网 / 吊球", "杀球 / 平抽", "挑球"]
const KEYS = [[KEY_L, KEY_J, KEY_K], [KEY_COMMA, KEY_N, KEY_M]]

var screen = "menu"
var mode = "ai"
var difficulty = 1
const GOAL_SCORE = 11
var sound_on = true
var guide_on = true
var baseline_camera = true
var selected_avatar = "male"
var remote_avatar = "male"
var avatar_return = "menu"
var paused = false
var clock_time = 0.0
var menu_time = 0.0
const DEMO_FLIGHT_TIME = 1.4
var demo_leg = -1
var ui: Control
var players: Array[Dictionary] = []
var ball = Vector3.ZERO
var velocity = Vector3.ZERO
var ball_trail: Array[Vector3] = []
var phase = "serve"
var phase_time = 0.0
var server = 0
var last_hit = 0
var score = [0, 0]
var rally = 0
var longest_rally = 0
var total_hits = 0
var perfect_hits = 0
var winner = 0
var last_winner = 0
var last_reason = ""
var toast = ""
var toast_time = 0.0
var effects: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var shake = 0.0
var freeze = 0.0
var center_x = 730.0
var court_scale = 1.0
var court_offset = Vector2.ZERO
var sound_bank: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var voice_index = 0
var ai_timer = 0.0
var shots_count = [0, 0, 0, 0]
var match_time = 0.0
var last_speed = 0
var training_hits = 0
var save_best = 0
var test_mode = false
var ai_both = false
var stats: Dictionary = {"net":0, "out":0, "ground":0, "points":0}
var socket: WebSocketPeer
var net_role = ""
var room_code = ""
var net_status = "创建一个房间，或输入朋友分享的房间码。"
var net_action = ""
var server_address = ""
var address_input: LineEdit
var code_input: LineEdit
var net_connected = false
var net_tick = 0.0
var net_ping = 0.0
var net_rtt = 0
var remote_move = Vector2.ZERO
var net_targets = [Vector2.ZERO, Vector2.ZERO]
var net_ball = Vector3.ZERO
var diagnostic_tick = 0.0
var invite_url = ""
var connection_scope = "local"
var invite_input: LineEdit
var copy_invite_button: Button
var net_connect_elapsed = 0.0
var lan_address = ""
var lan_only = true
var nickname = ""
var room_password = ""
var nickname_input: LineEdit
var password_input: LineEdit
var net_match_id = ""
var result_recorded = false
var board_items: ItemList
var shot_rng = RandomNumberGenerator.new()

func _ready() -> void:
	shot_rng.randomize()
	FONT.base_font = FONT_SOURCE
	FONT.variation_opentype = {0x77676874:500.0}
	FONT_BOLD.base_font = FONT_SOURCE
	FONT_BOLD.variation_opentype = {0x77676874:750.0}
	RenderingServer.set_default_clear_color(INK)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	_make_audio()
	_load_settings()
	_reset_players()
	arena = ARENA_3D.new()
	add_child(arena)
	arena.setup(self)
	_build_menu()
	if "--smoke-test" in OS.get_cmdline_user_args():
		test_mode = true
		ai_both = true
		start_game("ai")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.badmintonReady = true;")
		var invited = str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('room') || ''"))
		if invited.length() == 6 and invited.is_valid_hex_number():
			_show_lobby()
			code_input.text = invited.to_upper()
			_connect_room("join")

func _load_settings() -> void:
	var c = ConfigFile.new()
	if c.load("user://settings.cfg") == OK:
		difficulty = int(c.get_value("game", "difficulty", 1))
		sound_on = bool(c.get_value("game", "sound", true))
		save_best = int(c.get_value("game", "best", 0))
	nickname = str(c.get_value("game","nickname",""))
	server_address = str(c.get_value("game","server_override",""))
	baseline_camera = bool(c.get_value("game","baseline_camera",true))
	selected_avatar = _avatar_id(c.get_value("game","avatar","male"))

func _save_settings() -> void:
	var c = ConfigFile.new()
	c.load("user://settings.cfg")
	c.set_value("game", "difficulty", difficulty)
	c.set_value("game", "sound", sound_on)
	c.set_value("game", "best", maxi(save_best, longest_rally))
	c.set_value("game","nickname",nickname)
	c.set_value("game","baseline_camera",baseline_camera)
	c.set_value("game","avatar",selected_avatar)
	c.save("user://settings.cfg")

func _reset_players() -> void:
	players.clear()
	for i in range(2):
		var avatar = selected_avatar if i==0 else ("female" if selected_avatar=="male" else "male")
		if mode=="ai": avatar = selected_avatar
		if mode=="online" and screen=="game":
			avatar = selected_avatar if i==(1 if net_role=="guest" else 0) else remote_avatar
		players.append({"pos":Vector2(0, 3.6 if i == 0 else -3.6), "vel":Vector2.ZERO,
			"avatar":avatar,
			"stamina":100.0, "jump":0.0, "jump_v":0.0, "dash":0.0, "dash_cd":0.0,
			"swing":0.0, "shot":0, "charge":-1, "charge_time":0.0, "buffer":0.0,
			"step":0.0, "aim":Vector2.ZERO, "shot_aim":Vector2.ZERO, "last_drop_x":0.0, "last_drop_depth":1.2, "drop_count":0,
			"last_return":Vector2(99,99), "last_lane":-1,
			"stroke":"overhead", "landing":0.0,
			"ai_wait":0.0, "hit_flash":0.0, "backhand":false})
		FOOTWORK.reset(players.back())

func _clear_ui() -> void:
	for child in ui.get_children():
		ui.remove_child(child)
		child.queue_free()

func _style(bg: Color, border: Color, radius: int = 14) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 20
	s.content_margin_right = 20
	return s

func _button(label: String, rect: Rect2, action: Callable, primary: bool = false) -> Button:
	var b = Button.new()
	b.text = label
	b.position = rect.position
	b.size = rect.size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", FONT)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", INK if primary else WHITE)
	b.add_theme_color_override("font_hover_color", INK if primary else LIME)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_stylebox_override("normal", _style(LIME if primary else PANEL, LIME if primary else LINE))
	b.add_theme_stylebox_override("hover", _style(Color("ddffa0") if primary else Color("1c3541"), LIME))
	b.add_theme_stylebox_override("pressed", _style(TEAL, TEAL))
	b.add_theme_stylebox_override("focus", _style(Color(0,0,0,0), TEAL))
	b.pressed.connect(func(): _sfx("click"); action.call())
	ui.add_child(b)
	return b

func _build_menu() -> void:
	_disconnect()
	screen = "menu"
	paused = false
	_clear_ui()
	_button("开始挑战    ↗", Rect2(82, 556, 330, 62), func(): start_game("ai"), true)
	_button("角色 · " + ("女" if selected_avatar=="female" else "男"),Rect2(430,556,170,62),_show_avatar_selection)
	_button("在线对战  1 v 1", Rect2(82, 634, 210, 54), _show_lobby)
	_button("自由练习", Rect2(306, 634, 150, 54), func(): start_game("practice"))
	_button("操作指南", Rect2(82, 711, 174, 46), _show_help)
	_button("难度 · " + ["入门", "进阶", "高手"][difficulty], Rect2(270, 711, 186, 46), _cycle_difficulty)
	_button("声音 · " + ("开" if sound_on else "关"), Rect2(1213, 38, 154, 42), _toggle_sound)
	_reset_players()
	phase = "rally"
	menu_time = 0.0
	demo_leg = -1
	ball_trail.clear()
	for i in range(2):
		players[i].pos = _demo_position(i,0)
		FOOTWORK.reset(players[i])
	_demo(0)

func _avatar_id(value: Variant) -> String:
	return "female" if str(value)=="female" else "male"

func _show_avatar_selection() -> void:
	avatar_return = screen
	if screen=="lobby":
		nickname = nickname_input.text
		room_password = password_input.text
	screen = "avatars"
	_clear_ui()
	for i in range(2):
		var avatar = "male" if i==0 else "female"
		var card = _button("",Rect2(260+i*500,249,420,485),func(): _select_avatar(avatar))
		card.tooltip_text = "选择女选手" if i==1 else "选择男选手"
		card.add_theme_stylebox_override("normal",_style(Color.TRANSPARENT,Color.TRANSPARENT,20))
		card.add_theme_stylebox_override("hover",_style(Color(1,1,1,.025),LIME,20))
		card.add_theme_stylebox_override("pressed",_style(Color(TEAL,.08),TEAL,20))
		card.add_theme_stylebox_override("focus",_style(Color.TRANSPARENT,TEAL,20))
	_button("返回",Rect2(560,778,320,48),_return_from_avatars)

func _select_avatar(avatar: String) -> void:
	selected_avatar = _avatar_id(avatar)
	_save_settings()
	_return_from_avatars()

func _return_from_avatars() -> void:
	if avatar_return=="lobby": _show_lobby()
	else: _build_menu()

func _draw_avatar_selection() -> void:
	_center(Vector2(720,173),"选择角色",36)
	_center(Vector2(720,216),"点击卡片选择 · 男女角色的速度、体力和击球能力相同",17,MUTED)
	for i in range(2):
		var x = 260+i*500
		var avatar = "male" if i==0 else "female"
		_box(Rect2(x,249,420,485),PANEL,LIME if selected_avatar==avatar else LINE,20)
		_center(Vector2(x+210,300),"男选手" if i==0 else "女选手",28)
		_center(Vector2(x+210,335),"运动短发 / 速干球衣" if i==0 else "清爽马尾 / 运动球衣与短裤",15,MUTED)
		if selected_avatar==avatar: _center(Vector2(x+210,688),"当前选择",16,LIME)
		for side in range(2):
			_center(Vector2(x+135+side*150,612),"正面" if side==0 else "背面",14,MUTED)
	if arena!=null: draw_texture_rect(arena.get_texture(),scene_rect(),false)

func _cycle_difficulty() -> void:
	difficulty = (difficulty + 1) % 3
	_save_settings()
	_build_menu()

func _toggle_sound() -> void:
	sound_on = not sound_on
	_save_settings()
	if screen == "menu": _build_menu()
	elif paused: _pause_menu()

func start_game(new_mode: String) -> void:
	remote_view.reset()
	freeze = 0.0
	shake = 0.0
	effects.clear()
	particles.clear()
	mode = new_mode
	screen = "game"
	paused = false
	_clear_ui()
	_reset_players()
	score = [0, 0]
	rally = 0
	longest_rally = 0
	total_hits = 0
	perfect_hits = 0
	shots_count = [0, 0, 0, 0]
	match_time = 0
	training_hits = 0
	server = 0
	stats = {"net":0, "out":0, "ground":0, "points":0}
	_build_match_ui()
	_begin_serve()

func _build_match_ui() -> void:
	_clear_ui()
	var pause_button = _button("Ⅱ 暂停", Rect2(1308,24,108,42), _pause_menu)
	pause_button.set_meta("corner_button",true)

func _begin_serve() -> void:
	phase = "serve"
	phase_time = 0
	rally = 0
	ball_trail.clear()
	var parity = 1.0 if score[server] % 2 == 0 else -1.0
	var sx = parity * (1 if server == 0 else -1) * 1.28
	players[server].pos = Vector2(sx, 3.4 if server == 0 else -3.4)
	players[1-server].pos = Vector2(-sx, -3.8 if server == 0 else 3.8)
	for p in players:
		p.stamina = minf(100, p.stamina + 26)
		p.charge = -1
		p.shot_aim = Vector2.ZERO
		p.buffer = 0.0
		p.vel = Vector2.ZERO
		p.jump = 0.0
		p.jump_v = 0.0
		FOOTWORK.reset(p)
	for i in range(2): FOOTWORK.set_service_stance(players[i],i,i!=server)
	ball = _serve_ball()
	velocity = Vector3.ZERO
	last_hit = server
	toast = "准备发球" if mode != "practice" else "练习模式 · 放松，找到击球节奏"
	toast_time = 2.0

func _serve_ball() -> Vector3:
	var side = 1.0 if server==0 else -1.0
	var high = float(players[server].get("service_long",0))
	return Vector3(players[server].pos.x+lerpf(-.18,.30,high)*side,players[server].pos.y-lerpf(.35,.45,high)*side,1.05)

func _pause_menu() -> void:
	if screen != "game": return
	if mode == "online" and not paused: _net_send({"type":"pause", "value":true})
	paused = true
	for p in players: p.charge = -1
	_clear_ui()
	_button("继续比赛", Rect2(550, 350, 340, 58), _resume, true)
	_button("操作指南", Rect2(550, 425, 340, 50), _show_help)
	_button("声音 · " + ("开" if sound_on else "关"), Rect2(550, 490, 340, 50), _toggle_sound)
	if mode != "online": _button("重新开始", Rect2(550, 555, 340, 50), func(): start_game(mode))
	_button("返回主场", Rect2(550, 620, 340, 50), _build_menu)

func _resume() -> void:
	if mode == "online": _net_send({"type":"pause", "value":false})
	paused = false
	_build_match_ui()

var help_return = "menu"
func _show_help() -> void:
	help_return = screen
	screen = "help"
	_clear_ui()
	_button("明白了 · 上场", Rect2(1045, 777, 280, 56), func():
		if help_return == "menu": _build_menu()
		else:
			screen = "game"
			_resume(), true)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo: return
	var code = event.physical_keycode
	if event.pressed and code == KEY_ESCAPE:
		if screen == "help":
			if help_return == "menu": _build_menu()
			else:
				screen = "game"
				_resume()
		elif screen == "game":
			if paused: _resume()
			else: _pause_menu()
		return
	if event.pressed and code == KEY_H: guide_on = not guide_on
	if event.pressed and code == KEY_C and screen == "game":
		baseline_camera = not baseline_camera
		_save_settings()
	if screen != "game" or paused or phase == "end": return
	if mode == "online" and net_role == "guest":
		for s in range(3):
			if code == KEYS[0][s]: _net_send({"type":"input", "action":"shot", "shot":s,"pressed":event.pressed})
		if event.pressed and code == KEY_SPACE: _net_send({"type":"input", "action":"jump"})
		if event.pressed and code == KEY_SHIFT: _net_send({"type":"input", "action":"dash"})
		return
	for i in range(2 if mode == "local" else 1):
		for s in range(3):
			if code == KEYS[i][s]:
				if event.pressed and players[i].charge < 0:
					players[i].charge = s
					players[i].charge_time = 0.0
					players[i].shot_aim = players[i].aim
				elif not event.pressed and players[i].charge == s:
					players[i].charge = -1
					players[i].shot = s
					players[i].buffer = 0.36
					_try_hit(i, s)
		if event.pressed:
			if (i == 0 and code == KEY_SPACE) or (i == 1 and code == KEY_ENTER): _jump(i)
			if code == KEY_SHIFT and ((i == 0 and event.location != KEY_LOCATION_RIGHT) or (i == 1 and event.location == KEY_LOCATION_RIGHT)): _dash(i)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and screen == "game" and not test_mode:
		_pause_menu()

func _jump(i: int) -> void:
	var p = players[i]
	if p.jump <= 0 and p.stamina >= 12 and phase == "rally":
		p.jump_v = 4.7
		p.stamina -= 12
		_sfx("swoosh")

func _dash(i: int) -> void:
	var p = players[i]
	if p.dash_cd <= 0 and p.stamina >= 24 and phase == "rally":
		p.dash = 0.19
		p.dash_cd = 0.65
		p.stamina -= 24
		if p.aim.length() < 0.1:
			p.aim = (Vector2(ball.x, ball.y) - p.pos).normalized()
		_sfx("swoosh")

func _process(delta: float) -> void:
	clock_time += delta
	_network_process(delta)
	if arena!=null: arena.sync(self,delta)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if screen == "help" or paused: return
	var dt = delta
	if test_mode: dt *= 3.0
	toast_time = maxf(0, toast_time - dt)
	shake = maxf(0, shake - dt * 16)
	for e in effects: e.life -= dt
	effects = effects.filter(func(e): return e.life > 0)
	for p in particles:
		p.life -= dt
		p.pos += p.vel * dt
		p.vel.y += 190 * dt
	particles = particles.filter(func(p): return p.life > 0)
	if mode == "online" and net_role == "guest" and screen == "game": return
	if freeze > 0:
		freeze -= dt
		return
	if screen == "menu":
		_demo(dt)
		return
	if screen != "game": return
	phase_time += dt
	if phase == "end": return
	match_time += dt
	for i in range(2):
		_update_player(i, dt, ai_both or (i == 1 and mode in ["ai", "practice"]))
	if phase == "serve":
		ball = _serve_ball()
		if players[server].buffer > 0:
			players[server].buffer = maxf(0,players[server].buffer-dt)
			_try_hit(server,players[server].shot)
		if (server == 1 and mode in ["ai", "practice"]) or ai_both:
			if phase_time>.2 and players[server].charge<0: players[server].charge = 0 if randf()>.45 else 1
			if phase_time>1.0:
				_try_hit(server,int(players[server].charge))
				players[server].charge=-1
	elif phase == "rally":
		_step_ball(dt)
		for i in range(2):
			if players[i].buffer > 0:
				players[i].buffer = maxf(0,players[i].buffer-dt)
				if not _try_hit(i, players[i].shot) and players[i].buffer <= 0:
					players[i].swing = .16
					players[i].erase("contact")
					if i == 0:
						toast = "未击中 · 看落点提前到位，再松键挥拍"
						toast_time = 1.2
	elif phase == "point" and phase_time > 1.75:
		if _match_won(last_winner) and mode != "practice":
			_end_match(last_winner)
		else:
			_begin_serve()
	if test_mode and match_time > 240:
		print("SMOKE TIMEOUT ", JSON.stringify(stats), " hits=",total_hits)
		get_tree().quit(2)

func _update_player(i: int, dt: float, is_ai: bool) -> void:
	var p = players[i]
	p.swing = maxf(0, p.swing - dt)
	p.hit_flash = maxf(0, p.hit_flash - dt)
	p.dash_cd = maxf(0, p.dash_cd - dt)
	p.dash = maxf(0, p.dash - dt)
	p.landing = maxf(0,p.landing-dt)
	p.stamina = minf(100, p.stamina + dt * (14 if p.vel.length() < 1 else 8))
	if p.jump > 0 or p.jump_v > 0:
		p.jump += p.jump_v * dt
		p.jump_v -= 12.0 * dt
		if p.jump < 0:
			p.jump = 0.0
			p.jump_v = 0.0
			p.landing = .18
	if p.charge >= 0: p.charge_time = minf(.85, p.charge_time + dt)
	var movement = Vector2.ZERO
	if is_ai:
		movement = _ai(i, dt)
	elif mode == "online" and i == 1:
		movement = remote_move
		if movement.length() > 0: p.aim = movement.normalized()
		elif p.dash <= 0: p.aim = Vector2.ZERO
	else:
		if i == 0:
			movement = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
		else:
			movement = Vector2(float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
		if movement.length() > 0: p.aim = movement.normalized()
		elif p.dash <= 0: p.aim = Vector2.ZERO
	if p.charge >= 0 and movement.length() > .1:
		p.shot_aim = movement.normalized()
	# Small reach assist only after a shot has been queued and movement is released.
	# Never override manual movement or teleport the athlete to the shuttle.
	if not is_ai and p.buffer>0 and movement.length()<.1 and last_hit!=i and phase=="rally":
		var intercept = Vector2(ball.x,ball.y)+Vector2(velocity.x,velocity.y)*minf(.12,_time_to_height(2.2))
		var delta_to_ball: Vector2 = intercept-p.pos
		if delta_to_ball.length()<1.75 and ball.y*(1 if i==0 else -1)>.2:
			movement = delta_to_ball.normalized()*.65
	if phase != "rally": movement = Vector2.ZERO
	var speed = 4.5 if not is_ai else [3.7, 4.25, 4.85][difficulty]
	if mode == "practice" and is_ai: speed = 5.0
	if p.stamina < 18: speed *= .78
	if p.charge >= 0: speed *= .84
	if p.jump > .1: speed *= .83
	var desired: Vector2 = movement.limit_length() * speed
	if p.dash > 0: desired = p.aim * 10.5
	p.vel = p.vel.move_toward(desired, dt * 32)
	p.pos += p.vel * dt
	p.pos.x = clampf(p.pos.x, -3.75, 3.75)
	p.pos.y = clampf(p.pos.y, .45, 7.4) if i == 0 else clampf(p.pos.y, -7.4, -.45)
	p.step += p.vel.length() * dt * 2.6
	FOOTWORK.update(p,i,dt,phase=="rally",last_hit!=i,ball,is_ai,(1 if i==server else 2) if phase=="serve" else 0)

func _ai(i: int, dt: float) -> Vector2:
	var p = players[i]
	var sign_y = 1.0 if i == 0 else -1.0
	if phase != "rally": return Vector2.ZERO
	var target = Vector2(0, sign_y * 3.6)
	if last_hit != i:
		p.ai_wait += dt
		var delay = [.18, .10, .045][difficulty]
		if p.ai_wait < delay: return Vector2.ZERO
		# Intercept the descending shuttle at racket height, not its floor landing.
		var t = _time_to_height(1.6)
		target = Vector2(ball.x, ball.y) + Vector2(velocity.x, velocity.y) * ((1.0 - exp(-DRAG * t)) / DRAG)
		target.x = clampf(target.x, -2.65, 2.65)
		target.y = clampf(target.y * sign_y, .7, 6.6) * sign_y
		var dist = p.pos.distance_to(Vector2(ball.x, ball.y))
		if ball.y * sign_y > 0.3 and ball.z < 2.8 and velocity.z < 1.5 and dist < 1.05:
			var s = 0
			if mode != "practice":
				var roll = randf()
				if ball.z > 1.8 and roll < .40: s = 2
				elif absf(p.pos.y) < 2.4: s = 1 if roll < .55 else 3
				elif roll < .55: s = 1
				elif roll > .85: s = 3
			p.charge_time = randf_range(.16, .46)
			# Let tactical placement vary the route instead of always aiming at a corner.
			p.aim = Vector2.ZERO
			p.shot_aim = Vector2.ZERO
			_try_hit(i, s)
		if target.distance_to(p.pos) > 2.4 and t < .55 and difficulty == 2:
			p.aim = (target - p.pos).normalized()
			_dash(i)
	else:
		p.ai_wait = 0.0
	var diff: Vector2 = target - p.pos
	return diff.normalized() * minf(1, diff.length() / .25)

func _time_to_height(height: float) -> float:
	return maxf(0, (velocity.z + sqrt(maxf(0, velocity.z * velocity.z + 2 * G * (ball.z - height)))) / G)

func _landing() -> Vector2:
	var t = _time_to_height(0)
	return Vector2(ball.x, ball.y) + Vector2(velocity.x, velocity.y) * (1.0 - exp(-DRAG * t)) / DRAG

func _can_hit(i: int) -> bool:
	if phase == "serve": return i == server and phase_time > .2
	if phase != "rally" or last_hit == i: return false
	var p = players[i]
	if ball.y * (1 if i == 0 else -1) < .12: return false
	var reach = 1.40 + (.28 if p.dash > 0 else 0.0)
	return p.pos.distance_to(Vector2(ball.x, ball.y)) <= reach and ball.z >= .12 and ball.z <= 2.85 + p.jump and ARENA_3D.ATHLETE_3D.can_reach(p,i,ball)

func _try_hit(i: int, shot: int) -> bool:
	if not _can_hit(i): return false
	var p = players[i]
	var serving = phase == "serve"
	if serving:
		p.service_long = 0.0 if shot==1 else 1.0
		ball = _serve_ball()
	# L is resolved at contact on the authoritative host, including buffered shots.
	if shot==0 and not serving and ball.z-players[i].jump<1.9: shot=3
	var direction = -1.0 if i == 0 else 1.0
	var distance: float = p.pos.distance_to(Vector2(ball.x, ball.y))
	var quality = clampf(1.0 - distance * .38, .45, 1.0)
	var sweet = distance < .78 and p.charge_time >= .10 and p.charge_time <= .52
	var charge: float = clampf(p.charge_time / .55, 0, 1)
	var chosen_aim: Vector2 = p.shot_aim if p.shot_aim.length() > .1 else p.aim
	var target_x = 0.0
	var target_y = 5.8
	var travel = 1.65
	var label = SHOTS[shot]
	var smash = false
	p.backhand = (ball.x-p.pos.x)*(1.0 if i == 0 else -1.0) < -.25
	match shot:
		0:
			target_y = 5.85
			travel = 1.6 + charge * .2
			label = "高远球"
		1:
			var drop = _drop_target(i)
			target_x = drop.x
			target_y = absf(drop.y)
			travel = lerpf(1.16,1.02,charge) if absf(ball.y) > 3 else lerpf(.90,.78,charge)
			label = "吊球" if absf(ball.y) > 2.5 else "放网"
			if absf(p.pos.x) > .5:
				label = ("直线" if target_x*p.pos.x >= 0 else "斜线") + label
		2:
			smash = ball.z-p.jump > 1.85
			if smash:
				target_y = 3.9 + charge * 1.1
				travel = .61 - charge * .11 - p.jump * .07
				label = "跳杀" if p.jump > .35 else "杀球"
			else:
				target_y = 5.2
				travel = .85
				label = "平抽挡"
				if absf(ball.y) < 2.4:
					label = "网前推球"
					target_y = 4.5
					travel = 1.02
		3:
			target_y = 6.15
			travel = 1.95
			label = "挑球"
	if serving:
		target_x = -signf(p.pos.x) * 1.35
		target_y = 2.7 if shot == 1 else 5.9
		travel = 1.25 if shot == 1 else 1.95
		label = "发小球" if shot == 1 else "发高远球"
		ball.z = 1.05
	else:
		if shot != 1:
			var placement = _return_target(i, shot, smash, target_y, chosen_aim)
			target_x = placement.x
			target_y = placement.y
		var error = (1.0 - quality) * .60 + maxf(0, p.charge_time - .62) * .7
		target_x += randf_range(-error, error)
		target_y += randf_range(-error, error)
		if p.backhand: label = "反手" + label
		if shot == 1:
			p.last_drop_x = target_x
			p.last_drop_depth = target_y
			p.drop_count += 1
	var target = Vector3(target_x, target_y * direction, .025)
	var horizontal = Vector2(target.x - ball.x, target.y - ball.y)
	if serving and shot==1:
		# Solve the flight duration for six centimetres of tape clearance, retaining
		# the diagonal service-box landing point and the normal shuttle physics.
		var fraction = -ball.y / (target.y-ball.y)
		var low = .4
		var high = 1.25
		for attempt in range(24):
			var candidate = (low+high)*.5
			var cross_t = -log(1.0-fraction*(1.0-exp(-DRAG*candidate)))/DRAG
			var vz = (target.z-ball.z+.5*G*candidate*candidate)/candidate
			var cross_z = ball.z+vz*cross_t-.5*G*cross_t*cross_t
			if cross_z<1.61: low=candidate
			else: high=candidate
		travel = high
	velocity = Vector3(horizontal.x * DRAG / (1.0 - exp(-DRAG * travel)), horizontal.y * DRAG / (1.0 - exp(-DRAG * travel)), (target.z - ball.z + .5 * G * travel * travel) / travel)
	# Low defensive shots are lifted just enough to clear the tape. Late smashes can hit it.
	if not smash and not (serving and shot==1):
		var fraction = -ball.y / (target.y - ball.y)
		if fraction > 0 and fraction < 1:
			var cross_t = -log(1.0 - fraction * (1.0 - exp(-DRAG * travel))) / DRAG
			var cross_z = ball.z + velocity.z * cross_t - .5 * G * cross_t * cross_t
			var safety = 1.70 if shot != 3 else 2.4
			if cross_z < safety:
				# Increasing flight time preserves the chosen landing point and creates a higher arc.
				for attempt in range(20):
					travel += .055
					velocity.x = horizontal.x * DRAG / (1.0 - exp(-DRAG * travel))
					velocity.y = horizontal.y * DRAG / (1.0 - exp(-DRAG * travel))
					velocity.z = (target.z - ball.z + .5 * G * travel * travel) / travel
					cross_t = -log(1.0 - fraction * (1.0 - exp(-DRAG * travel))) / DRAG
					if ball.z + velocity.z * cross_t - .5 * G * cross_t * cross_t >= safety: break
	last_speed = roundi(velocity.length() * 3.6)
	# Animate the actual contact height: an overhead drop shares clear preparation,
	# while a low defensive clear is lifted from below rather than hit above the head.
	p.stroke = "overhead" if smash or (shot in [0,1] and ball.z-p.jump>1.9) else ("net" if shot==1 else ("lift" if shot in [0,3] else "drive"))
	FOOTWORK.hit(p,i,ball,serving)
	if players[1-i].jump<=0: players[1-i].split = .18
	p.shot = shot
	p.buffer = 0.0
	p.hit_flash = .25
	p.stamina = maxf(0, p.stamina - (7 if smash else 2))
	p.charge_time = 0.0
	p.shot_aim = Vector2.ZERO
	last_hit = i
	phase = "rally"
	if serving: toast_time = 0
	rally += 1
	longest_rally = maxi(longest_rally, rally)
	total_hits += 1
	if i == 0:
		shots_count[shot] += 1
		if sweet: perfect_hits += 1
		if mode == "practice": training_hits += 1
	ball_trail.clear()
	var col = CORAL if smash else (LIME if sweet else TEAL)
	_effect(_project(ball), label + (" · 甜区" if sweet and not serving else ""), col, ball)
	_burst(_project(ball), col, 13 if smash else 7)
	_sfx("smash" if smash else "hit")
	if smash:
		shake = 2.3
		freeze = .025
	if mode == "practice" and i == 0:
		toast = "回到中场准备下一拍" if quality > .7 else "有点勉强！再靠近落点一些"
		toast_time = 1.8
	return true

func _return_target(i: int, shot: int, smash: bool, base_depth: float, aim: Vector2) -> Vector2:
	# Called once per accepted hit by the host. Guests receive the resulting velocity;
	# drawing and network snapshots never roll another target.
	var p = players[i]
	var direction = -1.0 if i == 0 else 1.0
	var opponent_x: float = players[1-i].pos.x
	var x: float
	var manual_x = absf(aim.x) > .2
	var manual_y = absf(aim.y) > .3
	if manual_x:
		x = aim.x * 2.05 + shot_rng.randf_range(-.10,.10)
	else:
		var lanes = [-1.95, clampf(opponent_x,-1.2,1.2), 1.95]
		var weights: Array[float] = []
		var total = 0.0
		for lane in range(3):
			# Prefer open space, retain occasional body shots, discourage repetition.
			var weight = .8 + absf(float(lanes[lane])-opponent_x)*1.05
			if lane == 1: weight = 1.25 if smash else .65
			if lane == p.last_lane: weight *= .45
			weights.append(weight)
			total += weight
		var roll = shot_rng.randf()*total
		var selected = 2
		for lane in range(3):
			roll -= weights[lane]
			if roll <= 0:
				selected = lane
				break
		x = float(lanes[selected]) + shot_rng.randf_range(-.28,.28)
		p.last_lane = selected
	var low = 5.25
	var high = 6.3
	var spread = .35
	if shot == 2:
		low = 3.35 if smash else 3.65
		high = 5.65 if smash else 5.9
		spread = .72 if smash else .60
	elif shot == 3:
		low = 5.55
		spread = .30
	var depth = base_depth + shot_rng.randf_range(-spread,spread)
	if manual_y:
		depth = base_depth + aim.y*direction*.65 + shot_rng.randf_range(-.10,.10)
	depth = clampf(depth,low,high)
	# Separate successive automatic placements without reversing a manual aim.
	var target = Vector2(x,depth)
	if not manual_x and target.distance_to(p.last_return) < .55:
		var left = Vector2(clampf(x-.7,-2.3,2.3),depth)
		var right = Vector2(clampf(x+.7,-2.3,2.3),depth)
		target = left if left.distance_to(p.last_return)>right.distance_to(p.last_return) else right
	p.last_return = target
	return target

func _drop_target(i: int) -> Vector2:
	var p = players[i]
	var direction = -1.0 if i == 0 else 1.0
	var aim: Vector2 = p.shot_aim if p.shot_aim.length() > .1 else p.aim
	var x: float
	if absf(aim.x) > .2:
		x = signf(aim.x) * 2.12
	else:
		# Attack the open side; if the opponent is centered, vary straight/cross-court.
		var opponent_x: float = players[1-i].pos.x
		var side: float = -signf(opponent_x) if absf(opponent_x) > .45 else (1.0 if p.drop_count % 2 == 0 else -1.0)
		x = side * (1.48 + .29 * (p.drop_count % 3))
		if absf(x-p.last_drop_x) < .2: x = clampf(x - side*.48,-2.2,2.2)
	var charge: float = clampf(p.charge_time/.65,0,1)
	var depth = lerpf(.82,1.85,charge) + .12*(p.drop_count%3)
	if absf(aim.y) > .2:
		depth = 2.20 if aim.y*direction > 0 else .78
	return Vector2(x,clampf(depth,.65,2.35)*direction)

func _step_ball(dt: float) -> void:
	var previous = ball
	var decay = exp(-DRAG * dt)
	ball.x += velocity.x * (1.0 - decay) / DRAG
	ball.y += velocity.y * (1.0 - decay) / DRAG
	ball.z += velocity.z * dt - .5 * G * dt * dt
	velocity.x *= decay
	velocity.y *= decay
	velocity.z -= G * dt
	ball_trail.push_front(ball)
	if ball_trail.size() > 32: ball_trail.pop_back()
	if previous.y * ball.y < 0:
		var f = absf(previous.y) / (absf(previous.y) + absf(ball.y))
		var cross_z = lerpf(previous.z, ball.z, f)
		if cross_z < 1.55:
			stats.net += 1
			_point(1-last_hit, "下网 · 击球点再高一些")
			return
	if ball.z <= 0:
		ball.z = 0
		var outside = absf(ball.x) > 2.59 or absf(ball.y) > 6.70
		var landing_side = 0 if ball.y > 0 else 1
		var who = 1-last_hit if outside or landing_side == last_hit else last_hit
		stats["out" if outside else "ground"] += 1
		_point(who, "出界" if outside else "落地得分")

func _point(who: int, reason: String) -> void:
	if phase != "rally": return
	phase = "point"
	phase_time = 0.0
	last_winner = who
	last_reason = reason
	server = who
	if mode != "practice": score[who] += 1
	else: server = 0
	stats.points += 1
	_sfx("point")
	_effect(_project(Vector3(ball.x, ball.y, 0)) + Vector2(0,-20), "OUT" if reason == "出界" else "+1", LIME if who == 0 else CORAL, Vector3(ball.x,ball.y,0), -20)
	for p in players:
		p.charge = -1
		p.buffer = 0.0

func _match_won(i: int) -> bool:
	return (score[i] >= GOAL_SCORE and score[i] - score[1-i] >= 2) or score[i] >= 15

func _end_match(who: int) -> void:
	phase = "end"
	winner = who
	_save_settings()
	_clear_ui()
	_button("再来一场", Rect2(488, 641, 220, 58), _rematch, true)
	_button("返回主场", Rect2(732, 641, 220, 58), _build_menu)
	if mode == "online":
		if net_role == "host": _send_snapshot()
		_net_send({"type":"finish","match":net_match_id,"score":score})
	if test_mode:
		print("SMOKE OK ", JSON.stringify({"score":score,"hits":total_hits,"longest":longest_rally,"stats":stats,"seconds":match_time}))
		get_tree().quit(0)

func _demo_position(index: int, time: float) -> Vector2:
	return Vector2(sin(time*.55+index*2)*1.3,3.7 if index==0 else -3.8)

func _demo_contact(index: int, time: float) -> Vector3:
	var at = _demo_position(index,time)
	var side = 1.0 if index==0 else -1.0
	return Vector3(at.x+.35*side,at.y-.28*side,2.25)

func _demo(dt: float) -> void:
	# One physics clock drives feet, preparation, contact and the shuttle.
	menu_time += dt
	var leg_index = int(floor(menu_time/DEMO_FLIGHT_TIME))
	var leg_time = menu_time-leg_index*DEMO_FLIGHT_TIME
	var sender = leg_index%2
	var receiver = 1-sender
	var start = _demo_contact(sender,leg_index*DEMO_FLIGHT_TIME)
	var finish = _demo_contact(receiver,(leg_index+1)*DEMO_FLIGHT_TIME)
	ball = start.lerp(finish,leg_time/DEMO_FLIGHT_TIME)
	ball.z += .5*G*leg_time*(DEMO_FLIGHT_TIME-leg_time)
	velocity = (finish-start)/DEMO_FLIGHT_TIME+Vector3(0,0,.5*G*(DEMO_FLIGHT_TIME-2*leg_time))
	last_hit = sender
	for i in range(2):
		var p = players[i]
		p.swing = maxf(0, p.swing - dt)
		p.pos = _demo_position(i,menu_time)
		p.vel = Vector2(cos(menu_time*.55+i*2)*.715,0)
		p.step += p.vel.length() * dt * 2
		p.charge = 0 if i==receiver and DEMO_FLIGHT_TIME-leg_time<.45 else -1
		if leg_index!=demo_leg and i==sender:
			p.stroke = "overhead"
			p.backhand = false
			FOOTWORK.hit(p,i,start,false)
			p.swing = maxf(0,FOOTWORK.SWING_TIME-leg_time)
		FOOTWORK.update(p,i,dt,true,i==receiver,ball,false)
	demo_leg = leg_index
	ball_trail.push_front(ball)
	if ball_trail.size() > 14: ball_trail.pop_back()

func _effect(pos: Vector2, label: String, color: Color, world: Vector3 = Vector3.ZERO, offset_y: float = 0) -> void:
	effects.append({"pos":pos, "text":label, "color":color, "life":1.0})
	if mode == "online" and net_role == "host":
		_net_send({"type":"effect", "pos":[pos.x,pos.y], "world":[world.x,world.y,world.z], "offset_y":offset_y, "label":label,"color":color.to_html()})

func _burst(pos: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		particles.append({"pos":pos, "vel":Vector2.from_angle(randf()*TAU)*randf_range(45,160), "life":randf_range(.2,.5), "color":color})

func _make_audio() -> void:
	for key in ["hit", "smash", "point", "click", "swoosh"]:
		var duration = .16 if key != "point" else .45
		var rate = 22050
		var data = PackedByteArray()
		data.resize(int(duration * rate) * 2)
		for n in range(int(duration * rate)):
			var t = float(n) / rate
			var v = 0.0
			match key:
				"hit": v = (sin(t * TAU * (780 - t*2200))*.55 + randf_range(-1,1)*.35) * exp(-t*38)
				"smash": v = (sin(t * TAU * 170)*.6 + randf_range(-1,1)*.65) * exp(-t*27)
				"click": v = sin(t*TAU*950) * exp(-t*60)*.3
				"swoosh": v = randf_range(-1,1)*sin(t/duration*PI)*.16
				"point": v = sin(t*TAU*([523,659,784][mini(2, int(t*7))])) * sin(t/duration*PI)*.3
			data.encode_s16(n*2, int(clampf(v, -1, 1) * 21000))
		var stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = rate
		stream.data = data
		sound_bank[key] = stream
	for i in range(6):
		var v = AudioStreamPlayer.new()
		v.volume_db = -9
		add_child(v)
		voices.append(v)

func _sfx(key: String) -> void:
	if not sound_on or test_mode: return
	var v = voices[voice_index % voices.size()]
	v.stream = sound_bank[key]
	v.play()
	voice_index += 1

# All artwork is drawn in a fixed 1440 x 900 design space.
func interface_scale() -> float:
	var viewport_size = get_viewport_rect().size
	return minf(viewport_size.x/1440.0,viewport_size.y/900.0)

func interface_offset() -> Vector2:
	return (get_viewport_rect().size-Vector2(1440,900)*interface_scale())*.5

func scene_rect() -> Rect2:
	return Rect2(-interface_offset()/interface_scale(),get_viewport_rect().size/interface_scale())

func screen_to_interface(point: Vector2) -> Vector2:
	return (point-interface_offset())/interface_scale()

func _draw() -> void:
	var canvas_scale = Vector2.ONE*interface_scale()
	ui.scale = canvas_scale
	ui.position = interface_offset()
	for child in ui.get_children():
		if child.has_meta("corner_button"): child.position=Vector2(scene_rect().end.x-132,scene_rect().position.y+24)
	draw_set_transform(interface_offset(), 0, canvas_scale)
	_background()
	if screen == "menu":
		center_x = 1010
		court_scale = .76
		court_offset = Vector2(0, 138)
		_draw_court()
		_draw_world()
		_draw_menu()
	elif screen == "help":
		_draw_help()
	elif screen == "lobby":
		_draw_lobby()
	elif screen == "avatars":
		_draw_avatar_selection()
	elif screen in ["rooms","ranking"]:
		_center(Vector2(720,176),"局域网房间" if screen == "rooms" else "局域网战绩榜",36)
		_center(Vector2(720,216),"选择房间加入；带锁房间需要密码" if screen == "rooms" else "按胜场排名 · 双方确认结算 · 本服务器休闲战绩",16,MUTED)
		_center(Vector2(720,746),net_status,15,LIME)
	elif screen in ["room_password","connection_settings"]:
		_center(Vector2(720,210),"输入房间密码" if screen == "room_password" else "连接设置",36)
		_center(Vector2(720,270),"房间 " + code_input.text if screen == "room_password" else "仅主机地址变化时需要修改，其他玩家无需填写。",18,MUTED)
		_center(Vector2(720,610),net_status,16,LIME)
	else:
		center_x = 730
		court_scale = 1.0
		court_offset = Vector2(sin(clock_time*88)*shake, cos(clock_time*97)*shake*.5)
		_draw_court()
		_draw_world()
		_draw_hud()
		if phase == "point": _draw_point()
		if paused: _draw_pause()
		if phase == "end": _draw_result()
	draw_set_transform(Vector2.ZERO)

func _text(pos: Vector2, text: String, size: int = 20, color: Color = WHITE) -> void:
	draw_string(FONT_BOLD if size >= 28 else FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _center(pos: Vector2, text: String, size: int = 20, color: Color = WHITE) -> void:
	var w = (FONT_BOLD if size >= 28 else FONT).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(pos - Vector2(w/2, 0), text, size, color)

func _box(rect: Rect2, bg: Color = PANEL, border: Color = LINE, radius: int = 16) -> void:
	draw_style_box(_style(bg, border, radius), rect)

func _background() -> void:
	draw_rect(scene_rect(), Color("101014") if screen=="game" else INK)
	if screen=="game": return
	for i in range(22):
		var y = 100 + i * 40
		draw_line(Vector2(0,y), Vector2(1440,y), Color(0.13,.24,.28,.10), 1)
	for i in range(36):
		draw_circle(Vector2(i*43+10, 110), 1.4, Color(.5,.7,.65,.18))
	draw_line(Vector2(44,101), Vector2(1396,101), LINE, 1)
	_text(Vector2(80,66), "ACE / 羽球俱乐部", 22, WHITE)
	draw_circle(Vector2(58,58), 6, LIME)
	_text(Vector2(80,855), "COURT 01   /   EVERY SHOT COUNTS", 13, MUTED)
	_text(Vector2(1108,855), "谁是羽毛球高手  ·  2026", 14, MUTED)

func _local_player_index() -> int:
	return 1 if mode=="online" and net_role=="guest" else 0

func _view_sign() -> float:
	return -1.0 if screen=="game" and _local_player_index()==1 else 1.0

func _project(v: Vector3) -> Vector2:
	if arena!=null: return arena.project(v,self)
	v = Vector3(v.x*_view_sign(),v.y*_view_sign(),v.z)
	if baseline_camera and screen != "menu":
		# Intermediate baseline angle (~29 degrees), with a single height scale.
		# Avoid the previous height breakpoint that kinked an otherwise smooth arc.
		var height = v.z*.80
		var depth = maxf(8.0,(20.0-v.y)*.876+(11.0-height)*.482)
		var projected_y = 510.0+(v.y*.482-height*.876)*1400.0/depth
		# Only exceptionally high shots enter this smooth safety margin.
		if projected_y < 150: projected_y = 150-34*tanh((150-projected_y)/34)
		return Vector2(center_x+v.x*2600.0/depth,projected_y)+court_offset
	var depth = (v.y + 6.7) / 13.4
	var widen = lerpf(82, 112, depth) * (1.0 if screen=="menu" else 1.35)
	return Vector2(center_x + v.x * widen * court_scale, (260 + depth * 482 - v.z * 44 * lerpf(.8,1.08,depth)) * court_scale) + court_offset

func _floor(v: Vector2) -> Vector2:
	return _project(Vector3(v.x,v.y,0))

func _court_line(a: Vector2, b: Vector2, color: Color, width: float = 2.0) -> void:
	draw_line(_floor(a), _floor(b), color, width * court_scale, true)

func _draw_court() -> void:
	if arena!=null:
		draw_texture_rect(arena.get_texture(),scene_rect(),false)
		return
	# Low-lit arena terraces and an inset wooden apron.
	for i in range(3):
		var y = 194 + i*17
		draw_line(Vector2(center_x-370*court_scale, y*court_scale+court_offset.y), Vector2(center_x+370*court_scale, y*court_scale+court_offset.y), Color(.19,.29,.30,.3), 8*court_scale)
	var apron = PackedVector2Array([_floor(Vector2(-3.8,-7.5)),_floor(Vector2(3.8,-7.5)),_floor(Vector2(3.8,7.6)),_floor(Vector2(-3.8,7.6))])
	draw_colored_polygon(apron, Color("1c3437"))
	for i in range(20):
		_court_line(Vector2(-3.8,-7.4+i*.8),Vector2(3.8,-7.4+i*.8), Color(.4,.55,.44,.08),1)
	var court = PackedVector2Array([_floor(Vector2(-3.05,-6.7)),_floor(Vector2(3.05,-6.7)),_floor(Vector2(3.05,6.7)),_floor(Vector2(-3.05,6.7))])
	draw_colored_polygon(court, Color("21685a"))
	for i in range(14):
		var y1 = -6.7 + i * 13.4/14
		var y2 = y1 + 13.4/14
		var strip = PackedVector2Array([_floor(Vector2(-3.05,y1)),_floor(Vector2(3.05,y1)),_floor(Vector2(3.05,y2)),_floor(Vector2(-3.05,y2))])
		if i % 2 == 0: draw_colored_polygon(strip, Color(1,1,1,.025))
	var line_col = Color("c6dfbc")
	for x in [-3.05, -2.59, 2.59, 3.05]: _court_line(Vector2(x,-6.7), Vector2(x,6.7), line_col, 2.2)
	for y in [-6.7,-5.94,-1.98,1.98,5.94,6.7]: _court_line(Vector2(-3.05,y), Vector2(3.05,y), line_col, 2.2)
	_court_line(Vector2(0,-6.7),Vector2(0,-1.98),line_col)
	_court_line(Vector2(0,1.98),Vector2(0,6.7),line_col)
	_court_line(Vector2(-3.05,0),Vector2(3.05,0),Color(0,0,0,.25), 7)
	var mid = _floor(Vector2(0,4.6*_view_sign()))
	_center(mid, "A C E", int(34*court_scale), Color(1,1,1,.09))
	if screen == "game" and phase == "serve":
		var x1 = 0.0 if players[server].pos.x > 0 else -2.59
		var x2 = 2.59 if players[server].pos.x > 0 else 0.0
		var sy = 1.0 if server == 0 else -1.0
		draw_colored_polygon(PackedVector2Array([_floor(Vector2(x1,1.98*sy)),_floor(Vector2(x2,1.98*sy)),_floor(Vector2(x2,6.7*sy)),_floor(Vector2(x1,6.7*sy))]),Color(.8,.95,.45,.10))
	var badge = _floor(Vector2(0,-7.7*_view_sign()))
	_center(badge, "B A D M I N T O N   /   A C E   C L U B", int(13*court_scale), MUTED)

func _draw_net() -> void:
	if arena!=null: return
	var left = _project(Vector3(-3.2,0,1.55))
	var right = _project(Vector3(3.2,0,1.55))
	var lb = _project(Vector3(-3.2,0,.35))
	var rb = _project(Vector3(3.2,0,.35))
	draw_colored_polygon(PackedVector2Array([left,right,rb,lb]), Color(.025,.10,.13,.38))
	for i in range(37):
		var t = i/36.0
		draw_line(left.lerp(right,t),lb.lerp(rb,t),Color(.7,.84,.8,.24),1,true)
	for i in range(7):
		var t = i/6.0
		draw_line(left.lerp(lb,t),right.lerp(rb,t),Color(.7,.84,.8,.24),1,true)
	draw_line(left,right,WHITE,3*court_scale,true)
	for x in [-3.2,3.2]:
		var a = _project(Vector3(x,0,1.65))
		var b = _project(Vector3(x,0,0))
		draw_line(a,b,Color("7c9c93"),5*court_scale,true)
		draw_circle(a,4*court_scale,LIME)
		draw_line(b-Vector2(10,0),b+Vector2(10,0),Color("0c292d"),5,true)

func _draw_world() -> void:
	if screen == "game" and phase == "rally" and guide_on:
		_draw_flight_guide()
	if screen == "game" and phase == "rally":
		var local_player = 1 if mode == "online" and net_role == "guest" else 0
		if players[local_player].charge == 1:
			var aim_at = _floor(_drop_target(local_player))
			draw_arc(aim_at,18,0,TAU,36,LIME,2.4,true)
			draw_circle(aim_at,4,LIME)
			_center(aim_at+Vector2(0,-25),"吊球目标",14,LIME)
	if screen == "game" and phase == "rally" and guide_on:
		var land = _landing()
		var p = _floor(land)
		var color = LIME if last_hit != _local_player_index() else CORAL
		if absf(land.y) < 8.0 and absf(land.x) < 4:
			draw_arc(p, 14+sin(clock_time*9)*2, 0,TAU,32,Color(color,.65),1.6,true)
			draw_line(p-Vector2(20,0),p+Vector2(20,0),Color(color,.45),1)
			draw_line(p-Vector2(0,7),p+Vector2(0,7),Color(color,.45),1)
	var near_player = _local_player_index() if screen=="game" else 0
	_draw_player(1-near_player)
	_draw_net()
	_draw_player(near_player)
	_draw_shuttle()
	if screen == "game":
		for e in effects:
			var a: float = minf(1,e.life*3)
			if e.text in ["OUT","+1"]:
				_center(e.pos + Vector2(0,-40-(1-e.life)*35),e.text,20,Color(e.color,a))
			elif e == effects.back():
				_center(Vector2(1290,392),e.text,16,Color(e.color,a))
		for p in particles: draw_circle(p.pos,2.5,Color(p.color,p.life*2))

func _limb(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_line(a,b,Color("081b23"),width+3*court_scale,true)
	draw_line(a,b,color,width,true)
	draw_circle(b,width/2,color)

func _draw_player(i: int) -> void:
	var p = players[i]
	var ground = _floor(p.pos)
	var s: float = lerpf(.83,1.13,(p.pos.y+6.7)/13.4)*court_scale
	if baseline_camera and screen != "menu": s = clampf((ground.y-_project(Vector3(p.pos.x,p.pos.y,1.8)).y)/92.0*1.35,.95,1.8)
	if not baseline_camera and screen != "menu": s *= 1.2
	var color = LIME if i == 0 else CORAL
	if arena==null: ATHLETE.paint(self,p,i,ground,s,clock_time)
	if screen == "game":
		_center(Vector2(ground.x,minf(826,ground.y+25*s)),"P1" if i == 0 else ("P2" if mode in ["local","online"] else "AI"),12,color)
		if _can_hit(i) and phase == "rally": draw_arc(ground,27*s,0,TAU,36,Color(color,.7),2,true)
		if _can_hit(i) and phase=="rally" and last_hit!=i:
			if i == (1 if mode == "online" and net_role == "guest" else 0):
				_center(Vector2(ground.x,minf(828,ground.y+43*s)),"松键击球",13,LIME)
		if p.charge >= 0:
			var cp = ground+Vector2(-26,35)
			draw_rect(Rect2(cp,Vector2(52,5)),Color("142730"))
			draw_rect(Rect2(cp,Vector2(52*minf(1,p.charge_time/.65),5)),CORAL if p.charge_time > .62 else LIME)

func _draw_flight_guide() -> void:
	var duration = minf(3.0,_time_to_height(0))
	var color = LIME if last_hit != _local_player_index() else TEAL
	var path = PackedVector2Array([_project(ball)])
	for k in range(1,97):
		var t = duration*k/96.0
		var drag_factor = (1.0-exp(-DRAG*t))/DRAG
		var point = Vector3(ball.x+velocity.x*drag_factor,ball.y+velocity.y*drag_factor,maxf(0,ball.z+velocity.z*t-.5*G*t*t))
		path.append(_project(point))
	draw_polyline(path,Color(color,.35),2.0,true)
	var land = _landing()
	if absf(land.x)<4 and absf(land.y)<8:
		var at = _floor(land)
		ATHLETE.oval(self,at,Vector2(24,9),Color(color,.12))

func _draw_shuttle() -> void:
	var pos = _project(ball)
	var ground = _floor(Vector2(ball.x,ball.y))
	ATHLETE.oval(self,ground,Vector2(5,2)*court_scale,Color(0,0,0,.35))
	if guide_on and screen=="game":
		for k in range(0,12,2):
			draw_line(pos.lerp(ground,k/12.0),pos.lerp(ground,(k+1)/12.0),Color(WHITE,.18),1,true)
		draw_arc(ground,7,0,TAU,24,Color(LIME,.65),1.5,true)
	if ball_trail.size()>1:
		var trail_points = PackedVector2Array()
		var trail_colors = PackedColorArray()
		for k in range(ball_trail.size()):
			trail_points.append(_project(ball_trail[k]))
			trail_colors.append(Color(LIME,pow(1-k/float(ball_trail.size()),1.3)*.65))
		draw_polyline_colors(trail_points,trail_colors,1.5*court_scale,true)
	if arena!=null: return
	var angle = (_project(ball+velocity*.02)-pos).angle()
	if screen == "menu": angle = PI*.45
	var fan = PackedVector2Array([pos+Vector2(-11,-6).rotated(angle)*court_scale,pos+Vector2(2,0).rotated(angle)*court_scale,pos+Vector2(-11,6).rotated(angle)*court_scale])
	draw_circle(pos,9*court_scale,Color(LIME,.10))
	draw_colored_polygon(fan,WHITE)
	for k in [-1,0,1]: draw_line(pos,pos+Vector2(-11,k*5).rotated(angle)*court_scale,Color("afc8b8"),1,true)
	draw_circle(pos+Vector2(2,0).rotated(angle)*court_scale,3*court_scale,LIME)

func _draw_menu() -> void:
	_text(Vector2(76,210), "BADMINTON ACE", 17, LIME)
	_text(Vector2(76,280), "谁是", 54)
	_text(Vector2(76,350), "羽毛球高手", 54)

	_text(Vector2(84,482), "轻吊、重杀，每一拍都有答案。", 23, WHITE)
	_text(Vector2(84,516), "把对手调离中场，把胜利留在场上。", 18, MUTED)





	_text(Vector2(84,805), "键盘操作  ·  AI / 在线对战  ·  11 分一局",15,MUTED)
	if save_best > 0: _text(Vector2(1144,128),"最佳回合  " + str(save_best) + " 拍",13,LIME)

func _draw_hud() -> void:
	var area=scene_rect()
	var left=area.position+Vector2(24,24)
	for i in range(2):
		var row=left+Vector2(0,i*31)
		_box(Rect2(row,Vector2(240,28)),Color("234841"),Color("395a53"),3)
		_text(row+Vector2(9,20),"PLAYER 01" if i==0 else ("PLAYER 02" if mode in ["local","online"] else "ACE BOT"),16)
		_box(Rect2(row+Vector2(244,0),Vector2(34,28)),WHITE,WHITE,3)
		_text(row+Vector2(251,21),str(score[i]),19,Color("1c272a"))
		if server==i:draw_circle(row+Vector2(225,14),3,LIME)
	_text(left+Vector2(0,84),"回合 "+str(rally)+"   最长 "+str(longest_rally)+"   "+str(last_speed)+" km/h",13,MUTED)
	var stamina_at=Vector2(area.end.x-355,area.position.y+24)
	_box(Rect2(stamina_at,Vector2(205,52)),Color(.13,.14,.16,.88),Color(.2,.21,.23),3)
	var local_player=_local_player_index()
	_text(stamina_at+Vector2(10,19),"P"+str(local_player+1)+"  体力",13)
	_bar(stamina_at+Vector2(10,31),185,players[local_player].stamina,LIME)
	_center(Vector2(area.get_center().x,area.end.y-18),"WASD 移动   J 放网 / 吊球   K 杀球 / 平抽   L 高远 / 挑球",13,WHITE)
	_text(Vector2(area.end.x-490,area.end.y-40),"Space 跳跃   Shift 蹬步   H 轨迹   C 镜头   Esc 暂停",12,MUTED)
	if phase=="serve":
		_text(left+Vector2(0,116),"松开 J / L 发球" if server==local_player else "对手准备发球",15,LIME)
	elif toast_time>0:
		_text(left+Vector2(0,116),toast,14,LIME)

func _bar(pos: Vector2, width: float, value: float, color: Color) -> void:
	draw_style_box(_style(Color("0b1923"),Color("0b1923"),4),Rect2(pos,Vector2(width,7)))
	draw_style_box(_style(color,color,4),Rect2(pos,Vector2(maxf(2,width*value/100),7)))

func _key(pos: Vector2, label: String) -> void:
	_box(Rect2(pos,Vector2(35,33)),Color("1c3540"),Color("38545b"),7)
	_center(pos+Vector2(17.5,24),label,17,LIME)

func _draw_point() -> void:
	_box(Rect2(494,343,472,125),Color(.04,.10,.13,.95),LINE,16)
	var name = "P1" if mode == "online" else "你"
	if last_winner == 1: name = "P2" if mode == "online" else "AI"
	_center(Vector2(730,392),"回合结束" if mode == "practice" else name + " 得分",29,LIME if last_winner == 0 else CORAL)
	_center(Vector2(730,432),last_reason + "  /  " + str(rally) + " 拍回合",17,MUTED)

func _draw_pause() -> void:
	draw_rect(scene_rect(),Color(0.015,.04,.06,.83))
	_box(Rect2(482,220,476,501),PANEL,LINE,24)
	_center(Vector2(720,287),"中场休息",38)
	_center(Vector2(720,320),"调整呼吸，下一拍继续。",16,MUTED)

func _draw_result() -> void:
	draw_rect(scene_rect(),Color(.015,.04,.06,.86))
	_box(Rect2(410,232,620,510),PANEL,LINE,24)
	_center(Vector2(720,280),"MATCH COMPLETE",14,LIME)
	var label = "你就是羽毛球高手！" if winner == 0 else "好球，再挑战一次！"
	if mode == "online": label = "P" + str(winner+1) + " 赢得比赛！"
	_center(Vector2(720,339),label,34)
	_center(Vector2(720,423),str(score[0]) + "  :  " + str(score[1]),62,LIME)
	_center(Vector2(720,480),"最长回合  " + str(longest_rally) + " 拍    ·    P1 甜区  " + str(perfect_hits) + " 次",18)
	_center(Vector2(720,521),"比赛时长  %02d:%02d" % [int(match_time)/60, int(match_time)%60],16,MUTED)
	_center(Vector2(720,573),"P1 球路  高远 %d  /  吊球 %d  /  杀抽 %d  /  挑球 %d" % shots_count,15,MUTED)

func _draw_help() -> void:
	_text(Vector2(80,172),"把每一拍，打得有想法。",38)
	_text(Vector2(82,212),"先移动到球下方，选择球路，按住蓄力后松开。脚下亮环表示进入击球范围。",18,MUTED)
	_box(Rect2(80,252,610,224),PANEL,LINE)
	_box(Rect2(718,252,610,224),PANEL,LINE)
	_text(Vector2(106,294),"01 / 玩家一",24,LIME)
	_text(Vector2(744,294),"02 / 在线对战",24,CORAL)
	var left = ["W A S D  移动     ·     方向 + 击球 = 指定落点", "J 放网 / 吊球    K 杀球 / 平抽    L 高远 / 挑球", "Space 跳跃    左 Shift 蹬步救球", "发球：J 网前短发球 / L 高远发球"]
	var right = ["双方在各自机器上使用同一套 WASD + J K L", "连接同一内网主机，创建房间或查看房间列表。", "双方都在自己的底线视角操作，自己背对镜头。", "密码可留空；双方完整打完后记录战绩。"]
	for i in range(4):
		_text(Vector2(106,333+i*35),left[i],16,WHITE if i < 2 else MUTED)
		_text(Vector2(744,333+i*35),right[i],16,WHITE if i < 2 else MUTED)
	var titles = ["拉开纵深", "打出落差", "抢到高点", "守住网前"]
	var lines = [["高远球压住底线，争取回位时间。","前场被动时用挑球解围。"],["按住 J：A/D 选左右，W/S 选深浅。","停步保留瞄准；近网自动变为放网。"],["高点 K 杀球；低点自动平抽。","Space 起跳后，接 K 打出跳杀。"],["接球时用蹬步扩大救球范围。","脚下亮环时出手，避免过早挥空。"]]
	for i in range(4):
		var x = 80+i*318
		_box(Rect2(x,502,294,193),PANEL,LINE)
		_text(Vector2(x+20,540),"0"+str(i+1),15,LIME)
		_text(Vector2(x+20,578),titles[i],23)
		_text(Vector2(x+20,616),lines[i][0],13,MUTED)
		_text(Vector2(x+20,646),lines[i][1],13,MUTED)
	_text(Vector2(82,736),"规则：单打内边线，落地得分；下网 / 出界失分。每球得分，赢球方发球，发球左右区随本方分数交替。",16,WHITE)
	_text(Vector2(82,769),"比赛统一为 11 分制，需领先 2 分，15 分封顶。练习模式不计输赢。",14,MUTED)
	_text(Vector2(82,807),"短蓄力 0.1–0.5 秒，松键挥拍；提前松键可缓冲接球。H 轨迹 / 落点，C 切换视角。",14,LIME)

# Host-authoritative simulation; a small WebSocket service routes room traffic.
func _show_lobby() -> void:
	screen = "lobby"
	_clear_ui()
	if server_address.is_empty():
		server_address = "ws://127.0.0.1:8766/ws"
		if OS.has_feature("web"):
			server_address = str(JavaScriptBridge.eval("window.ACE_SERVER || (location.protocol === 'file:' ? 'ws://127.0.0.1:8766/ws' : (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws')"))
	nickname_input = _input_box(Rect2(405,248,280,43),nickname,"你的昵称（最多 16 字）")
	nickname_input.max_length = 16
	password_input = _input_box(Rect2(705,248,330,43),room_password,"房间密码（留空为公开房）")
	password_input.max_length = 32
	password_input.secret = true
	address_input = _input_box(Rect2(405,312,630,52),server_address,"主机内网地址，例如 ws://192.168.1.8:8766/ws")
	address_input.hide()
	code_input = _input_box(Rect2(405,463,320,57),room_code,"输入六位房间码")
	code_input.max_length = 6
	code_input.hide()
	_button("查看空闲房间",Rect2(405,463,630,57),func(): _request_lobby_data("list"),true)
	_button("创建房间",Rect2(405,385,630,55),func(): _connect_room("create"))
	invite_input = _input_box(Rect2(355,648,680,45),lan_address if lan_only else invite_url,"开房后显示主机内网连接地址；请同时分享房间码")
	invite_input.editable = false
	invite_input.add_theme_font_size_override("font_size",14)
	invite_input.hide()
	copy_invite_button = _button("复制连接信息",Rect2(1045,648,138,45),_copy_invite)
	copy_invite_button.disabled = invite_url.is_empty() and lan_address.is_empty()
	copy_invite_button.hide()
	_button("战绩排行榜",Rect2(405,711,280,45),func(): _request_lobby_data("leaders"))
	_button("我的角色 · " + ("女" if selected_avatar=="female" else "男") + "   /   更换",Rect2(405,653,630,42),_show_avatar_selection)
	_button("连接设置",Rect2(705,711,330,45),_show_connection_settings)
	_button("返回主场",Rect2(565,794,310,42),_build_menu)

func _show_connection_settings() -> void:
	room_password = password_input.text
	nickname = nickname_input.text
	screen = "connection_settings"
	for child in ui.get_children(): child.hide()
	address_input.show()
	address_input.position = Vector2(370,350)
	address_input.size = Vector2(700,55)
	_button("保存连接地址",Rect2(500,450,440,50),func():
		server_address = address_input.text.strip_edges()
		_disconnect()
		var c = ConfigFile.new()
		c.load("user://settings.cfg")
		c.set_value("game","server_override",server_address)
		c.save("user://settings.cfg")
		_show_lobby())
	_button("返回",Rect2(500,530,440,50),_show_lobby)

func _show_room_password(code: String) -> void:
	_show_lobby()
	code_input.text = code
	screen = "room_password"
	for child in ui.get_children(): child.hide()
	password_input.show()
	password_input.position = Vector2(500,365)
	password_input.size = Vector2(440,55)
	password_input.placeholder_text = "请输入房主设置的密码"
	password_input.grab_focus()
	_button("进入房间",Rect2(500,450,440,50),func(): _connect_room("join"),true)
	_button("返回",Rect2(500,530,440,50),_show_lobby)

func _request_lobby_data(action: String) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN and net_connected:
		_net_send({"type":action})
	else: _connect_room(action)

func _show_board(kind: String, rows: Array) -> void:
	screen = kind
	_clear_ui()
	board_items = ItemList.new()
	board_items.position = Vector2(260,250)
	board_items.size = Vector2(920,450)
	board_items.add_theme_font_override("font",FONT)
	board_items.add_theme_font_size_override("font_size",21)
	board_items.add_theme_constant_override("v_separation",18)
	board_items.add_theme_stylebox_override("panel",_style(PANEL,LINE,16))
	ui.add_child(board_items)
	if kind == "rooms": rows = rows.filter(func(row): return int(row.players)<2 and str(row.code)!=room_code)
	for row in rows:
		if kind == "rooms":
			var description = "%s  ·  %s  ·  %d / 2 人  ·  %d 分制  ·  %s" % [str(row.code),str(row.name),int(row.players),int(row.goal),"有密码" if row.locked else "公开"]
			board_items.add_item(description)
			board_items.set_item_metadata(board_items.item_count-1,row)
		else:
			var rate = roundi(100.0*int(row.wins)/maxi(1,int(row.games)))
			board_items.add_item("%02d    %s    ·    %d 胜 / %d 场    ·    胜率 %d%%" % [board_items.item_count+1,str(row.name),int(row.wins),int(row.games),rate])
	if rows.is_empty(): board_items.add_item("暂时没有等待房间，创建一个吧。" if kind == "rooms" else "还没有战绩，完成一场双人比赛后再来看。",null,false)
	if kind == "rooms":
		_button("进入房间",Rect2(260,778,260,48),func():
			var selected = board_items.get_selected_items()
			if selected.is_empty(): return
			var row = board_items.get_item_metadata(selected[0])
			if row == null: return
			if int(row.players) >= 2:
				net_status = "这个房间已经满了，请选另一个。"
				return
			var selected_code = str(row.code)
			room_password = ""
			_show_lobby()
			code_input.text = selected_code
			if bool(row.locked):
				net_status = ""
				_show_room_password(selected_code)
			else: _connect_room("join"))
	_button("刷新",Rect2(550,778,260,48),func(): _net_send({"type":"list" if kind == "rooms" else "leaders"}))
	_button("返回房间页",Rect2(840,778,340,48),_show_lobby)

func _input_box(rect: Rect2, value: String, placeholder: String) -> LineEdit:
	var edit = LineEdit.new()
	edit.position = rect.position
	edit.size = rect.size
	edit.text = value
	edit.placeholder_text = placeholder
	edit.add_theme_font_override("font",FONT)
	edit.add_theme_font_size_override("font_size",19)
	edit.add_theme_color_override("font_color",WHITE)
	edit.add_theme_stylebox_override("normal",_style(Color("0b1923"),LINE,10))
	edit.add_theme_stylebox_override("focus",_style(Color("0b1923"),LIME,10))
	ui.add_child(edit)
	return edit

func _draw_lobby() -> void:
	_center(Vector2(720,170),"隔着屏幕，也能一决高下。",37)
	_center(Vector2(720,211),"LAN DUEL / 局域网双人对战",16,LIME)
	_box(Rect2(235,232,970,541),PANEL,LINE,22)
	_center(Vector2(720,332),"密码留空创建公开房；设置密码，仅邀请知道密码的朋友。",16,MUTED)
	_center(Vector2(720,557),net_status,15,LIME)
	if not room_code.is_empty():
		_center(Vector2(720,603),"房间码  " + room_code,32,WHITE)
	_center(Vector2(720,632),"创建后等待对手；对方在空闲房间列表选择你的房间即可。",15,MUTED)
	_center(Vector2(720,785),"同一局域网 · 服务器保持运行 · 无需填写连接地址",13,MUTED)

func _connect_room(action: String) -> void:
	var wanted_code = code_input.text.strip_edges().to_upper()
	nickname = nickname_input.text.strip_edges()
	room_password = password_input.text
	_save_settings()
	server_address = address_input.text.strip_edges()
	# Accept a page or invitation URL, but connect to its /ws endpoint.
	if server_address.begins_with("https://") or server_address.begins_with("http://"):
		var scheme = "wss://" if server_address.begins_with("https://") else "ws://"
		var authority = server_address.split("://",true,1)[1].split("/")[0].split("?")[0].split("#")[0]
		server_address = scheme + authority + "/ws"
		address_input.text = server_address
	if not server_address.begins_with("ws://") and not server_address.begins_with("wss://"):
		net_status = "服务地址需要以 ws:// 或 wss:// 开头。"
		return
	if action == "join" and wanted_code.length() != 6:
		net_status = "请输入朋友的六位房间码。"
		return
	_disconnect()
	room_code = wanted_code if action == "join" else ""
	net_action = action
	net_status = "正在连接服务…"
	net_connect_elapsed = 0.0
	socket = WebSocketPeer.new()
	var error = socket.connect_to_url(server_address)
	if error != OK:
		net_status = "无法连接服务，请检查地址。"
		socket = null

func _disconnect() -> void:
	if socket != null: socket.close(1000,"Leaving room")
	socket = null
	net_connected = false
	net_role = ""
	room_code = ""
	invite_url = ""
	lan_address = ""
	lan_only = true
	connection_scope = "local"
	if is_instance_valid(invite_input): invite_input.text = ""
	if is_instance_valid(copy_invite_button): copy_invite_button.disabled = true
	remote_move = Vector2.ZERO
	net_match_id = ""
	net_status = "创建一个房间，或输入朋友分享的房间码。"

func _copy_invite() -> void:
	var share_text = invite_url
	if not lan_address.is_empty() and (lan_only or invite_url.is_empty()):
		share_text = "谁是羽毛球高手 · 局域网对战\n连接地址：" + lan_address + "\n房间码：" + room_code + "\n请完整解压游戏包，打开本地 index.html，在在线对战中填写地址和房间码。"
	if share_text.is_empty(): return
	var copied = true
	if OS.has_feature("web"):
		copied = bool(JavaScriptBridge.eval("(()=>{const t=document.createElement('textarea');t.value="+JSON.stringify(share_text)+";t.style.position='fixed';t.style.opacity='0';document.body.appendChild(t);t.select();const ok=document.execCommand('copy');t.remove();return ok})()"))
	else: DisplayServer.clipboard_set(share_text)
	net_status = "已复制网页邀请，朋友打开后会自动加入。" if copied else "请选中下方网页链接，按 Ctrl+C 复制。"
	if connection_scope == "lan": net_status = "已复制内网连接地址和房间码，请在游戏中填写。" if copied else "请手动复制下方连接地址，并告知朋友房间码。"

func _net_send(packet: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify(packet))

func _network_process(dt: float) -> void:
	diagnostic_tick += dt
	if OS.has_feature("web") and diagnostic_tick > .20:
		diagnostic_tick = 0
		var state = {"screen":screen,"phase":phase,"mode":mode,"role":net_role,"room":room_code,"status":net_status,"invitation":invite_url,"scope":connection_scope,"score":score,"hits":total_hits,"rally":rally,"paused":paused,"server":server,"last_hit":last_hit,"ball":[ball.x,ball.y,ball.z],"velocity":[velocity.x,velocity.y,velocity.z],"players":[[players[0].pos.x,players[0].pos.y],[players[1].pos.x,players[1].pos.y]],"baseline_camera":baseline_camera,"guide":guide_on,"selected_avatar":selected_avatar,"avatars":[players[0].avatar,players[1].avatar],"ball_screen":[_project(ball).x,_project(ball).y],"view_player":_local_player_index(),"footwork":[players[0].footwork,players[1].footwork]}
		state.render_size = [arena.size.x,arena.size.y]
		state.ui_scale = [ui.scale.x,ui.scale.y]
		state.ui_offset = [ui.position.x,ui.position.y]
		state.court_corners = []
		for corner in [Vector3(-3.05,-6.7,0),Vector3(3.05,-6.7,0),Vector3(-3.05,6.7,0),Vector3(3.05,6.7,0)]:
			var at = _project(corner)
			at = (at*interface_scale()+interface_offset())/get_viewport_rect().size*Vector2(1440,900)
			state.court_corners.append([at.x,at.y])
		if screen=="menu":
			state.demo_leg = demo_leg
			state.pelvis_heights = []
			for athlete in arena.athletes:
				state.pelvis_heights.append(athlete.poses[athlete.bones.pelvis].origin.y)
		JavaScriptBridge.eval("window.badmintonState="+JSON.stringify(state)+";")
	if socket == null: return
	socket.poll()
	var ready = socket.get_ready_state()
	if ready == WebSocketPeer.STATE_CLOSED:
		var was_connected = net_connected
		socket = null
		net_connected = false
		net_status = "连接已断开，请重新连接。" if was_connected else "连接失败，请确认联机服务已启动、地址可达。"
		if screen == "game":
			paused = true
			_show_lobby()
		return
	if ready != WebSocketPeer.STATE_OPEN:
		net_connect_elapsed += dt
		if net_connect_elapsed > 10:
			socket.close()
			socket = null
			net_status = "连接超时。请检查同一局域网、主机服务和防火墙，勿填写对方的 127.0.0.1。"
		return
	if not net_connected:
		net_connected = true
		var identities = ConfigFile.new()
		identities.load("user://identities.cfg")
		_net_send({"type":"hello","name":nickname,"token":str(identities.get_value("servers",server_address,""))})
	while socket != null and socket.get_available_packet_count() > 0:
		var decoded = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if decoded is Dictionary: _receive_packet(decoded)
	if screen != "game" or mode != "online": return
	net_tick += dt
	net_ping += dt
	if net_ping > 2:
		net_ping = 0
		_net_send({"type":"ping","stamp":Time.get_ticks_msec()})
	if net_role == "guest" and not paused: remote_view.render(self,dt)
	if net_tick < 1.0/30.0: return
	net_tick = 0
	if net_role == "host": _send_snapshot()
	elif net_role == "guest":
		var move = Vector2.ZERO if paused else Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
		_net_send({"type":"input","action":"move","x":-move.x,"y":-move.y,"avatar":selected_avatar})

func _send_snapshot() -> void:
	var ps = []
	for p in players:
		ps.append({"motion":FOOTWORK.snapshot(p),"avatar":p.avatar,"pos":[p.pos.x,p.pos.y],"vel":[p.vel.x,p.vel.y],"stamina":p.stamina,"jump":p.jump,"swing":p.swing,"stroke":p.stroke,"landing":p.landing,"dash":p.dash,"buffer":p.buffer,"shot":p.shot,"charge":p.charge,"charge_time":p.charge_time,"step":p.step,"backhand":p.backhand,"shot_aim":[p.shot_aim.x,p.shot_aim.y],"last_drop_x":p.last_drop_x,"drop_count":p.drop_count})
	_net_send({"type":"state","players":ps,"ball":[ball.x,ball.y,ball.z],"velocity":[velocity.x,velocity.y,velocity.z],"phase":phase,"score":score,"server":server,"last_hit":last_hit,"rally":rally,"longest":longest_rally,"hits":total_hits,"perfect":perfect_hits,"shots":shots_count,"winner":winner,"last_winner":last_winner,"reason":last_reason,"speed":last_speed,"time":match_time,"paused":paused})

func _receive_packet(d: Dictionary) -> void:
	match d.get("type",""):
		"profile":
			nickname = str(d.name)
			var identities = ConfigFile.new()
			identities.load("user://identities.cfg")
			identities.set_value("servers",server_address,str(d.token))
			identities.save("user://identities.cfg")
			_save_settings()
			_net_send({"type":net_action,"code":room_code,"goal":GOAL_SCORE,"password":room_password})
		"rooms":
			net_status = "选择公开房直接加入；有密码房需填写密码。"
			_show_board("rooms",d.rooms)
		"leaders":
			net_status = "战绩保存在当前主机；清理浏览器数据会失去原游客身份。"
			_show_board("ranking",d.players)
		"recorded":
			result_recorded = true
			toast = "双方确认完成，战绩已保存"
			toast_time = 4.0
		"connection":
			connection_scope = str(d.get("scope","local"))
			lan_only = bool(d.get("lanOnly",false))
			lan_address = str(d.get("lanAddress",""))
		"created":
			if screen=="avatars": _show_lobby()
			net_role = "host"
			room_code = str(d.code)
			net_status = "房间已创建，请复制下面的网页邀请链接。"
			code_input.text = room_code
			invite_url = str(d.get("invitation",""))
			connection_scope = str(d.get("scope","local"))
			lan_only = bool(d.get("lanOnly",false))
			lan_address = str(d.get("lanAddress",""))
			invite_input.text = lan_address if lan_only or invite_url.is_empty() else invite_url
			copy_invite_button.disabled = invite_url.is_empty() and lan_address.is_empty()
			if not lan_address.is_empty() and (lan_only or invite_url.is_empty()): net_status = "房间已创建，等待对手从空闲房间列表进入。"
			elif invite_url.is_empty(): net_status = "仅有本机连接，未检测到可分享的内网地址，请检查网络。"
		"start":
			remote_avatar = "male"
			net_role = str(d.role)
			room_code = str(d.code)
			net_match_id = str(d.match)
			result_recorded = false
			start_game("online")
			net_targets = [players[0].pos,players[1].pos]
			net_ball = ball
			if net_role=="guest": _net_send({"type":"input","action":"move","x":0,"y":0,"avatar":selected_avatar})
		"error": net_status = str(d.get("message","房间连接失败"))
		"peer_left":
			paused = true
			net_status = "对手离开了房间，请重新创建或加入。"
			_show_lobby()
		"pong": net_rtt = int(Time.get_ticks_msec()-int(d.stamp))
		"pause":
			if bool(d.value):
				paused = true
				_pause_menu()
			else:
				paused = false
				screen = "game"
				_build_match_ui()
		"input":
			if net_role != "host" or phase == "end": return
			var p = players[1]
			match d.get("action",""):
				"move":
					remote_move = Vector2(clampf(float(d.x),-1,1),clampf(float(d.y),-1,1))
					remote_avatar = _avatar_id(d.get("avatar","male"))
					p.avatar = remote_avatar
				"jump":
					if not paused: _jump(1)
				"dash":
					if not paused: _dash(1)
				"shot":
					if paused: return
					var shot = clampi(int(d.shot),0,3)
					if bool(d.pressed):
						p.charge = shot
						p.charge_time = 0.0
						p.shot_aim = p.aim
					elif p.charge == shot:
						p.charge = -1
						p.shot = shot
						p.buffer = .36
						_try_hit(1,shot)
		"effect":
			if net_role == "guest":
				var at = Vector2(float(d.pos[0]),float(d.pos[1]))
				if d.has("world"):
					at = _project(Vector3(float(d.world[0]),float(d.world[1]),float(d.world[2])))+Vector2(0,float(d.get("offset_y",0)))
				_effect(at,str(d.label),Color(str(d.color)))
				_burst(at,Color(str(d.color)),9)
				_sfx("smash" if "杀" in str(d.label) else "hit")
		"rematch":
			net_match_id = str(d.match)
			result_recorded = false
			start_game("online")
		"state":
			if net_role != "guest": return
			remote_view.push(d)
			for i in range(2):
				var p = d.players[i]
				FOOTWORK.receive(players[i],p.get("motion",{}))
				players[i].avatar = selected_avatar if i==1 else _avatar_id(p.get("avatar","male"))
				if i==0: remote_avatar = players[i].avatar
				net_targets[i] = Vector2(float(p.pos[0]),float(p.pos[1]))
				players[i].vel = Vector2(float(p.vel[0]),float(p.vel[1]))
				players[i].shot_aim = Vector2(float(p.shot_aim[0]),float(p.shot_aim[1]))
				players[i].last_drop_x = float(p.last_drop_x)
				players[i].drop_count = int(p.drop_count)
				for key in ["stamina","jump","swing","stroke","landing","shot","charge","charge_time","step","backhand"]: players[i][key] = p[key]
				for key in ["dash","buffer"]: players[i][key] = p.get(key,0.0)
			net_ball = Vector3(float(d.ball[0]),float(d.ball[1]),float(d.ball[2]))
			var old_phase = phase
			phase = str(d.phase)
			if old_phase=="serve" and phase=="rally": toast_time = 0
			score = [int(d.score[0]),int(d.score[1])]
			server = int(d.server)
			last_hit = int(d.last_hit)
			rally = int(d.rally)
			longest_rally = int(d.longest)
			total_hits = int(d.hits)
			perfect_hits = int(d.perfect)
			shots_count = d.shots
			last_winner = int(d.last_winner)
			last_reason = str(d.reason)
			last_speed = int(d.speed)
			match_time = float(d.time)
			if phase == "end" and old_phase != "end": _end_match(int(d.winner))
			if phase == "point" and old_phase != "point": _sfx("point")

func _rematch() -> void:
	if mode == "online":
		_net_send({"type":"rematch"})
	else: start_game(mode)

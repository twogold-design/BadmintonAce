extends SceneTree
func _initialize():call_deferred("run")
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.session_token="saved-test-session";game._show_login()
	var buttons=[]
	for child in game.ui.get_children():
		if child is Button:buttons.append(child.text)
	var ok=buttons==["登录","单机游玩"] and game.login_password.secret and game.socket==null
	game._enter_offline()
	ok=ok and game.offline_mode and not game.authenticated and game.screen=="menu" and game.socket==null
	game._show_challenges()
	game._start_challenge("chen-yufei")
	ok=ok and game.screen=="game" and game.players[1].avatar=="female" and game.challenge_id.is_empty()
	game.score=[11,0]
	game._end_match(0)
	ok=ok and game.phase=="end" and game.account_points==0 and not game.result_recorded and game.socket==null
	game._rematch()
	ok=ok and game.phase=="serve" and game.challenge_opponent=="chen-yufei"
	game._build_menu()
	game.start_game("practice")
	ok=ok and game.mode=="practice" and game.socket==null
	game._build_menu()
	game._show_lobby()
	ok=ok and game.screen=="login" and not game.offline_mode and game.socket==null
	print("LOGIN / OFFLINE ENTRY: ","PASS" if ok else "FAILED", " buttons=",buttons)
	game.queue_free();quit(0 if ok else 1)

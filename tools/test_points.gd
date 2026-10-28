extends SceneTree
var game
var account = ""
var failures = 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	if not ok: failures += 1; push_error(label)
func until(predicate: Callable) -> bool:
	for i in range(600):
		if predicate.call(): return true
		await create_timer(.02).timeout
	push_error("Timed out: " + game.screen + " / " + game.net_status)
	quit(1)
	return false
func run():
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.sound_on = false
	game._show_login()
	game.server_address = OS.get_environment("TEST_URL")
	account = OS.get_environment("ACE_POINTS_ACCOUNT")
	game.login_name.text = account
	game.login_password.text = "points-ui-pass"
	game._submit_auth("register")
	await until(func(): return game.authenticated and game.screen=="menu")
	check(game.account_points==0,"New account starts at zero")
	game._show_challenges()
	check(game.opponents.size()==8,"Eight named challengers")
	for opponent in ["shi-yuqi","shi-yuqi","chen-yufei"]:
		game._start_challenge(opponent)
		await until(func(): return game.screen=="game")
		check(game.players[1].avatar==("female" if opponent=="chen-yufei" else "male"),"Opponent appearance follows roster")
		game.score=[11,7]
		game._end_match(0)
		await until(func(): return game.result_recorded)
		game._show_challenges()
	check(game.account_points==10,"Repeat win does not duplicate first-win points")
	check(game.completed_opponents.size()==2,"Completion marks survive selection changes")
	game._build_menu()
	await until(func(): return game.leaders_loaded)
	game._logout()
	game.login_name.text=account
	game.login_password.text="points-ui-pass"
	game._submit_auth("login")
	await until(func(): return game.authenticated and game.screen=="menu")
	check(game.account_points==10 and game.completed_opponents.size()==2,"Login restores points and rewards")
	game._disconnect()
	print("POINTS UI: failures=",failures)
	quit(1 if failures else 0)

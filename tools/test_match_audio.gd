extends SceneTree
## Exercise real match audio players through scoring and network entry points.

class AudioGame:
	extends "res://scripts/main.gd"
	var sent_state: Dictionary = {}
	func _save_settings() -> void:
		pass # Test results must not alter the user's sound preference.
	func _net_send(packet: Dictionary) -> bool:
		if packet.get("type", "") == "state": sent_state = packet.duplicate(true)
		return false # No accounts or live matches are touched by this test.

var checks = 0
var failures = 0
var game

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func fresh(mode_name: String = "ai", role: String = "") -> void:
	game.sound_on = true
	game.test_mode = false
	game.offline_mode = true
	game.net_role = role
	game.start_game(mode_name)

func packet(seq: int, scores: Array, next_phase: String, who: int = 0) -> Dictionary:
	game._send_snapshot()
	var state: Dictionary = game.sent_state.duplicate(true)
	state.merge({"seq":seq, "match":game.net_match_id, "score":scores,
		"phase":next_phase, "winner":who, "time":float(seq)}, true)
	return state

func check_decoding(stream: AudioStream, label: String) -> void:
	var playback = stream.instantiate_playback()
	check(playback != null, label + " creates a decoder")
	if playback == null: return
	playback.start()
	var peak = 0.0
	# Inspect enough of the intro to allow a short natural lead-in.
	for block in range(16):
		var samples: PackedVector2Array = playback.mix_audio(1.0, 4096)
		for sample in samples:
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		if peak > .0001: break
	playback.stop()
	check(peak > .0001, label + " decodes to audible PCM samples")

func run() -> void:
	game = AudioGame.new()
	game.offline_mode = true
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	fresh()
	check(game.cheer_player != game.result_player, "Cheer and result use separate players")
	check(not game.voices.has(game.cheer_player), "Hit sound pool cannot interrupt cheers")
	var selected: Dictionary = {}
	game.cheer_rng.seed = 20261116
	for i in range(64):
		game._score_cheer()
		var stream: AudioStreamOggVorbis = game.cheer_player.stream
		check(stream != null and stream.get_length() > 0 and not stream.loop, "Cheer has valid non-looping imported audio")
		selected[stream.resource_path.get_file()] = true
	check(selected.size() == 3 and selected.has("SFX_Cheer_a.ogg") and selected.has("SFX_Cheer_b.ogg") and selected.has("SFX_Cheer_c.ogg"), "Random selection reaches all three supplied cheers")
	for filename in ["SFX_Cheer_a.ogg", "SFX_Cheer_b.ogg", "SFX_Cheer_c.ogg", "SFX_Win.ogg", "SFX_Lose.ogg"]:
		var sample: AudioStreamOggVorbis = load("res://assets/audio/" + filename)
		check(sample != null and sample.get_length() > 0 and not sample.loop, filename + " is valid and non-looping")
		check_decoding(sample, filename)

	fresh()
	game.phase = "rally"
	game._point(0, "test point")
	check(game.score == [1, 0] and game.cheer_player.playing, "A local score plays a cheer")
	game.cheer_player.stop()
	game._point(0, "duplicate")
	check(game.score == [1, 0] and not game.cheer_player.playing, "A repeated point call cannot replay the cheer")
	fresh("practice")
	game.phase = "rally"
	game._point(0, "practice")
	check(game.score == [0, 0] and game.cheer_player.playing, "Practice rally completion cheers without changing the score")

	fresh("online", "guest")
	game.offline_mode = false
	game.net_match_id = "audio-test"
	var scored = packet(1, [1, 0], "point")
	game._receive_peer_packet(scored)
	check(game.cheer_player.playing, "Guest cheers when the authoritative score increases")
	game.cheer_player.stop()
	game._receive_peer_packet(scored)
	check(not game.cheer_player.playing, "Duplicate network sequence does not replay audio")
	game._receive_peer_packet(packet(2, [1, 0], "point"))
	check(not game.cheer_player.playing, "A newer snapshot with the same score does not replay audio")
	game._receive_peer_packet(packet(3, [1, 1], "serve"))
	check(game.cheer_player.playing, "Guest cheers even when the point phase was skipped")
	game.cheer_player.stop()
	game._receive_peer_packet(packet(4, [11, 1], "end", 0))
	check(not game.cheer_player.playing and game.result_player.playing and game.result_player.stream == game.LOSE_SAMPLE, "A losing guest hears defeat audio when point phase is skipped")
	game.result_player.stop()
	game._receive_peer_packet(packet(5, [11, 1], "end", 0))
	check(not game.cheer_player.playing and not game.result_player.playing, "Repeated end snapshots do not replay match audio")

	for result in [["ai", "", 0, true], ["ai", "", 1, false], ["online", "host", 0, true], ["online", "host", 1, false], ["online", "guest", 1, true], ["online", "guest", 0, false], ["local", "", 1, true]]:
		fresh(result[0], result[1])
		game._score_cheer()
		game._end_match(result[2], false)
		check(game.result_player.playing, "A finished match plays result audio: " + str(result))
		check(game.result_player.stream == (game.WIN_SAMPLE if result[3] else game.LOSE_SAMPLE), "Win or loss sound follows local ownership: " + str(result))
		check(not game.cheer_player.playing, "Result sound replaces the active score cheer")
		game.result_player.stop()
		game._end_match(result[2], false)
		check(not game.result_player.playing, "Repeated result cannot replay win or loss audio: " + str(result))

	fresh()
	game._score_cheer()
	game._pause_menu()
	game._sync_match_audio()
	check(game.cheer_player.stream_paused, "Pause freezes the active cheer")
	game._resume()
	game._sync_match_audio()
	check(not game.cheer_player.stream_paused and game.cheer_player.playing, "Resume continues the active cheer")
	game._toggle_sound()
	check(not game.cheer_player.playing and not game.result_player.playing, "Turning sound off stops match audio immediately")
	game._score_cheer()
	game._end_match(0, false)
	check(not game.cheer_player.playing and not game.result_player.playing, "Muted scoring and victory stay silent")
	game.sound_on = true
	game._result_sfx(0)
	check(not game.result_player.playing, "Unmuting after the result does not replay victory")
	fresh()
	game.sound_on = false
	game._end_match(1, false)
	check(not game.result_player.playing, "Muted defeat stays silent")
	game.sound_on = true
	game._result_sfx(1)
	check(not game.result_player.playing, "Unmuting after defeat cannot replay its result")
	fresh()
	check(not game.result_audio_handled, "Starting another match resets victory deduplication")
	game._end_match(0, false)
	check(game.result_player.playing, "A fresh match can play victory again")
	game._rematch()
	check(not game.result_player.playing and not game.cheer_player.playing and not game.result_audio_handled, "Rematch stops previous audio and resets its result")
	game._score_cheer()
	game._build_menu()
	check(not game.cheer_player.playing and not game.result_player.playing, "Returning to the menu immediately stops match audio")
	for who in [0, 1]:
		fresh()
		game._end_match(who, false)
		check(game.result_player.playing, "Result audio is active before leaving: winner " + str(who))
		game._build_menu()
		check(not game.result_player.playing and not game.cheer_player.playing, "Returning from results immediately stops win or loss audio")
		fresh("online", "guest")
		game._end_match(who, false)
		check(game.result_player.playing, "Guest result audio is active before requesting a rematch")
		game._rematch()
		check(game.phase == "end" and not game.result_player.playing and not game.cheer_player.playing, "Online rematch stops audio immediately while waiting for the other player")
		game._end_match(who, false)
		check(not game.result_player.playing, "A repeated result while waiting for online rematch cannot restart win or loss audio")
	fresh()
	game._end_match(1, false)
	game._toggle_sound()
	check(not game.result_player.playing, "Muting an active defeat sample stops it immediately")
	fresh()
	game._end_match(1, false)
	game._rematch()
	check(not game.result_player.playing and not game.result_audio_handled, "Offline rematch stops defeat audio and resets result deduplication")
	fresh()
	game._score_cheer()
	game.screen = "help"
	game._sync_match_audio()
	check(not game.cheer_player.playing, "Leaving the match screen stops its audio")
	fresh()
	game.test_mode = true
	game._score_cheer()
	game._result_sfx(0)
	check(not game.cheer_player.playing and not game.result_player.playing, "Automated gameplay mode suppresses both samples")
	game.test_mode = false
	game._stop_match_audio()
	for voice in game.voices: voice.stop()
	# Give the audio mixer time to retire stopped playback objects before exit.
	await create_timer(.15).timeout
	game.queue_free()
	await create_timer(.15).timeout
	print("MATCH AUDIO: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

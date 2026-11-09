extends SceneTree
## Use --display-driver headless --audio-driver PulseAudio on Linux to test
## actual backend mixing. AudioEffectCapture captures only this app's UI bus.
const Sound = preload("res://menu_audio.gd")
var checks := 0
var failures := 0
var capture := AudioEffectCapture.new()
var ui_bus := -1
var events: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func on_sound(kind: String) -> void:
	events.append(kind)

func peak() -> float:
	var frames := capture.get_buffer(capture.get_frames_available())
	var maximum := 0.0
	for sample in frames: maximum = maxf(maximum, maxf(absf(sample.x), absf(sample.y)))
	return maximum

func play_and_check(sound: AudioStreamPlayer, kind: String) -> void:
	capture.clear_buffer()
	sound.call({"click": "click", "start": "start_session", "complete": "complete_session"}[kind])
	check(sound.playing and sound.stream == sound.sounds[kind], "Player starts the requested cue")
	await create_timer(sound.stream.get_length() + 0.12).timeout
	var output_peak := peak()
	check(output_peak > 0.1 and output_peak < 0.8, "Audible unclipped audio reaches UI bus: " + kind)
	check(not sound.playing, "Cue finishes without looping")
	print("Audio ", kind, ": duration=", sound.stream.get_length(), " output peak=", snappedf(linear_to_db(output_peak), 0.1), " dBFS")

func prepare_block(game: Control) -> void:
	if game.phase == game.Phase.TRANSITION_DRAWING:
		game._on_frame_presented()
		game._advance(game.deadline_us)
	game._on_frame_presented()
	game._advance(game.deadline_us)
	for i in 3: game._advance(game.deadline_us)
	check(game.phase == game.Phase.GAP, "Preparation completes without sound")

func test_mode(selected_mode: String) -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.history.path = "/tmp/visual-attention-audio-%s-%d.json" % [selected_mode, OS.get_process_id()]
	game.history.entries = []
	game.rng.seed = 471
	check(not game.audio.muted and game.mute.text == "Mute", "App defaults to unmuted")
	game.audio.sound_started.connect(on_sound)
	game._select_mode(selected_mode)
	await create_timer(0.15).timeout
	events.clear()
	capture.clear_buffer()
	game._start_session()
	check(events == ["start"], "Start cue in " + selected_mode)
	await create_timer(0.4).timeout
	check(peak() > 0.1, "Session start reaches real audio mixer")
	prepare_block(game)
	game._toggle_mute()
	check(game.audio.muted and game.mute.text == "Unmute", "In-test mute works")
	game._toggle_mute()
	check(not game.audio.muted and game.mute.text == "Mute" and events == ["start"], "In-test unmute stays silent")
	for i in 40:
		game._advance(game.deadline_us)
		game._on_frame_presented()
		check(events == ["start"], "No stimulus-onset audio")
		var deadline: int = game.responses.deadline_us
		if game.Stimuli.is_target(game.sequence[i], game.active_targets):
			game.responses.respond(game.responses.onset_us + 250123)
			var input := InputEventMouseButton.new()
			input.button_index = MOUSE_BUTTON_LEFT
			input.pressed = true
			input.position = Vector2(10, 10)
			game._input(input)
		check(events == ["start"] and game.responses.deadline_us == deadline, "Responses stay silent and deadlines unchanged")
		game._advance(game.deadline_us)
		if (i + 1) % 10 == 0 and i < 39: prepare_block(game)
	check(events == ["start", "complete"], "Exactly start and completion cues for a session")
	check(game.latest.hits == 12 and is_equal_approx(game.latest.mean_ms, 250.123) and game.latest.accuracy == 100.0, "Audio leaves RT precision and scoring unchanged")
	capture.clear_buffer()
	await create_timer(0.45).timeout
	check(peak() > 0.1, "Session completion reaches real audio mixer")
	game._toggle_mute()
	events.clear()
	game._start_session()
	check(events.is_empty() and not game.audio.playing, "Muted session start suppressed")
	game._abort()
	game.audio.complete_session()
	check(events.is_empty() and not game.audio.playing, "Muted completion suppressed")
	var path: String = game.history.path
	game.queue_free()
	await create_timer(0.1).timeout
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func run() -> void:
	print("Audio backend: ", AudioServer.get_driver_name(), "; device: ", AudioServer.output_device)
	check(AudioServer.get_driver_name() != "Dummy", "Use a real audio driver for this playback test")
	ui_bus = AudioServer.get_bus_index("UI")
	check(ui_bus >= 0, "Dedicated UI bus configured")
	if ui_bus < 0:
		quit(1)
		return
	check(AudioServer.get_bus_send(ui_bus) == &"Master" and not AudioServer.is_bus_mute(ui_bus) and not AudioServer.is_bus_mute(0), "UI routes to unmuted Master")
	check(AudioServer.get_bus_volume_db(ui_bus) == 0.0 and AudioServer.get_bus_volume_db(0) == 0.0, "Buses do not attenuate UI audio")
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(ui_bus, capture)
	var sound := Sound.new()
	root.add_child(sound)
	check(not sound.muted and sound.volume_db == -6.0 and sound.bus == &"UI", "Player defaults correctly configured")
	for kind in ["click", "start", "complete"]:
		var stream: AudioStreamWAV = sound.sounds[kind]
		check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 44100 and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Valid PCM WAV format")
		var source_peak := 0
		for i in int(stream.data.size() / 2.0): source_peak = maxi(source_peak, absi(stream.data.decode_s16(i * 2)))
		check(source_peak > 12000 and source_peak < 32767, "PCM contains strong nonzero samples without clipping")
		await play_and_check(sound, kind)
	sound.start_session()
	check(sound.playing, "Cue active before muting")
	sound.toggle()
	check(sound.muted and not sound.playing, "Mute stops active playback")
	await create_timer(0.1).timeout
	capture.clear_buffer()
	sound.click()
	sound.start_session()
	sound.complete_session()
	await create_timer(0.4).timeout
	check(peak() < 0.00001 and not sound.playing, "All cues silent while muted")
	sound.toggle()
	check(not sound.muted, "Unmute restores state")
	await play_and_check(sound, "click")
	sound.queue_free()
	await create_timer(0.1).timeout
	await test_mode("normal")
	await test_mode("advanced")
	AudioServer.remove_bus_effect(ui_bus, 0)
	print("Audio: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

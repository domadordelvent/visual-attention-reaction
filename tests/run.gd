extends SceneTree
const Stimuli = preload("res://stimuli.gd")
const Targets = preload("res://targets.gd")
const Responses = preload("res://responses.gd")
const Statistics = preload("res://statistics.gd")
const History = preload("res://history.gd")
var checks := 0
var failures := 0
var test_path := ""

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_path = "/tmp/visual-attention-test-%d.json" % OS.get_process_id()
	test_generation()
	test_dynamic_generation()
	test_responses()
	test_dynamic_responses()
	test_statistics()
	test_history()
	await test_flow("normal")
	await test_flow("advanced")
	for path in [test_path, test_path + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("%d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_generation() -> void:
	var rng := RandomNumberGenerator.new()
	var observed := {}
	var first_positions := {}
	for count in [10, 11, 17, 40, 199, 200]:
		for seed_value in 100:
			rng.seed = seed_value
			var sequence := Stimuli.generate(count, rng)
			check(sequence.size() == count, "Stimulus count")
			var targets := 0
			var run_length := 0
			var has_blue_distractor := false
			var has_other_square := false
			var first_target := -1
			for i in sequence.size():
				var item: Dictionary = sequence[i]
				check(item.gap >= 1.0 and item.gap <= 4.0, "Default gap bounds")
				check(item.shape in Stimuli.SHAPES and item.color >= 0 and item.color < 4, "Valid shape and color")
				observed[str(item.shape) + str(item.color)] = true
				if Stimuli.is_target(item):
					targets += 1
					run_length = 0
					if first_target < 0: first_target = i
				else:
					run_length += 1
					check(run_length <= 5, "Bounded distractor streak")
					has_blue_distractor = has_blue_distractor or item.color == 0
					has_other_square = has_other_square or item.shape == "square"
			check(targets == roundi(count * 0.3), "Exact intended proportion")
			check(has_blue_distractor and has_other_square, "Both near-target categories guaranteed")
			first_positions[first_target] = true
	check(observed.size() == 20, "All 20 shape/color combinations sampled")
	check(first_positions.size() > 3, "Target positions vary")
	rng.seed = 888
	var a := Stimuli.generate(40, rng, 2.0, 2.5)
	rng.seed = 888
	check(a == Stimuli.generate(40, rng, 2.0, 2.5), "Reproducible seeded generation")
	var gaps := {}
	for item in a:
		check(item.gap >= 2.0 and item.gap <= 2.5, "Configured gap bounds")
		gaps[item.gap] = true
	check(gaps.size() > 30, "Intervals randomized")
	check(Stimuli.is_target({"shape": "square", "color": 0}), "Recognize blue square")
	check(not Stimuli.is_target({"shape": "circle", "color": 0}), "Reject blue circle")
	check(not Stimuli.is_target({"shape": "square", "color": 1}), "Reject nonblue square")

func test_responses() -> void:
	var r := Responses.new()
	r.respond(100)
	check(r.trials.is_empty() and r.premature == 0, "Inactive clicks ignored")
	r.begin({"shape": "square", "color": 0}, 1000000, 1.0)
	r.respond(999999)
	check(not r.answered, "Pre-onset response ignored")
	r.respond(1250123)
	r.respond(1400000)
	r.finish()
	r.finish()
	check(r.trials.size() == 1, "Finish is idempotent")
	check(is_equal_approx(r.trials[0].rt_ms, 250.123), "Microsecond monotonic timestamp converted to milliseconds")
	r.begin({"shape": "circle", "color": 0}, 2000000, 1.0)
	r.respond(2300000)
	r.respond(2400000)
	r.finish()
	check(r.trials[1].responded and r.trials[1].rt_ms == null, "One false alarm, no distractor RT")
	r.begin({"shape": "square", "color": 0}, 4000000, 1.0)
	r.respond(5000000)
	r.finish()
	check(not r.trials[2].responded, "Click at deadline cannot rescue an omission")
	r.begin({"shape": "triangle", "color": 2}, 6000000, 1.0)
	r.finish()
	r.respond(7100000, true)
	r.respond(7200000, true)
	var stats := Statistics.calculate(r.trials, r.premature)
	check(stats.hits == 1 and stats.omissions == 1 and stats.false_alarms == 1 and stats.correct_rejections == 1, "All four response outcomes")
	check(stats.premature == 2 and stats.accuracy == 50.0, "Premature separate from accuracy")
	check(stats.mean_ms == stats.fastest_ms and stats.mean_ms == stats.slowest_ms, "Only valid target RT used")

func test_statistics() -> void:
	var trials: Array = []
	for time in [300.0, 100.0, 500.0, 200.0]:
		trials.append({"target": true, "responded": true, "rt_ms": time})
	var stats := Statistics.calculate(trials, 0)
	check(stats.mean_ms == 275.0 and stats.median_ms == 250.0, "Even median and mean")
	check(stats.fastest_ms == 100.0 and stats.slowest_ms == 500.0, "Extrema")
	trials.pop_back()
	stats = Statistics.calculate(trials, 0)
	check(stats.median_ms == 300.0, "Odd median")
	stats = Statistics.calculate([], 4)
	check(stats.accuracy == 0 and stats.mean_ms == null and stats.median_ms == null and stats.fastest_ms == null and stats.slowest_ms == null, "Empty session has no division errors")
	stats = Statistics.calculate([{"target": true, "responded": false, "rt_ms": null}], 0)
	check(stats.omissions == 1 and stats.mean_ms == null and stats.accuracy == 0, "Zero valid responses")

func test_history() -> void:
	var h := History.new()
	h.path = test_path
	h.load_sessions()
	check(h.entries.is_empty(), "Missing history safe")
	for i in 12:
		var result := Statistics.calculate([], i)
		check(h.record(result), "Save succeeds")
	check(h.entries.size() == 10 and h.entries[0].premature == 11 and h.entries[9].premature == 2, "History capped, newest first")
	var reloaded := History.new()
	reloaded.path = test_path
	reloaded.load_sessions()
	check(reloaded.entries == h.entries, "History round trip including null RTs")
	check(reloaded.entries[0].date is String, "Local date stored")
	check(reloaded.entries.size() == 10 and reloaded.for_mode("legacy").is_empty() and reloaded.for_mode("").is_empty(), "Unsupported history retained in storage without display support")
	for selected_mode in Targets.MODES:
		var result := Statistics.calculate([{"target": true, "responded": true, "rt_ms": 321.123}], 2)
		result["mode"] = selected_mode
		result["presentation_seconds"] = 1.0
		result["interval_min"] = 1.0
		result["interval_max"] = 4.0
		check(h.record(result), "Save new mode with old results")
	var stored_json := FileAccess.get_file_as_string(test_path)
	reloaded.load_sessions()
	check(reloaded.entries.size() == 10 and reloaded.for_mode("legacy").is_empty() and reloaded.for_mode("normal").size() == 1 and reloaded.for_mode("advanced").size() == 1, "Normal and Advanced records survive mixed-history round trips")
	check(is_equal_approx(reloaded.for_mode("advanced")[0].mean_ms, 321.123), "Mode history preserves millisecond statistics")
	check(FileAccess.get_file_as_string(test_path) == stored_json, "Loading and filtering history never rewrites saved results")
	var file := FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string("invalid json")
	file.close()
	reloaded.load_sessions()
	check(not reloaded.error.is_empty() and reloaded.entries.is_empty(), "Corrupt history handled")
	file = FileAccess.open(test_path, FileAccess.WRITE)
	file.store_string('[{}, {"date": 9}]')
	file.close()
	reloaded.load_sessions()
	check(not reloaded.error.is_empty() and reloaded.entries.is_empty(), "Malformed entries handled")
	h.path = "/tmp/visual-attention-missing-%d/no-dir/sessions.json" % OS.get_process_id()
	check(not h.record(Statistics.calculate([], 0)) and not h.error.is_empty(), "Save failure surfaced")

func click(game: Control, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	game._input(event)

func prepare_block(game: Control, index: int) -> void:
	if index > 0:
		check(game.phase == game.Phase.TRANSITION_DRAWING, "New-target announcement queued at block boundary")
		check(game.figure.item.is_empty() and not game.preview_row.visible, "Stimulus area cleared before target change")
		check(game.overlay.text == ("NEW TARGETS" if game.mode == "advanced" else "NEW TARGET"), "Prominent new-target message")
		check(game.progress_label.text.begins_with("Block %d/4" % (index + 1)), "Next block clearly labelled during transition")
		var before: int = game.responses.premature
		var recorded: int = game.responses.trials.size()
		click(game, Vector2(10, 10))
		game._on_frame_presented()
		check(game.phase == game.Phase.TRANSITION, "Announcement starts after rendering")
		check(game.deadline_us - Time.get_ticks_usec() > 1490000 and game.deadline_us - Time.get_ticks_usec() <= 1500000, "Announcement lasts 1.5 seconds")
		var deadline: int = game.deadline_us
		game._advance(deadline - 1)
		check(game.phase == game.Phase.TRANSITION, "Announcement cannot end early")
		click(game, Vector2(10, 10))
		game.deadline_us = 0
		click(game, Vector2(10, 10))
		check(game.phase == game.Phase.TRANSITION and game.responses.premature == before and game.responses.trials.size() == recorded and not game.responses.active, "Transition clicks ignored including deadline boundary")
		game.deadline_us = deadline
		game._advance(deadline)
		check(game.transition_tween == null and game.overlay.modulate == Color.WHITE, "Transition fade reset before preview")
	check(game.phase == game.Phase.DRAWING and game.drawing_preview, "Block preview queued")
	check(game.current_block == index and game.active_targets == game.blocks[index].targets, "Correct active block definitions")
	check(game.figure.item.is_empty(), "No test figure behind preview")
	for i in game.target_previews.size():
		check(game.target_previews[i].visible == (i < game.active_targets.size()), "Correct preview count")
		if i < game.active_targets.size(): check(Targets.same(game.target_previews[i].item, game.active_targets[i]), "Correct preview identity")
	var premature_before: int = game.responses.premature
	click(game, Vector2(10, 10))
	check(game.responses.premature == premature_before, "Drawing clicks ignored")
	game._on_frame_presented()
	check(game.phase == game.Phase.PREVIEW and game.deadline_us - Time.get_ticks_usec() > 2900000, "Three-second preview starts after rendering")
	click(game, Vector2(10, 10))
	check(not game.responses.active and game.responses.premature == premature_before, "Preview response recording disabled")
	game._advance(game.deadline_us)
	check(game.overlay.text == "3" and not game.preview_row.visible, "Countdown removes all previews")
	for number in [2, 1]:
		game._advance(game.deadline_us)
		check(game.overlay.text == str(number), "Countdown order")
		var saved_deadline: int = game.deadline_us
		game.deadline_us = 0
		click(game, Vector2(10, 10))
		check(game.responses.premature == premature_before, "Countdown clicks never count, even at deadline")
		game.deadline_us = saved_deadline
	game._advance(game.deadline_us)
	check(game.phase == game.Phase.GAP, "Countdown enters initial gap")

func test_flow(selected_mode: String) -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.history.path = test_path
	game.history.entries = []
	game.audio.muted = true
	game.rng.seed = 88
	await process_frame
	check(game.phase == game.Phase.MENU and game.start.visible, "Instruction screen")
	check(game.mode == "normal" and game.normal_button.button_pressed, "Default mode selection")
	if selected_mode == "advanced": game.advanced_button.pressed.emit()
	else: game.normal_button.pressed.emit()
	check(game.mode == selected_mode and game.mode_selector.visible, "Mode selector action")
	game._start_session()
	check(not game.mode_selector.visible and game.sequence.size() == 40, "Mode locked for 40-stimulus session")
	prepare_block(game, 0)
	game.deadline_us = Time.get_ticks_usec() + 1000000
	click(game, Vector2(10, 10))
	check(game.responses.premature == 1, "Whole-screen interval click")
	await process_frame
	click(game, game.mute.get_global_rect().get_center())
	click(game, game.abort_button.get_global_rect().get_center())
	check(game.responses.premature == 1, "UI clicks excluded")
	for i in game.sequence.size():
		game._advance(game.deadline_us)
		check(game.phase == game.Phase.DRAWING and not game.drawing_preview, "One queued test stimulus")
		check(game.figure.item == game.sequence[i] and not game.preview_row.visible, "Correct single presented stimulus")
		game._on_frame_presented()
		check(game.phase == game.Phase.STIMULUS, "Response window armed after rendering")
		if Targets.matches(game.sequence[i], game.active_targets):
			click(game, Vector2(10, 10))
			click(game, Vector2(15, 15))
		game._advance(game.deadline_us)
		check(game.responses.trials.size() == i + 1, "Exactly one record per stimulus")
		if (i + 1) % 10 == 0 and i < 39:
			check(not game.responses.active and game.cursor == i + 1, "Response window closed at block boundary")
			prepare_block(game, int((i + 1) / 10.0))
	check(game.phase == game.Phase.RESULTS and game.latest.total == 40, "Session completes after fourth block")
	check(game.latest.hits == 12 and game.latest.correct_rejections == 28 and game.latest.accuracy == 100.0, "Full-session scoring and duplicate suppression")
	check(game.latest.mode == selected_mode and game.history.entries.size() == 1, "Completed session saved once with mode")
	check(game.history.for_mode(selected_mode).size() == 1 and game.history.for_mode("legacy").is_empty(), "Separate mode history")
	var saved := History.new()
	saved.path = test_path
	saved.load_sessions()
	check(saved.for_mode(selected_mode).size() == 1, "Mode survives persistence")
	game._show_history()
	check(game.phase == game.Phase.HISTORY and game.history_mode == selected_mode and game.history_panel.get_child_count() == 1, "History opens in current mode")
	check(game.history_buttons.size() == 2 and game.history_buttons.has_all(["normal", "advanced"]), "Only Normal and Advanced history tabs")
	game._filter_history("legacy", false)
	check(game.history_mode == selected_mode, "Unsupported history filter cannot be displayed")
	game._back()
	game._start_session()
	check(game.responses.trials.is_empty() and game.responses.premature == 0 and game.mode == selected_mode, "Restart clears responses and keeps mode")
	game._notification(game.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.phase == game.Phase.MENU and game.history.entries.size() == 1, "Focus loss aborts without saving")
	game._start_session()
	game._abort()
	check(game.phase == game.Phase.MENU and not game.responses.active and not game.preview_row.visible, "Manual end clears previews")
	game.min_input.value = 5
	game.max_input.value = 1
	await process_frame
	game._start_session()
	check(game.phase == game.Phase.MENU and game.start.disabled, "Invalid intervals blocked")
	game.queue_free()
	await process_frame

func test_dynamic_generation() -> void:
	var rng := RandomNumberGenerator.new()
	var observed_targets := {}
	for selected_mode in Targets.MODES:
		var extra_target_positions := {}
		for seed_value in 200:
			rng.seed = seed_value
			var blocks := Stimuli.generate_session(selected_mode, rng)
			check(blocks.size() == 4, "Four blocks")
			var previous: Array = []
			var total := 0
			for block in blocks:
				var active: Array = block.targets
				check(active.size() == (2 if selected_mode == "advanced" else 1), "Target count matches mode")
				if selected_mode == "advanced": check(not Targets.same(active[0], active[1]), "Two distinct active targets")
				for target in active:
					check(not Targets.matches(target, previous), "No target repeated across neighboring blocks")
					observed_targets[Targets.describe(target)] = true
				check(block.stimuli.size() == 10, "Ten stimuli per block")
				var target_counts: Array[int] = []
				target_counts.resize(active.size())
				target_counts.fill(0)
				var run_length := 0
				for item in block.stimuli:
					check(item.gap >= 1 and item.gap <= 4, "Dynamic block gap bounds")
					check(item.shape in Targets.SHAPES and item.color in range(4), "Valid dynamic stimulus")
					if Targets.matches(item, active):
						run_length = 0
						for i in active.size():
							if Targets.same(item, active[i]): target_counts[i] += 1
					else:
						run_length += 1
						check(run_length <= 5, "Bounded dynamic distractor streak")
				var hits := 0
				for count in target_counts: hits += count
				check(hits == 3, "Three target presentations in each block")
				total += hits
				if selected_mode == "advanced":
					check(target_counts.min() == 1 and target_counts.max() == 2, "Both advanced targets appear, balanced 2/1")
					extra_target_positions[target_counts.find(2)] = true
				for target in active:
					var share_shape := false
					var share_color := false
					for item in block.stimuli:
						if Targets.matches(item, active): continue
						share_shape = share_shape or (item.shape == target.shape and item.color != target.color)
						share_color = share_color or (item.color == target.color and item.shape != target.shape)
					check(share_shape and share_color, "Safe near-target distractors for every active target")
				previous = active
			check(total == 12, "Twelve targets across complete session")
		if selected_mode == "advanced": check(extra_target_positions.size() == 2, "Extra advanced appearance not always assigned to same target")
		rng.seed = 2026
		var first := Stimuli.generate_session(selected_mode, rng, 2.0, 2.5)
		rng.seed = 2026
		check(first == Stimuli.generate_session(selected_mode, rng, 2.0, 2.5), "Dynamic schedules deterministic with seeded RNG")
		for block in first:
			for item in block.stimuli: check(item.gap >= 2.0 and item.gap <= 2.5, "Configured block gap bounds")
	check(observed_targets.size() == 20, "All shape/color target definitions possible")

func test_dynamic_responses() -> void:
	var active := [{"shape": "triangle", "color": 2}, {"shape": "circle", "color": 3}]
	var r := Responses.new()
	var now := 1000000
	for target in active:
		r.begin(target, now, 1.0, active)
		r.respond(now + 123456)
		r.respond(now + 500000)
		r.finish()
		now += 2000000
	r.begin({"shape": "square", "color": 0}, now, 1.0, active)
	r.respond(now + 200000)
	r.finish()
	var stats := Statistics.calculate(r.trials, 0)
	check(stats.hits == 2 and stats.false_alarms == 1, "Either active definition scores a hit; old blue square can be distractor")
	check(is_equal_approx(stats.mean_ms, 123.456), "Dynamic targets preserve exact reaction-time conversion")
	r.begin(active[0], now + 2000000, 1.0, [{"shape": "pentagon", "color": 1}])
	r.respond(now + 2200000)
	r.finish()
	check(not r.trials.back().target, "Old target becomes distractor when definitions change")

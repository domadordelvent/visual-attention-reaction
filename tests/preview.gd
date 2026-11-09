extends SceneTree
## Rendered integration check; run without --headless and with a display.
var failures := 0
var checks := 0
var game: Control
var selected_mode := "normal"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func capture(name_value: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/visual-attention-" + selected_mode + "-" + name_value + ".png")

func pointer(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await RenderingServer.frame_post_draw
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await RenderingServer.frame_post_draw
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await RenderingServer.frame_post_draw

func check_width() -> void:
	check(game.content.size.x <= game.scroll.size.x + 0.5, "Content fits width")
	check(game.scroll.get_h_scroll_bar().max_value <= game.scroll.size.x + 0.5, "No horizontal clipping")

func check_arena() -> void:
	check(game.arena.get_global_rect().end.y <= game.scroll.size.y, "Stimulus area fully visible at minimum size")
	check(game.arena.get_global_rect().position.y >= 0, "Stimulus area starts inside viewport")

func prepare_block(index: int) -> void:
	if index > 0:
		await RenderingServer.frame_post_draw
		await process_frame
		check(game.phase == game.Phase.TRANSITION, "Real renderer arms target-change announcement")
		check(game.figure.item.is_empty() and not game.preview_row.visible, "Announcement shows no figures")
		var before: int = game.responses.premature
		await pointer(Vector2(10, 10))
		check(game.responses.premature == before and not game.responses.active, "Actual transition click ignored")
		if index == 1:
			await capture("new-target")
			root.size = Vector2i(360, 480)
			await create_timer(0.1).timeout
			check_arena()
			check_width()
			check(game.overlay.text == ("NEW TARGETS" if selected_mode == "advanced" else "NEW TARGET"), "Announcement text fits smallest window")
			await capture("new-target-small")
			root.size = Vector2i(800, 900)
			await process_frame
		game._advance(game.deadline_us)
	await RenderingServer.frame_post_draw
	await process_frame
	check(game.phase == game.Phase.PREVIEW, "Real render signal arms block preview")
	check(game.current_block == index, "Correct rendered block index")
	check(game.preview_row.visible and game.figure.item.is_empty(), "Only target definitions visible during preview")
	if index == 0:
		await capture("target")
		root.size = Vector2i(360, 480)
		await create_timer(0.1).timeout
		check_arena()
		check_width()
		for i in game.active_targets.size():
			var bounds: Rect2 = game.target_previews[i].get_global_rect()
			check(bounds.size.x > 80 and bounds.size.y > 100, "Preview has meaningful display space")
		if selected_mode == "advanced":
			var first: Rect2 = game.target_previews[0].get_global_rect()
			var second: Rect2 = game.target_previews[1].get_global_rect()
			check(not first.intersects(second), "Advanced target previews do not overlap")
		await capture("target-small")
		root.size = Vector2i(800, 900)
		await process_frame
	# Skip preparation only after the renderer has armed the actual preview.
	game._advance(game.deadline_us)
	check(not game.preview_row.visible, "Countdown hides all targets")
	for i in 3: game._advance(game.deadline_us)
	check(game.phase == game.Phase.GAP, "Countdown enters blank interval")

func run_mode(value: String) -> void:
	selected_mode = value
	root.size = Vector2i(800, 900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.history.path = "/tmp/visual-attention-preview-%s-%d.json" % [value, OS.get_process_id()]
	game.history.entries = []
	game.audio.muted = true
	game.rng.seed = 431
	game.set_process(false)
	root.grab_focus()
	await create_timer(0.2).timeout
	var mode_button: Button = game.advanced_button if value == "advanced" else game.normal_button
	await pointer(mode_button.get_global_rect().get_center())
	check(game.mode == value and mode_button.button_pressed, "Actual mode selector GUI action")
	await capture("menu")
	await pointer(game.start.get_global_rect().get_center())
	check(not game.sequence.is_empty(), "Actual Start button begins session")
	if game.sequence.is_empty():
		game.queue_free()
		await process_frame
		return
	await prepare_block(0)
	for i in 40:
		game._advance(game.deadline_us)
		await RenderingServer.frame_post_draw
		await process_frame
		check(game.phase == game.Phase.STIMULUS and not game.preview_row.visible, "Renderer arms a single test stimulus")
		if i == 0:
			await capture("session")
			await pointer(game.mute.get_global_rect().get_center())
			check(not game.responses.answered and game.responses.premature == 0, "Actual GUI mute click excluded")
			check(not game.audio.muted, "Actual GUI mute action works")
			game.audio.muted = true
		if game.Stimuli.is_target(game.sequence[i], game.active_targets):
			await pointer(Vector2(10, 10))
			check(game.responses.answered, "Either target accepts actual viewport input outside arena")
			var rt: Variant = game.responses.current.rt_ms
			await pointer(Vector2(12, 12))
			check(game.responses.current.rt_ms == rt, "Duplicate input preserves first response time")
		if i == 0:
			root.size = Vector2i(360, 480)
			await create_timer(0.1).timeout
			check_arena()
			check_width()
			await capture("session-small")
			root.size = Vector2i(800, 900)
			await process_frame
		game._advance(game.deadline_us)
		if (i + 1) % 10 == 0 and i < 39: await prepare_block(int((i + 1) / 10.0))
	check(game.phase == game.Phase.RESULTS and game.latest.total == 40, "Rendered session completes")
	check(game.latest.mode == value and game.latest.hits == 12 and game.latest.accuracy == 100, "Rendered mode-specific scoring")
	await capture("results")
	game._show_history()
	check(game.history_mode == value, "History opens current mode only")
	await process_frame
	check(game.history_buttons.size() == 2 and game.history_buttons.has_all(["normal", "advanced"]), "Only two history tabs exist")
	var other := "advanced" if value == "normal" else "normal"
	await pointer(game.history_buttons[other].get_global_rect().get_center())
	check(game.history_mode == other and game.history.for_mode(other).is_empty(), "Actual history tab filters modes")
	await pointer(game.history_buttons[value].get_global_rect().get_center())
	check(game.history_mode == value and game.history_panel.get_child_count() == 1, "Actual mode history tab restores its results")
	await capture("history")
	for size_value in [Vector2i(360, 480), Vector2i(1280, 720), Vector2i(800, 900)]:
		root.size = size_value
		await create_timer(0.1).timeout
		check_width()
		await capture("history-size-%d-%d" % [size_value.x, size_value.y])
		game._back()
		await process_frame
		check_width()
		await capture("size-%d-%d" % [size_value.x, size_value.y])
		game._show_history()
	var path: String = game.history.path
	game.queue_free()
	await create_timer(0.15).timeout
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func run() -> void:
	await run_mode("normal")
	await run_mode("advanced")
	await check_diamond_rendering()
	print("Rendered integration and resize, both modes: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_diamond_rendering() -> void:
	# Measure actual rendered pixels at gameplay and two-target preview sizes.
	root.size = Vector2i(800, 900)
	var shape := Control.new()
	shape.set_script(load("res://figure.gd"))
	root.add_child(shape)
	shape.position = Vector2(24, 24)
	shape.display({"shape": "diamond", "color": 0})
	for dimensions in [Vector2(400, 400), Vector2(292, 240), Vector2(134, 210)]:
		shape.size = dimensions
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		var region := Rect2i(shape.get_global_rect())
		var left := region.end.x
		var right := region.position.x
		var top := region.end.y
		var bottom := region.position.y
		var filled := 0
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var pixel := frame.get_pixel(x, y)
				var blue := Color("438bfa")
				if absf(pixel.r - blue.r) + absf(pixel.g - blue.g) + absf(pixel.b - blue.b) < 0.02:
					left = mini(left, x)
					right = maxi(right, x)
					top = mini(top, y)
					bottom = maxi(bottom, y)
					filled += 1
		var width := right - left + 1
		var height := bottom - top + 1
		check(filled > 0 and absi(width - height) <= 1, "Rendered diamond has equal diagonals at %s" % dimensions)
		check(absf((left + right + 1) / 2.0 - shape.get_global_rect().get_center().x) <= 1.0 and absf((top + bottom + 1) / 2.0 - shape.get_global_rect().get_center().y) <= 1.0, "Diamond remains centered")
		check(left > region.position.x and right < region.end.x - 1 and top > region.position.y and bottom < region.end.y - 1, "Diamond fits comfortably inside available space")
		var coverage := float(filled) / maxi(width * height, 1)
		check(coverage > 0.47 and coverage < 0.53, "Diamond is a rotated square rather than an upright square or circle")
		frame.save_png("/tmp/visual-attention-diamond-%d-%d.png" % [int(dimensions.x), int(dimensions.y)])
	shape.queue_free()
	await process_frame

extends RefCounted
## Controlled stimulus schedules; target definitions live in targets.gd.
const Targets = preload("res://targets.gd")
const SESSION_COUNT := 40
const BLOCK_SIZE := 10
const BLUE := Color("438bfa")
const COLORS := [BLUE, Color("f2bc59"), Color("eb738c"), Color("67cba4")]
const SHAPES := Targets.SHAPES
const MAX_DISTRACTOR_RUN := 5

static func is_target(item: Dictionary, active: Array = Targets.LEGACY) -> bool:
	return Targets.matches(item, active)

static func generate(count: int, rng: RandomNumberGenerator, gap_min: float = 1.0, gap_max: float = 4.0, active: Array = Targets.LEGACY) -> Array[Dictionary]:
	count = clampi(count, 10, 200)
	gap_min = clampf(gap_min, 0.25, 10.0)
	gap_max = clampf(gap_max, gap_min, 10.0)
	var targets := roundi(count * 0.3)
	var flags: Array[bool] = []
	# Rejection sampling shuffles target positions within this schedule.
	# Bound the work, with a randomized capacity-constrained fallback.
	var accepted := false
	for attempt in 512:
		flags.clear()
		for i in count: flags.append(i < targets)
		for i in range(count - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var swap := flags[i]
			flags[i] = flags[j]
			flags[j] = swap
		var run := 0
		accepted = true
		for flag in flags:
			run = 0 if flag else run + 1
			if run > MAX_DISTRACTOR_RUN:
				accepted = false
				break
		if accepted: break
	if not accepted:
		var gaps: Array[int] = []
		gaps.resize(targets + 1)
		gaps.fill(0)
		for i in count - targets:
			var available: Array[int] = []
			for j in gaps.size():
				if gaps[j] < MAX_DISTRACTOR_RUN: available.append(j)
			gaps[available[rng.randi_range(0, available.size() - 1)]] += 1
		flags.clear()
		for i in gaps.size():
			for j in gaps[i]: flags.append(false)
			if i < targets: flags.append(true)
	var distractors: Array[Dictionary] = []
	for item in Targets.combinations():
		if not is_target(item, active): distractors.append(item)
	# Include both near-target categories for every active definition.
	var distractor_items: Array[Dictionary] = []
	for target in active:
		for share_shape in [true, false]:
			var candidates: Array[Dictionary] = []
			for item in distractors:
				var shares_feature: bool
				if share_shape: shares_feature = item.shape == target.shape and item.color != target.color
				else: shares_feature = item.color == target.color and item.shape != target.shape
				if shares_feature: candidates.append(item)
			distractor_items.append(candidates[rng.randi_range(0, candidates.size() - 1)].duplicate())
	while distractor_items.size() < count - targets:
		distractor_items.append(distractors[rng.randi_range(0, distractors.size() - 1)].duplicate())
	# Alternate definitions after a random starting target, so odd totals differ
	# by at most one and the extra appearance does not always favor the same one.
	var target_items: Array[Dictionary] = []
	var first := rng.randi_range(0, active.size() - 1)
	for i in targets: target_items.append(active[(first + i) % active.size()].duplicate())
	for i in range(target_items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := target_items[i]
		target_items[i] = target_items[j]
		target_items[j] = swap
	for i in range(distractor_items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := distractor_items[i]
		distractor_items[i] = distractor_items[j]
		distractor_items[j] = swap
	var result: Array[Dictionary] = []
	var cursor := 0
	var target_cursor := 0
	for flag in flags:
		var item: Dictionary
		if flag:
			item = target_items[target_cursor].duplicate()
			target_cursor += 1
		else:
			item = distractor_items[cursor].duplicate()
			cursor += 1
		item["gap"] = rng.randf_range(gap_min, gap_max)
		result.append(item)
	return result

static func generate_session(mode: String, rng: RandomNumberGenerator, gap_min: float = 1.0, gap_max: float = 4.0) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var previous: Array = []
	for index in int(SESSION_COUNT / BLOCK_SIZE):
		var active := Targets.generate(mode, previous, rng)
		blocks.append({"targets": active, "stimuli": generate(BLOCK_SIZE, rng, gap_min, gap_max, active)})
		previous = active
	return blocks

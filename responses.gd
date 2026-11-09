extends RefCounted
const Stimuli = preload("res://stimuli.gd")
var trials: Array[Dictionary] = []
var premature := 0
var onset_us := -1
var deadline_us := -1
var active := false
var answered := false
var current: Dictionary = {}

func begin(item: Dictionary, now_us: int, duration: float, active_targets: Array = Stimuli.Targets.LEGACY) -> void:
	current = {"target": Stimuli.is_target(item, active_targets), "responded": false, "rt_ms": null}
	onset_us = now_us
	deadline_us = now_us + roundi(duration * 1000000.0)
	active = true
	answered = false

func respond(now_us: int, in_gap: bool = false) -> void:
	if in_gap:
		premature += 1
	elif active and not answered and now_us >= onset_us and now_us < deadline_us:
		answered = true
		current.responded = true
		if current.target: current.rt_ms = (now_us - onset_us) / 1000.0

func finish() -> void:
	if not active: return
	trials.append(current.duplicate())
	active = false

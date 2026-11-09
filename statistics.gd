extends RefCounted

static func calculate(trials: Array, premature: int) -> Dictionary:
	var r := {"total": trials.size(), "targets": 0, "hits": 0, "omissions": 0,
		"false_alarms": 0, "correct_rejections": 0, "premature": premature,
		"mean_ms": null, "median_ms": null, "fastest_ms": null, "slowest_ms": null, "accuracy": 0.0}
	var times: Array[float] = []
	for trial in trials:
		if trial.target:
			r.targets += 1
			if trial.responded:
				r.hits += 1
				times.append(float(trial.rt_ms))
			else: r.omissions += 1
		elif trial.responded: r.false_alarms += 1
		else: r.correct_rejections += 1
	if not trials.is_empty(): r.accuracy = 100.0 * (r.hits + r.correct_rejections) / trials.size()
	if not times.is_empty():
		times.sort()
		var sum := 0.0
		for value in times: sum += value
		r.mean_ms = sum / times.size()
		var middle := int(times.size() / 2.0)
		r.median_ms = times[middle] if times.size() % 2 else (times[middle - 1] + times[middle]) / 2.0
		r.fastest_ms = times.front()
		r.slowest_ms = times.back()
	return r

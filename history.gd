extends RefCounted
var path := "user://sessions.json"
var entries: Array = []
var error := ""
const REQUIRED := ["date", "accuracy", "mean_ms", "median_ms", "fastest_ms", "slowest_ms",
	"omissions", "false_alarms", "premature", "total", "hits", "targets", "correct_rejections"]

func load_sessions() -> void:
	entries = []
	error = ""
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		error = "History could not be opened."
		return
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	var data: Variant = parser.data
	if parse_error != OK or not data is Array:
		error = "Saved history could not be read."
		return
	for entry in data:
		if not entry is Dictionary or not entry.has_all(REQUIRED):
			error = "Some saved history entries could not be read."
			continue
		var valid := entry.date is String
		for key in ["accuracy", "omissions", "false_alarms", "premature", "total", "hits", "targets", "correct_rejections"]:
			valid = valid and (entry[key] is int or entry[key] is float)
		for key in ["mean_ms", "median_ms", "fastest_ms", "slowest_ms"]:
			valid = valid and (entry[key] == null or entry[key] is int or entry[key] is float)
		if valid:
			# JSON uses floating point for all numbers; normalize counters.
			for key in ["omissions", "false_alarms", "premature", "total", "hits", "targets", "correct_rejections"]:
				entry[key] = int(entry[key])
			entry.accuracy = float(entry.accuracy)
			entries.append(entry)
		else: error = "Some saved history entries could not be read."
	entries = entries.slice(0, 10)

func record(result: Dictionary) -> bool:
	var entry := result.duplicate(true)
	entry["date"] = Time.get_datetime_string_from_system(false, true)
	entries.push_front(entry)
	entries = entries.slice(0, 10)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "Could not save history. This result remains available until you close the app."
		return false
	file.store_string(JSON.stringify(entries))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "Could not save history. This result remains available until you close the app."
		return false
	error = ""
	return true

static func mode_of(entry: Dictionary) -> String:
	# Unsupported records stay in storage but are not exposed in the history UI.
	var mode: Variant = entry.get("mode", "")
	return mode if mode is String and mode in ["normal", "advanced"] else ""

func for_mode(mode: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if mode not in ["normal", "advanced"]: return result
	for entry in entries:
		if mode_of(entry) == mode: result.append(entry)
	return result

extends AudioStreamPlayer
## Cached UI cues only; stimulus presentation and responses never call this node.
signal sound_started(kind: String)
const SAMPLE_RATE := 44100
const VOLUME_DB := -6.0
var muted := false
var sounds: Dictionary = {}

func _ready() -> void:
	bus = &"UI" if AudioServer.get_bus_index("UI") >= 0 else &"Master"
	volume_db = VOLUME_DB
	pitch_scale = 1.0
	max_polyphony = 1
	autoplay = false
	stream_paused = false
	sounds = {
		"click": _make_sound([640.0], 0.08),
		"start": _make_sound([520.0, 780.0], 0.11),
		"complete": _make_sound([659.25, 830.61, 987.77], 0.10),
	}

func _make_sound(notes: Array[float], note_seconds: float) -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = SAMPLE_RATE
	sound.stereo = false
	sound.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var count := roundi(notes.size() * note_seconds * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / SAMPLE_RATE
		var note := mini(int(t / note_seconds), notes.size() - 1)
		var local_time := t - note * note_seconds
		var envelope := minf(local_time / 0.006, 1.0) * clampf((note_seconds - local_time) / 0.025, 0.0, 1.0)
		var phase := TAU * notes[note] * local_time
		var wave := (sin(phase) + 0.06 * sin(phase * 2.0)) / 1.06
		data.encode_s16(i * 2, int(wave * envelope * 0.65 * 32767.0))
	sound.data = data
	return sound

func _play_cue(kind: String) -> void:
	if muted: return
	if playing and kind == "click" and stream == sounds[kind]: return
	stop()
	stream = sounds[kind]
	play()
	sound_started.emit(kind)

func click() -> void:
	_play_cue("click")

func start_session() -> void:
	_play_cue("start")

func complete_session() -> void:
	_play_cue("complete")

func toggle() -> void:
	muted = not muted
	if muted: stop()

func _exit_tree() -> void:
	stop()
	stream = null
	sounds.clear()

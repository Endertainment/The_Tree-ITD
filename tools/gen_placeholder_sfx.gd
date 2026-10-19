extends SceneTree
## Generates the placeholder audio bed for The Tree.
##
## Every file is synthesized from scratch (sine/saw/square/noise plus envelopes),
## so the repository carries no third-party samples and no download step is
## needed. Output is 44.1 kHz, mono, 16-bit PCM, peak-normalized.
##
## Run:
##   godot --headless --path . --script res://tools/gen_placeholder_sfx.gd
##
## The files land in `res://assets/audio/sfx/` and `res://assets/audio/music/`.
## Re-running overwrites them; the generator is deterministic (fixed RNG seed),
## so a regenerated file is byte-identical on the same engine version.

const RATE := 44100
const SFX_DIR := "res://assets/audio/sfx"
const MUSIC_DIR := "res://assets/audio/music"
const RNG_SEED := 20261020
const SFX_PEAK := 0.9
const MUSIC_PEAK := 0.55
const MUSIC_SECONDS := 30.0
const EDGE_FADE := 0.004

var _rng := RandomNumberGenerator.new()
var _written := 0


func _initialize() -> void:
	_rng.seed = RNG_SEED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SFX_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MUSIC_DIR))

	# --- UI bus -----------------------------------------------------------
	_write_sfx("ui_tap", _tone(0.08, 1150.0, 820.0, "sine", 0.6, 30.0))
	_write_sfx("ui_confirm", _arpeggio(PackedFloat32Array([660.0, 990.0]), 0.07, 0.5, 18.0))
	_write_sfx("error", _tone(0.20, 220.0, 208.0, "square", 0.35, 10.0))

	# --- SFX bus ----------------------------------------------------------
	_write_sfx("build", _mix(
		_tone(0.35, 150.0, 90.0, "sine", 0.7, 9.0),
		_tone(0.18, 400.0, 200.0, "sine", 0.0, 18.0, 0.55),
		1.0
	))
	_write_sfx("upgrade", _arpeggio(
		PackedFloat32Array([523.25, 659.25, 783.99]), 0.12, 0.5, 7.0
	))
	_write_sfx("arrow", _tone(0.15, 900.0, 1600.0, "sine", 0.25, 14.0, 0.5))
	_write_sfx("hit", _tone(0.10, 240.0, 120.0, "sine", 0.55, 22.0, 0.45))
	_write_sfx("enemy_die", _tone(0.30, 420.0, 110.0, "tri", 0.5, 7.0, 0.2))
	_write_sfx("boss_roar", _mix(
		_tone(0.60, 78.0, 62.0, "saw", 0.6, 1.6, 0.22, 0.12, 9.0),
		_tone(0.60, 118.0, 96.0, "sine", 0.4, 2.2, 0.15),
		0.5
	))
	_write_sfx("victory", _arpeggio(
		PackedFloat32Array([523.25, 659.25, 783.99, 1046.5]), 0.11, 0.5, 5.0
	))
	_write_sfx("defeat", _arpeggio(
		PackedFloat32Array([392.0, 329.63, 261.63, 196.0]), 0.12, 0.5, 4.0
	))
	_write_sfx("coin", _arpeggio(
		PackedFloat32Array([1318.5, 1760.0]), 0.05, 0.45, 22.0
	))

	# --- Music bus --------------------------------------------------------
	_write_wav(MUSIC_DIR + "/grove_loop.wav", _grove_loop(), true, MUSIC_PEAK)

	print("[gen_sfx] wrote %d files" % _written)
	quit(0)


# ---------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------

## Renders a single swept oscillator with an attack/decay envelope.
## `wobble` modulates pitch (fraction), `wobble_rate` is in Hz.
func _tone(
	duration: float,
	f0: float,
	f1: float,
	wave: String,
	amp: float,
	decay: float,
	noise := 0.0,
	wobble := 0.0,
	wobble_rate := 0.0
) -> PackedFloat32Array:
	var count := _frames(duration)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	var attack := 0.004
	for index in count:
		var t := float(index) / RATE
		var freq := lerpf(f0, f1, t / duration)
		if wobble > 0.0:
			freq *= 1.0 + wobble * sin(TAU * wobble_rate * t)
		phase += TAU * freq / RATE
		var sample := _wave_value(wave, phase) * amp
		if noise > 0.0:
			sample += noise * _rng.randf_range(-1.0, 1.0)
		out[index] = sample * _envelope(t, attack, decay)
	return out


## Renders `notes` as equal-length segments with a per-note decay.
func _arpeggio(notes: PackedFloat32Array, segment: float, amp: float, decay: float) -> PackedFloat32Array:
	if notes.is_empty():
		return PackedFloat32Array()
	var count := _frames(segment * float(notes.size()))
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for index in count:
		var t := float(index) / RATE
		var note_index := mini(int(t / segment), notes.size() - 1)
		var local := t - float(note_index) * segment
		phase += TAU * notes[note_index] / RATE
		var env := minf(1.0, local / 0.006) * exp(-decay * local)
		out[index] = sin(phase) * amp * env
	return out


## Adds `b` into `a` at `gain`, extending `a` when `b` is longer.
func _mix(a: PackedFloat32Array, b: PackedFloat32Array, gain: float) -> PackedFloat32Array:
	if b.size() > a.size():
		var grown := a.duplicate()
		grown.resize(b.size())
		a = grown
	for index in b.size():
		a[index] += b[index] * gain
	return a


## 30 s ambient pad loop: Am - F - C - G, 7.5 s per chord.
func _grove_loop() -> PackedFloat32Array:
	var chords := [
		[220.00, 261.63, 329.63],
		[174.61, 220.00, 261.63],
		[261.63, 329.63, 392.00],
		[196.00, 246.94, 293.66],
	]
	var chord_seconds := MUSIC_SECONDS / float(chords.size())
	var count := _frames(MUSIC_SECONDS)
	var out := PackedFloat32Array()
	out.resize(count)
	for index in count:
		var t := float(index) / RATE
		var chord_index := mini(int(t / chord_seconds), chords.size() - 1)
		var local := t - float(chord_index) * chord_seconds
		var swell := _swell(local, chord_seconds)
		var sample := 0.0
		var chord: Array = chords[chord_index]
		for voice_index in chord.size():
			var freq: float = chord[voice_index]
			# Detuned pair per voice gives a slow, wide chorus.
			sample += sin(TAU * freq * t) * 0.30
			sample += sin(TAU * freq * 1.003 * t + 0.7) * 0.22
		# A quiet bell arpeggio on top, one note per beat-ish.
		var bell_step := int(local / 1.25)
		if bell_step < 6:
			var bell_freq: float = chord[bell_step % chord.size()] * 2.0
			var bell_t := local - float(bell_step) * 1.25
			sample += sin(TAU * bell_freq * bell_t) * 0.10 * exp(-3.5 * bell_t)
		var breath := 0.85 + 0.15 * sin(TAU * 0.08 * t)
		out[index] = sample * swell * breath * 0.25
	return out


func _swell(local: float, length: float) -> float:
	var attack := 1.8
	var release := 1.8
	var fade_in := minf(1.0, local / attack)
	var fade_out := minf(1.0, (length - local) / release)
	return ease(minf(fade_in, fade_out), 0.5)


func _wave_value(wave: String, phase: float) -> float:
	match wave:
		"square":
			return 1.0 if sin(phase) >= 0.0 else -1.0
		"saw":
			return fposmod(phase / TAU, 1.0) * 2.0 - 1.0
		"tri":
			return asin(sin(phase)) * (2.0 / PI)
		_:
			return sin(phase)


func _envelope(t: float, attack: float, decay: float) -> float:
	return minf(1.0, t / attack) * exp(-decay * t)


func _frames(duration: float) -> int:
	return maxi(2, int(round(duration * RATE)))


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

func _write_sfx(id: String, samples: PackedFloat32Array) -> void:
	_write_wav(SFX_DIR + "/" + id + ".wav", samples, false, SFX_PEAK)


## Peak-normalizes, converts to 16-bit PCM and saves a WAV.
func _write_wav(path: String, samples: PackedFloat32Array, loop: bool, peak: float) -> void:
	if samples.is_empty():
		push_error("[gen_sfx] no samples for %s" % path)
		return
	var loudest := 0.0
	for value in samples:
		loudest = maxf(loudest, absf(value))
	var gain := 0.0 if loudest <= 0.0001 else peak / loudest
	var count := samples.size()
	var data := PackedByteArray()
	data.resize(count * 2)
	var edge := maxi(1, mini(count / 2, int(EDGE_FADE * RATE)))
	for index in count:
		var value := samples[index] * gain
		# Taper both ends so playback and looping never click.
		if index < edge:
			value *= float(index) / float(edge)
		elif index >= count - edge:
			value *= float(count - 1 - index) / float(edge)
		data.encode_s16(index * 2, int(round(clampf(value, -1.0, 1.0) * 32767.0)))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	var err := stream.save_to_wav(path)
	if err != OK:
		push_error("[gen_sfx] save failed (%d): %s" % [err, path])
		return
	_written += 1
	print("[gen_sfx] %-22s %5.2fs  %6d bytes" % [path.get_file(), float(count) / RATE, count * 2])

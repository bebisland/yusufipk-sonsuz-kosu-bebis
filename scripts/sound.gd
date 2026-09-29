extends Node
## Autoload: looping background music plus sound effects synthesized at startup.
## Lives outside the main scene so the music keeps playing across restarts.

const MUSIC_PATH := "res://assets/audio/music_loop.ogg"
const MIX_RATE := 44100

var music: AudioStreamPlayer
var sfx_players := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music = AudioStreamPlayer.new()
	music.volume_db = -12.0
	add_child(music)
	if ResourceLoader.exists(MUSIC_PATH):
		var stream: AudioStream = load(MUSIC_PATH)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		music.stream = stream
		music.play()
	else:
		push_warning("Missing music, playing without it: %s" % MUSIC_PATH)

	_add_sfx("jump", _make_jump(), -6.0)
	_add_sfx("crystal", _make_crystal(), -8.0)
	_add_sfx("crash", _make_crash(), -2.0)


func play(sfx_name: String) -> void:
	var player: AudioStreamPlayer = sfx_players.get(sfx_name)
	if player:
		player.play()


func _add_sfx(sfx_name: String, stream: AudioStreamWAV, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	# Several crystals can be picked up in quick succession.
	player.max_polyphony = 4
	add_child(player)
	sfx_players[sfx_name] = player


# --- Synthesis ---------------------------------------------------------------

## Rising square-ish chirp.
func _make_jump() -> AudioStreamWAV:
	var length := 0.2
	var samples := PackedFloat32Array()
	var phase := 0.0
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		var k := t / length
		var freq := lerpf(260.0, 720.0, sqrt(k))
		phase += freq / MIX_RATE
		var tone := sin(TAU * phase) + 0.3 * signf(sin(TAU * phase))
		var env := minf(t / 0.01, 1.0) * pow(1.0 - k, 1.5)
		samples.append(tone * env * 0.45)
	return _to_wav(samples)


## Two bright bell notes (E6 then B6) with a soft overtone.
func _make_crystal() -> AudioStreamWAV:
	var length := 0.35
	var notes := [[1318.5, 0.0], [1975.5, 0.07]]
	var samples := PackedFloat32Array()
	samples.resize(int(length * MIX_RATE))
	for note in notes:
		var freq: float = note[0]
		var start: int = int(note[1] * MIX_RATE)
		for i in range(start, samples.size()):
			var t := float(i - start) / MIX_RATE
			var env := minf(t / 0.004, 1.0) * exp(-t * 14.0)
			var tone := sin(TAU * freq * t) + 0.35 * sin(TAU * freq * 2.76 * t)
			samples[i] += tone * env * 0.3
	return _to_wav(samples)


## Low thud with a falling pitch plus a burst of filtered noise.
func _make_crash() -> AudioStreamWAV:
	var length := 0.6
	var samples := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phase := 0.0
	var noise := 0.0
	for i in int(length * MIX_RATE):
		var t := float(i) / MIX_RATE
		var freq := lerpf(140.0, 45.0, minf(t / 0.3, 1.0))
		phase += freq / MIX_RATE
		var thud := sin(TAU * phase) * exp(-t * 6.0)
		# One-pole low-pass keeps the noise rumbly rather than hissy.
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.18)
		var crunch := noise * exp(-t * 9.0) * 1.6
		samples.append((thud * 0.7 + crunch * 0.5) * minf(t / 0.003, 1.0))
	return _to_wav(samples)


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav

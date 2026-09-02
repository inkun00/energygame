extends Node

## AudioManager: 프로시저럴 사운드 효과(SFX) 및 BGM 관리 매니저

signal special_skill_sfx_played(skill_id)

const SPECIAL_SKILL_SFX_IDS: Array[String] = [
	"eco_dash", "wind_path", "lightning_leap", "solar_charge", "starlight_charge",
	"purifying_wave", "earth_barrier", "forest_supply", "recycle_salvage", "mycelium_harvest"
]

var sfx_player: AudioStreamPlayer
var bgm_player: AudioStreamPlayer

func _ready() -> void:
	sfx_player = AudioStreamPlayer.new()
	bgm_player = AudioStreamPlayer.new()
	add_child(sfx_player)
	add_child(bgm_player)

# 신디사이저 톤 생성 (주사위 굴림, 정답 팡파레, 오답 삑, 사다리 상승음 등)
func play_tone(freq: float, duration: float = 0.15, type: String = "sine", gain: float = 0.4) -> void:
	var sample_rate: int = 22050
	var total_frames: int = int(sample_rate * duration)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = duration + 0.05
	
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = generator
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if playback:
		for i in range(total_frames):
			var t: float = float(i) / sample_rate
			var sample: float = 0.0
			if type == "square":
				sample = gain * 0.75 if sin(2.0 * PI * freq * t) > 0 else -gain * 0.75
			elif type == "saw":
				sample = gain * 0.75 * (2.0 * fmod(t * freq, 1.0) - 1.0)
			else: # sine
				sample = gain * sin(2.0 * PI * freq * t)
			# 시작 클릭음을 줄이는 짧은 어택과 자연스러운 페이드아웃입니다.
			var attack := minf(1.0, float(i) / maxf(float(sample_rate) * 0.012, 1.0))
			var env := attack * (1.0 - float(i) / float(total_frames))
			sample *= env
			playback.push_frame(Vector2(sample, sample))
			
	# 자동 소멸 타이머
	get_tree().create_timer(duration + 0.1).timeout.connect(player.queue_free)

func play_sweep(start_freq: float, end_freq: float, duration: float, type: String = "sine", gain: float = 0.3) -> void:
	var sample_rate := 22050
	var total_frames := int(sample_rate * duration)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = duration + 0.05
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = generator
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var phase := 0.0
	if playback:
		for i in range(total_frames):
			var progress := float(i) / maxf(float(total_frames - 1), 1.0)
			var frequency := lerpf(start_freq, end_freq, progress)
			phase += TAU * frequency / float(sample_rate)
			var wave := sin(phase)
			if type == "square":
				wave = 0.75 if wave >= 0.0 else -0.75
			elif type == "saw":
				wave = 0.75 * (2.0 * fmod(phase / TAU, 1.0) - 1.0)
			var attack := minf(1.0, float(i) / maxf(float(sample_rate) * 0.015, 1.0))
			var release := pow(1.0 - progress, 0.7)
			var sample := wave * gain * attack * release
			playback.push_frame(Vector2(sample, sample))
	get_tree().create_timer(duration + 0.1).timeout.connect(player.queue_free)

func _queue_tone(delay: float, frequency: float, duration: float, wave_type: String = "sine", gain: float = 0.3) -> void:
	if delay <= 0.0:
		play_tone(frequency, duration, wave_type, gain)
	else:
		get_tree().create_timer(delay).timeout.connect(play_tone.bind(frequency, duration, wave_type, gain))

func _queue_sweep(delay: float, start_frequency: float, end_frequency: float, duration: float, wave_type: String = "sine", gain: float = 0.3) -> void:
	if delay <= 0.0:
		play_sweep(start_frequency, end_frequency, duration, wave_type, gain)
	else:
		get_tree().create_timer(delay).timeout.connect(play_sweep.bind(start_frequency, end_frequency, duration, wave_type, gain))

## 화면 특수효과의 움직임과 맞춘 캐릭터별 고유 효과음입니다.
func play_special_skill_sfx(skill_id: String) -> void:
	special_skill_sfx_played.emit(skill_id)
	match skill_id:
		"eco_dash":
			_queue_sweep(0.0, 240.0, 620.0, 0.34, "sine", 0.28)
			_queue_tone(0.24, 659.25, 0.16, "sine", 0.25)
			_queue_tone(0.38, 880.0, 0.22, "sine", 0.22)
		"wind_path":
			_queue_sweep(0.0, 920.0, 260.0, 0.46, "sine", 0.22)
			_queue_sweep(0.16, 380.0, 1050.0, 0.42, "sine", 0.19)
			_queue_tone(0.46, 740.0, 0.18, "sine", 0.18)
		"lightning_leap":
			_queue_tone(0.0, 1280.0, 0.055, "square", 0.34)
			_queue_tone(0.07, 820.0, 0.07, "square", 0.30)
			_queue_tone(0.15, 1640.0, 0.05, "square", 0.28)
			_queue_sweep(0.18, 260.0, 90.0, 0.30, "saw", 0.25)
		"solar_charge":
			_queue_sweep(0.0, 330.0, 660.0, 0.42, "sine", 0.24)
			_queue_tone(0.22, 523.25, 0.42, "sine", 0.20)
			_queue_tone(0.25, 659.25, 0.40, "sine", 0.18)
			_queue_tone(0.28, 783.99, 0.38, "sine", 0.17)
		"starlight_charge":
			_queue_tone(0.0, 880.0, 0.13, "sine", 0.20)
			_queue_tone(0.12, 1174.66, 0.15, "sine", 0.22)
			_queue_tone(0.25, 1318.51, 0.17, "sine", 0.20)
			_queue_tone(0.40, 1760.0, 0.25, "sine", 0.18)
		"purifying_wave":
			_queue_sweep(0.0, 260.0, 720.0, 0.55, "sine", 0.25)
			_queue_tone(0.18, 920.0, 0.10, "sine", 0.17)
			_queue_tone(0.31, 1120.0, 0.09, "sine", 0.15)
			_queue_tone(0.44, 1380.0, 0.12, "sine", 0.14)
		"earth_barrier":
			_queue_sweep(0.0, 150.0, 72.0, 0.30, "saw", 0.34)
			_queue_tone(0.14, 110.0, 0.24, "square", 0.25)
			_queue_tone(0.31, 196.0, 0.34, "sine", 0.24)
		"forest_supply":
			_queue_tone(0.0, 329.63, 0.18, "sine", 0.20)
			_queue_tone(0.13, 440.0, 0.18, "sine", 0.20)
			_queue_tone(0.26, 523.25, 0.20, "sine", 0.22)
			_queue_tone(0.41, 659.25, 0.26, "sine", 0.20)
		"recycle_salvage":
			_queue_tone(0.0, 420.0, 0.12, "square", 0.18)
			_queue_tone(0.12, 560.0, 0.12, "square", 0.18)
			_queue_tone(0.24, 700.0, 0.12, "square", 0.18)
			_queue_tone(0.38, 420.0, 0.24, "sine", 0.24)
		"mycelium_harvest":
			_queue_sweep(0.0, 190.0, 460.0, 0.48, "sine", 0.24)
			_queue_tone(0.22, 493.88, 0.22, "sine", 0.18)
			_queue_tone(0.42, 739.99, 0.28, "sine", 0.19)
		_:
			_queue_sweep(0.0, 300.0, 720.0, 0.42, "sine", 0.25)

func play_dice_sfx() -> void:
	play_tone(520.0, 0.08, "square")
	get_tree().create_timer(0.08).timeout.connect(func(): play_tone(660.0, 0.08, "square"))

func play_move_sfx() -> void:
	play_tone(440.0, 0.06, "sine")

func play_correct_sfx() -> void:
	play_tone(523.25, 0.1, "sine") # C5
	get_tree().create_timer(0.1).timeout.connect(func(): play_tone(659.25, 0.1, "sine")) # E5
	get_tree().create_timer(0.2).timeout.connect(func(): play_tone(783.99, 0.25, "sine")) # G5

func play_wrong_sfx() -> void:
	play_tone(220.0, 0.2, "saw")
	get_tree().create_timer(0.15).timeout.connect(func(): play_tone(180.0, 0.3, "saw"))

func play_ladder_sfx() -> void:
	for i in range(5):
		get_tree().create_timer(i * 0.06).timeout.connect(func(): play_tone(400.0 + i * 120.0, 0.08, "sine"))

func play_slide_sfx() -> void:
	for i in range(5):
		get_tree().create_timer(i * 0.06).timeout.connect(func(): play_tone(700.0 - i * 100.0, 0.08, "saw"))

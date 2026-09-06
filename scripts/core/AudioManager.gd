extends Node

## Effects are baked at development time and bundled in the initial game pack.
## Web playback uses Web Audio samples; no synthesis, HTTP requests, or note timers.
signal special_skill_sfx_played(skill_id)

const SPECIAL_SKILL_SFX_IDS: Array[String] = ["eco_dash", "wind_path", "lightning_leap", "solar_charge", "starlight_charge", "purifying_wave", "earth_barrier", "forest_supply", "recycle_salvage", "mycelium_harvest"]
const MAX_VOICES := 12
const CLIPS := {
	"eco_dash": preload("res://assets/audio/sfx/eco_dash.wav"),
	"wind_path": preload("res://assets/audio/sfx/wind_path.wav"),
	"lightning_leap": preload("res://assets/audio/sfx/lightning_leap.wav"),
	"solar_charge": preload("res://assets/audio/sfx/solar_charge.wav"),
	"starlight_charge": preload("res://assets/audio/sfx/starlight_charge.wav"),
	"purifying_wave": preload("res://assets/audio/sfx/purifying_wave.wav"),
	"earth_barrier": preload("res://assets/audio/sfx/earth_barrier.wav"),
	"forest_supply": preload("res://assets/audio/sfx/forest_supply.wav"),
	"recycle_salvage": preload("res://assets/audio/sfx/recycle_salvage.wav"),
	"mycelium_harvest": preload("res://assets/audio/sfx/mycelium_harvest.wav"),
	"skill_default": preload("res://assets/audio/sfx/skill_default.wav"),
	"dice": preload("res://assets/audio/sfx/dice.wav"),
	"move": preload("res://assets/audio/sfx/move.wav"),
	"correct": preload("res://assets/audio/sfx/correct.wav"),
	"wrong": preload("res://assets/audio/sfx/wrong.wav"),
	"ladder": preload("res://assets/audio/sfx/ladder.wav"),
	"slide": preload("res://assets/audio/sfx/slide.wav"),
}

var voices: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for index in range(MAX_VOICES):
		var player := AudioStreamPlayer.new()
		player.name = "EffectVoice%02d" % index
		# Browser sample playback continues independently of game-frame timing.
		player.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE if OS.has_feature("web") else AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		voices.append(player)

func _play_clip(effect_id: String) -> void:
	var clip: AudioStream = CLIPS.get(effect_id)
	if clip == null:
		return
	for player in voices:
		if not player.playing:
			player.stream = clip
			player.play()
			return
	# Bound exceptional event bursts without cutting off an effect already playing.

func play_special_skill_sfx(skill_id: String) -> void:
	special_skill_sfx_played.emit(skill_id)
	_play_clip(skill_id if skill_id in SPECIAL_SKILL_SFX_IDS else "skill_default")

func play_dice_sfx() -> void:
	_play_clip("dice")

func play_move_sfx() -> void:
	_play_clip("move")

func play_correct_sfx() -> void:
	_play_clip("correct")

func play_wrong_sfx() -> void:
	_play_clip("wrong")

func play_ladder_sfx() -> void:
	_play_clip("ladder")

func play_slide_sfx() -> void:
	_play_clip("slide")

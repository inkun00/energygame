extends Control
class_name BossUIController

## BossUIController: 중간보스/최종보스 레이드 팝업 모달 인터랙션 제어

signal boss_material_decided(player_idx, item_id)

const UI = preload("res://scripts/ui/CommercialUI.gd")

@onready var boss_image: TextureRect = $Panel/BossImage
@onready var boss_name_label: Label = $Panel/BossNameLabel
@onready var hp_bar: ProgressBar = $Panel/HPBar
@onready var hp_label: Label = $Panel/HPLabel
@onready var weakness_label: Label = $Panel/WeaknessLabel
@onready var attack_buttons_container: HBoxContainer = $Panel/AttackButtonsContainer

var current_player_idx: int = 0
var boss_ref: BossRaidController

func _ready() -> void:
	_apply_commercial_ui()
	visible = false

func display_boss_battle(p_idx: int, b_controller: BossRaidController) -> void:
	current_player_idx = p_idx
	boss_ref = b_controller
	visible = true
	
	boss_name_label.text = "보스 레이드 · " + b_controller.boss_name
	weakness_label.text = b_controller.weakness_desc
	hp_bar.max_value = b_controller.max_hp
	hp_bar.value = b_controller.current_hp
	hp_label.text = "HP: %d / %d" % [b_controller.current_hp, b_controller.max_hp]
	
	if ResourceLoader.exists(b_controller.boss_sprite_path):
		boss_image.texture = load(b_controller.boss_sprite_path)
		
	_rebuild_material_buttons()
	var battle_panel := get_node_or_null("Panel") as Panel
	if battle_panel:
		battle_panel.modulate = Color(1, 1, 1, 0)
		battle_panel.scale = Vector2(0.94, 0.94)
		battle_panel.pivot_offset = battle_panel.size * 0.5
		var tween := create_tween().set_parallel(true)
		tween.tween_property(battle_panel, "modulate", Color.WHITE, 0.18)
		tween.tween_property(battle_panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _rebuild_material_buttons() -> void:
	# 카드 대신 현재 플레이어가 모은 핵심 건설재료를 보스 퇴치에 사용합니다.
	for child in attack_buttons_container.get_children():
		attack_buttons_container.remove_child(child)
		child.queue_free()
	if not GameManager or current_player_idx < 0 or current_player_idx >= GameManager.players.size():
		return
	var is_ai: bool = GameManager.players[current_player_idx].get("is_ai", false)
	var inventory: Dictionary = GameManager.players[current_player_idx].get("inventory", {})
	var usable_materials: Array[String] = []
	for item_id in ["solar_panel", "wind_blade", "battery", "smart_grid"]:
		if int(inventory.get(item_id, 0)) > 0:
			usable_materials.append(item_id)
	for item_id in usable_materials:
		var item: Dictionary = GameManager.ITEM_DEFINITIONS[item_id]
		var btn := Button.new()
		btn.text = "%s 1개 사용\n60 피해" % item.get("name", "건설재료")
		btn.tooltip_text = "모은 건설재료 1개를 사용해 보스를 퇴치합니다."
		btn.custom_minimum_size = Vector2(170, 52)
		btn.add_theme_font_size_override("font_size", 18)
		UI.apply_secondary_button(btn, UI.TEAL)
		btn.disabled = is_ai
		btn.pressed.connect(_on_material_chosen.bind(item_id))
		attack_buttons_container.add_child(btn)

	var give_up_button := Button.new()
	give_up_button.text = ("재료 없음\n시작 칸으로" if usable_materials.is_empty() else "퇴치 포기\n시작 칸으로")
	give_up_button.tooltip_text = "보스를 퇴치하지 못하면 현재 플레이어가 0번 시작 칸으로 돌아갑니다."
	give_up_button.custom_minimum_size = Vector2(150, 52)
	give_up_button.add_theme_font_size_override("font_size", 17)
	UI.apply_secondary_button(give_up_button, UI.DANGER)
	give_up_button.disabled = is_ai
	give_up_button.pressed.connect(_on_give_up_chosen)
	attack_buttons_container.add_child(give_up_button)

func update_boss_status(b_controller: BossRaidController) -> void:
	boss_ref = b_controller
	hp_bar.value = b_controller.current_hp
	hp_label.text = "HP: %d / %d" % [b_controller.current_hp, b_controller.max_hp]
	_rebuild_material_buttons()

func close_boss_battle() -> void:
	visible = false
	boss_ref = null

func _on_material_chosen(item_id: String) -> void:
	if not GameManager or not boss_ref or current_player_idx < 0 or current_player_idx >= GameManager.players.size():
		return
	var inventory: Dictionary = GameManager.players[current_player_idx].get("inventory", {})
	if int(inventory.get(item_id, 0)) <= 0:
		_rebuild_material_buttons()
		return
	inventory[item_id] = int(inventory[item_id]) - 1
	GameManager.player_inventory_changed.emit(current_player_idx, inventory.duplicate(true))
	boss_material_decided.emit(current_player_idx, item_id)
	var defeated := boss_ref.apply_damage(60)
	GameManager.status_message_posted.emit("%s을(를) 사용해 보스에게 60 피해를 주었습니다!" % GameManager.ITEM_DEFINITIONS[item_id]["name"])
	if defeated:
		GameManager.status_message_posted.emit("보스 퇴치 성공! 건설재료의 힘으로 마을을 지켰습니다.")
		close_boss_battle()
	else:
		update_boss_status(boss_ref)

func _on_give_up_chosen() -> void:
	if not GameManager or current_player_idx < 0 or current_player_idx >= GameManager.players.size():
		return
	var from_tile := int(GameManager.players[current_player_idx].get("position", 0))
	GameManager.players[current_player_idx]["position"] = 0
	GameManager.player_moved.emit(current_player_idx, from_tile, 0)
	GameManager.status_message_posted.emit("보스를 퇴치하지 못해 0번 시작 칸으로 돌아갑니다.")
	close_boss_battle()
	GameManager.end_turn()


func _apply_commercial_ui() -> void:
	var dimmer := get_node_or_null("Dimmer") as ColorRect
	if dimmer:
		dimmer.color = Color(0.004, 0.012, 0.018, 0.86)
	var battle_panel := get_node_or_null("Panel") as Panel
	if battle_panel:
		battle_panel.add_theme_stylebox_override("panel", UI.padded_panel(Color("15262f"), UI.DANGER.darkened(0.15), 18.0, 18))
	if boss_name_label:
		boss_name_label.add_theme_color_override("font_color", Color("ff9292"))
	if hp_bar:
		hp_bar.add_theme_stylebox_override("background", UI.progress_background())
		hp_bar.add_theme_stylebox_override("fill", UI.progress_fill(UI.DANGER))
	if weakness_label:
		weakness_label.add_theme_color_override("font_color", UI.GOLD)

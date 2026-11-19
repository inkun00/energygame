extends RefCounted

const UI = preload("res://scripts/ui/CommercialUI.gd")

var lobby: Control
var scroll := ScrollContainer.new()
var title := Label.new()
var portrait := TextureRect.new()
var role_label := Label.new()
var hero_details := VBoxContainer.new()
var form := PanelContainer.new()
var story_backdrop := TextureRect.new()
var content: VBoxContainer
var desktop_controls: Dictionary = {}
var desktop_visibility: Dictionary = {}
var desktop_story_offsets: Dictionary = {}
var desktop_content_rect: Rect2
var desktop_action_offsets: Vector4
var active := false

func setup(view: Control) -> void:
	lobby = view
	content = lobby.menu_panel.get_node("Content")
	desktop_content_rect = content.get_rect()
	scroll.name = "PortraitLobby"
	lobby.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 20
	scroll.offset_right = -20
	scroll.offset_top = 94
	scroll.offset_bottom = -18
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.hide()
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 18)
	scroll.add_child(stack)
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel", UI.padded_panel(UI.PANEL, UI.TEAL_DARK, 14))
	stack.add_child(hero)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	hero.add_child(row)
	portrait.custom_minimum_size = Vector2(106, 106)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(portrait)
	hero_details.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_details.add_theme_constant_override("separation", 6)
	row.add_child(hero_details)
	role_label.add_theme_font_size_override("font_size", 22)
	role_label.add_theme_color_override("font_color", UI.TEXT_MUTED)
	role_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_details.add_child(role_label)
	form.add_theme_stylebox_override("panel", UI.padded_panel(Color("102a26f7"), UI.BORDER_MUTED, 22))
	stack.add_child(form)
	title.text = lobby.logo_container.get_node("Title").text
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", UI.GOLD)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.position = Vector2(20, 0)
	title.size = Vector2(320, 78)
	lobby.get_node("TopBar").add_child(title)
	title.hide()

	story_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	story_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	story_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	story_backdrop.self_modulate = Color(0.18, 0.25, 0.23)
	lobby.opening_story.add_child(story_backdrop)
	story_backdrop.hide()
	for node in [lobby.opening_image, lobby.opening_story.get_node("StoryTitle"), lobby.opening_story.get_node("CaptionPanel"), lobby.opening_step_label, lobby.opening_skip_button, lobby.opening_next_button]:
		desktop_story_offsets[node] = Vector4(node.offset_left, node.offset_top, node.offset_right, node.offset_bottom)
	update_hero()

func update_hero() -> void:
	portrait.texture = lobby.hero_portrait.texture
	role_label.text = lobby.character_role_label.text

func _style(control: Control, font: int, height: int = 0) -> void:
	var previous_font := control.get_theme_font_size("font_size") if control.has_theme_font_size_override("font_size") else -1
	desktop_controls[control] = [previous_font, control.custom_minimum_size]
	control.add_theme_font_size_override("font_size", font)
	if height > 0: control.custom_minimum_size.y = height

func apply(canvas: Vector2, use_portrait: bool) -> void:
	lobby.size = canvas
	if active != use_portrait:
		active = use_portrait
		for node in [lobby.logo_container, lobby.hero_badge, lobby.hero_glow, lobby.hero_portrait, lobby.menu_panel]:
			if active:
				desktop_visibility[node] = node.visible
				node.hide()
			else:
				node.visible = desktop_visibility[node]
		if not active: desktop_visibility.clear()
		title.visible = active
		scroll.visible = active
		story_backdrop.visible = active
		lobby.opening_story.get_node("Scrim").visible = not active
		if active:
			var actions: Control = lobby.get_node("TopBar/TopActions")
			desktop_action_offsets = Vector4(actions.offset_left, actions.offset_top, actions.offset_right, actions.offset_bottom)
			content.reparent(form, false)
			lobby.character_choose_button.reparent(hero_details, false)
			hero_details.move_child(lobby.character_choose_button, 0)
			content.get_node("CharacterLabel").hide()
			content.add_theme_constant_override("separation", 13)
			_style(content.get_node("NicknameLabel"), 23)
			_style(content.get_node("GameTimeRow/Label"), 23)
			_style(content.get_node("LearningGradeRow").get_child(0), 23)
			_style(lobby.nickname_edit, 26, 68)
			_style(lobby.character_choose_button, 25, 64)
			_style(lobby.game_time_option_button, 23, 70)
			_style(lobby.learning_grade_option, 24, 68)
			_style(lobby.quiz_challenge_option, 24, 68)
			_style(lobby.reading_time_toggle, 24, 64)
			_style(lobby.local_start_button, 27, 78)
			_style(content.get_node("PlayModeButtons/OnlinePlayButton"), 27, 78)
			_style(lobby.minigames_button, 26, 76)
			_style(lobby.status_label, 22)
			_style(lobby.help_button, 22, 62)
			_style(lobby.sound_button, 23, 62)
			_style(lobby.opening_caption, 28)
			_style(lobby.opening_skip_button, 21)
			_style(lobby.opening_next_button, 28)
			_style(lobby.opening_step_label, 23)
			_style(lobby.opening_story.get_node("StoryTitle"), 31)
			lobby.story_school.custom_minimum_size = Vector2(83, 65)
			lobby.get_node("TopBar").offset_bottom = 78
			scroll.scroll_vertical = 0
			update_hero()
		else:
			lobby.character_choose_button.reparent(content, false)
			content.move_child(lobby.character_choose_button, lobby.char_option_button.get_index())
			content.get_node("CharacterLabel").show()
			content.reparent(lobby.menu_panel, false)
			content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			content.position = desktop_content_rect.position
			content.size = desktop_content_rect.size
			content.add_theme_constant_override("separation", 8)
			for node in desktop_controls:
				var saved: Array = desktop_controls[node]
				if saved[0] < 0: node.remove_theme_font_size_override("font_size")
				else: node.add_theme_font_size_override("font_size", saved[0])
				node.custom_minimum_size = saved[1]
			desktop_controls.clear()
			lobby.story_school.custom_minimum_size = Vector2(124, 88)
			lobby.get_node("TopBar").offset_bottom = 54
			var actions: Control = lobby.get_node("TopBar/TopActions")
			actions.offset_left = desktop_action_offsets.x
			actions.offset_top = desktop_action_offsets.y
			actions.offset_right = desktop_action_offsets.z
			actions.offset_bottom = desktop_action_offsets.w
			for node in desktop_story_offsets:
				var margins: Vector4 = desktop_story_offsets[node]
				node.offset_left = margins.x
				node.offset_top = margins.y
				node.offset_right = margins.z
				node.offset_bottom = margins.w
			lobby.opening_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if active:
		var actions: Control = lobby.get_node("TopBar/TopActions")
		actions.position = Vector2(canvas.x - 249, 8)
		actions.size = Vector2(230, 62)
		portrait.custom_minimum_size = Vector2.ONE * clampf(canvas.y * 0.14, 96, 180)
		scroll.offset_top = clampf((canvas.y - 720) * 0.09 + 94, 94, 145)
		_fit_story(canvas)

func _fit_story(canvas: Vector2) -> void:
	var width := canvas.x
	var height := canvas.y
	var inset := 20.0
	var image_height := minf(width * 9.0 / 16.0, height * 0.33)
	var caption_height := minf(216.0, height * 0.31)
	var group_height := image_height + caption_height + 16
	var group_top := 90.0 + maxf(0, height - 90.0 - 112.0 - group_height) * 0.37
	var caption_top := group_top + image_height + 16
	var title_node: Label = lobby.opening_story.get_node("StoryTitle")
	title_node.position = Vector2(12, 13)
	title_node.size = Vector2(width - 222, 64)
	lobby.opening_skip_button.position = Vector2(width - 200, 13)
	lobby.opening_skip_button.size = Vector2(180, 64)
	var art: TextureRect = lobby.opening_image
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.offset_left = 0
	art.offset_right = 0
	art.offset_top = group_top
	art.offset_bottom = group_top + image_height - height
	var caption: PanelContainer = lobby.opening_story.get_node("CaptionPanel")
	caption.position = Vector2(inset, caption_top)
	caption.size = Vector2(width - 2 * inset, caption_height)
	lobby.opening_step_label.position = Vector2(inset, height - 99)
	lobby.opening_step_label.size = Vector2(150, 68)
	lobby.opening_next_button.position = Vector2(185, height - 101)
	lobby.opening_next_button.size = Vector2(width - 185 - inset, 74)
	story_backdrop.texture = art.texture

func story_changed() -> void:
	if active: story_backdrop.texture = lobby.opening_image.texture

extends CanvasLayer

const SAMPLE_RATE := 44100
const SETTINGS_PATH := "user://settings.cfg"

var sensitivity := 1.0
var volume := 0.75
var crosshair_color := "white"
var crosshair_size := "medium"
var high_scores := {
	"sixshot": [],
	"tracking": [],
	"tracking_fast": []
}
var selected_mode := "sixshot"
var in_game := false
var paused := false
var settings_return := "main"
var scenes_return := "main"
var finishing := false

var main_panel: PanelContainer
var pause_panel: PanelContainer
var settings_panel: PanelContainer
var scenes_panel: PanelContainer
var high_scores_panel: PanelContainer
var high_scores_label: Label
var selected_scene_label: Label
var sensitivity_value: Label
var volume_value: Label
var crosshair_color_option: OptionButton
var crosshair_size_option: OptionButton
var bgm_player: AudioStreamPlayer
var shot_player: AudioStreamPlayer
var hit_player: AudioStreamPlayer

@onready var player: Node = $"../Player"
@onready var hud: CanvasLayer = $"../HUD"
@onready var arena: Node = $".."

func _ready() -> void:
	add_to_group("game_menu")
	add_to_group("game_audio")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_load_settings()
	_build_audio()
	_build_ui()
	_apply_volume()
	_apply_crosshair_settings()
	_show_main_menu()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if in_game and not paused and visible == false:
			pause_game()
			get_viewport().set_input_as_handled()
		elif in_game and paused and pause_panel and pause_panel.visible:
			resume_game()
			get_viewport().set_input_as_handled()

func play_shot() -> void:
	if shot_player:
		shot_player.stop()
		shot_player.play()

func play_hit() -> void:
	if hit_player:
		hit_player.stop()
		hit_player.play()

func pause_game() -> void:
	if not in_game or finishing:
		return
	paused = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if player and player.has_method("stop_training"):
		player.stop_training()
	if hud and hud.has_method("set_paused"):
		hud.set_paused(true)
	_show_pause_menu()

func resume_game() -> void:
	if not in_game or finishing:
		return
	paused = false
	visible = false
	if hud and hud.has_method("set_paused"):
		hud.set_paused(false)
	if player and player.has_method("start_training"):
		player.start_training(sensitivity)

func training_finished() -> void:
	if finishing:
		return
	finishing = true
	if hud and hud.has_method("get_score"):
		_record_high_score(hud.get_score())
	await get_tree().create_timer(0.9).timeout
	_return_to_main_menu()
	finishing = false

func _start_game() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	in_game = true
	paused = false
	finishing = false
	visible = false
	if arena and arena.has_method("start_mode"):
		arena.start_mode(selected_mode)
	if hud:
		hud.player = player
		_apply_crosshair_settings()
		hud.start_training(selected_mode)
	if player and player.has_method("start_training"):
		player.start_training(sensitivity)
	if bgm_player:
		bgm_player.play()

func _return_to_main_menu() -> void:
	in_game = false
	paused = false
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if bgm_player:
		bgm_player.stop()
	if player and player.has_method("stop_training"):
		player.stop_training()
	if hud and hud.has_method("stop_training"):
		hud.stop_training()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_show_main_menu()

func _show_settings_from_main() -> void:
	settings_return = "main"
	_show_settings()

func _show_settings_from_pause() -> void:
	settings_return = "pause"
	_show_settings()

func _show_scenes_from_main() -> void:
	scenes_return = "main"
	_show_scenes()

func _show_scenes_from_pause() -> void:
	scenes_return = "pause"
	_show_scenes()

func _show_settings() -> void:
	main_panel.visible = false
	pause_panel.visible = false
	scenes_panel.visible = false
	high_scores_panel.visible = false
	settings_panel.visible = true

func _back_from_settings() -> void:
	settings_panel.visible = false
	if settings_return == "pause" and in_game:
		pause_panel.visible = true
		high_scores_panel.visible = false
	else:
		main_panel.visible = true
		high_scores_panel.visible = true

func _show_scenes() -> void:
	main_panel.visible = false
	pause_panel.visible = false
	settings_panel.visible = false
	high_scores_panel.visible = false
	scenes_panel.visible = true

func _back_from_scenes() -> void:
	scenes_panel.visible = false
	if scenes_return == "pause" and in_game:
		pause_panel.visible = true
		high_scores_panel.visible = false
	else:
		main_panel.visible = true
		high_scores_panel.visible = true

func _show_main_menu() -> void:
	main_panel.visible = true
	high_scores_panel.visible = true
	pause_panel.visible = false
	settings_panel.visible = false
	scenes_panel.visible = false

func _show_pause_menu() -> void:
	main_panel.visible = false
	high_scores_panel.visible = false
	pause_panel.visible = true
	settings_panel.visible = false
	scenes_panel.visible = false

func _quit_game() -> void:
	get_tree().quit()

func _on_sensitivity_changed(value: float) -> void:
	sensitivity = clampf(value, 0.1, 10.0)
	if sensitivity_value:
		sensitivity_value.text = "%.1f" % sensitivity
	if in_game and not paused and player and player.has_method("start_training"):
		player.start_training(sensitivity)
	_save_settings()

func _on_volume_changed(value: float) -> void:
	volume = clampf(value / 100.0, 0.0, 1.0)
	if volume_value:
		volume_value.text = "%d%%" % int(round(volume * 100.0))
	_apply_volume()
	_save_settings()

func _on_crosshair_color_selected(index: int) -> void:
	var values := ["white", "red", "blue"]
	if index >= 0 and index < values.size():
		crosshair_color = values[index]
	_apply_crosshair_settings()
	_save_settings()

func _on_crosshair_size_selected(index: int) -> void:
	var values := ["small", "medium", "large"]
	if index >= 0 and index < values.size():
		crosshair_size = values[index]
	_apply_crosshair_settings()
	_save_settings()

func _select_mode(mode: String) -> void:
	selected_mode = mode
	_update_selected_scene_label()
	_save_settings()
	_start_game()

func _apply_volume() -> void:
	var db := linear_to_db(maxf(volume, 0.001))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

func _apply_crosshair_settings() -> void:
	if hud and hud.has_method("configure_crosshair"):
		hud.configure_crosshair(crosshair_color, crosshair_size)

func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error != OK:
		return
	sensitivity = clampf(float(config.get_value("gameplay", "sensitivity", sensitivity)), 0.1, 10.0)
	volume = clampf(float(config.get_value("audio", "volume", volume)), 0.0, 1.0)
	crosshair_color = str(config.get_value("crosshair", "color", crosshair_color))
	crosshair_size = str(config.get_value("crosshair", "size", crosshair_size))
	selected_mode = str(config.get_value("gameplay", "selected_mode", selected_mode))
	for mode in high_scores.keys():
		high_scores[mode] = _score_array_from_config(config.get_value("scores", mode, []))
	var legacy_scores: Array = config.get_value("scores", "top_five", [])
	if not legacy_scores.is_empty() and high_scores["sixshot"].is_empty():
		high_scores["sixshot"] = _score_array_from_config(legacy_scores)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("gameplay", "sensitivity", sensitivity)
	config.set_value("gameplay", "selected_mode", selected_mode)
	config.set_value("audio", "volume", volume)
	config.set_value("crosshair", "color", crosshair_color)
	config.set_value("crosshair", "size", crosshair_size)
	for mode in high_scores.keys():
		config.set_value("scores", mode, high_scores[mode])
	config.save(SETTINGS_PATH)

func _record_high_score(value: int) -> void:
	var scores: Array = high_scores.get(selected_mode, [])
	scores.append(value)
	high_scores[selected_mode] = _sort_and_trim_scores(scores)
	_save_settings()
	_update_high_scores_label()

func _score_array_from_config(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(int(value))
	return _sort_and_trim_scores(result)

func _sort_and_trim_scores(scores: Array) -> Array[int]:
	var sorted_scores: Array[int] = []
	for value in scores:
		sorted_scores.append(int(value))
	sorted_scores.sort()
	sorted_scores.reverse()
	while sorted_scores.size() > 5:
		sorted_scores.pop_back()
	return sorted_scores

func _update_high_scores_label() -> void:
	if high_scores_label == null:
		return
	var lines: Array[String] = []
	for mode in ["sixshot", "tracking", "tracking_fast"]:
		lines.append(_mode_display_name(mode))
		var scores: Array = high_scores.get(mode, [])
		if scores.is_empty():
			lines.append("暂无记录")
		else:
			for i in scores.size():
				lines.append("%d. %d" % [i + 1, scores[i]])
		lines.append("")
	high_scores_label.text = "\n".join(lines)

func _build_ui() -> void:
	var root := Control.new()
	root.name = "MenuRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var background := ColorRect.new()
	background.color = Color(0.06, 0.075, 0.085, 0.96)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var title := Label.new()
	title.text = "Sixshot Trainer"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-210, 88)
	title.size = Vector2(420, 58)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0))
	root.add_child(title)

	main_panel = _panel(Vector2(-150, -130), Vector2(300, 300))
	root.add_child(main_panel)
	var main_box := _vbox(main_panel)
	main_box.add_child(_button("开始游戏", _start_game))
	selected_scene_label = Label.new()
	selected_scene_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_scene_label.add_theme_font_size_override("font_size", 16)
	selected_scene_label.custom_minimum_size = Vector2(260, 28)
	main_box.add_child(selected_scene_label)
	main_box.add_child(_button("选择场景", _show_scenes_from_main))
	main_box.add_child(_button("设置", _show_settings_from_main))
	main_box.add_child(_button("退出游戏", _quit_game))
	_update_selected_scene_label()

	high_scores_panel = _panel(Vector2(210, -170), Vector2(300, 420))
	root.add_child(high_scores_panel)
	var scores_box := _vbox(high_scores_panel)
	var scores_title := Label.new()
	scores_title.text = "历史最高分"
	scores_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scores_title.add_theme_font_size_override("font_size", 22)
	scores_box.add_child(scores_title)
	high_scores_label = Label.new()
	high_scores_label.custom_minimum_size = Vector2(260, 330)
	high_scores_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	high_scores_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	high_scores_label.add_theme_font_size_override("font_size", 16)
	scores_box.add_child(high_scores_label)
	_update_high_scores_label()

	pause_panel = _panel(Vector2(-150, -120), Vector2(300, 280))
	root.add_child(pause_panel)
	var pause_box := _vbox(pause_panel)
	pause_box.add_child(_button("继续游戏", resume_game))
	pause_box.add_child(_button("选择场景", _show_scenes_from_pause))
	pause_box.add_child(_button("设置", _show_settings_from_pause))
	pause_box.add_child(_button("返回主菜单", _return_to_main_menu))

	scenes_panel = _panel(Vector2(-210, -150), Vector2(420, 330))
	root.add_child(scenes_panel)
	var scenes_box := _vbox(scenes_panel)
	var scenes_title := Label.new()
	scenes_title.text = "选择场景"
	scenes_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scenes_title.add_theme_font_size_override("font_size", 26)
	scenes_box.add_child(scenes_title)
	scenes_box.add_child(_button("六目标训练", func() -> void: _select_mode("sixshot")))
	scenes_box.add_child(_button("跟枪训练", func() -> void: _select_mode("tracking")))
	scenes_box.add_child(_button("快速跟枪", func() -> void: _select_mode("tracking_fast")))
	scenes_box.add_child(_button("返回", _back_from_scenes))

	settings_panel = _panel(Vector2(-230, -205), Vector2(460, 440))
	root.add_child(settings_panel)
	var settings_box := _vbox(settings_panel)

	var settings_title := Label.new()
	settings_title.text = "设置"
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_title.add_theme_font_size_override("font_size", 26)
	settings_box.add_child(settings_title)

	settings_box.add_child(_slider_row("灵敏度", 0.1, 10.0, 0.1, sensitivity, _on_sensitivity_changed, true))
	settings_box.add_child(_slider_row("音量", 0.0, 100.0, 1.0, volume * 100.0, _on_volume_changed, false))
	settings_box.add_child(_option_row("准星颜色", ["白色", "红色", "蓝色"], _crosshair_color_index(), _on_crosshair_color_selected, true))
	settings_box.add_child(_option_row("准星大小", ["小", "中", "大"], _crosshair_size_index(), _on_crosshair_size_selected, false))
	settings_box.add_child(_button("返回", _back_from_settings))

func _panel(pos: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = pos
	panel.size = size
	return panel

func _vbox(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	parent.add_child(box)
	return box

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 48)
	button.pressed.connect(callback)
	return button

func _update_selected_scene_label() -> void:
	if selected_scene_label == null:
		return
	selected_scene_label.text = "当前: %s" % _mode_display_name(selected_mode)

func _mode_display_name(mode: String) -> String:
	match mode:
		"sixshot":
			return "六目标训练"
		"tracking":
			return "跟枪训练"
		"tracking_fast":
			return "快速跟枪"
		_:
			return "六目标训练"

func _slider_row(label_text: String, min_value: float, max_value: float, step: float, initial: float, callback: Callable, is_sensitivity: bool) -> VBoxContainer:
	var box := VBoxContainer.new()
	var header := HBoxContainer.new()
	box.add_child(header)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 24)
	header.add_child(label)

	var value_label := Label.new()
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(260, 24)
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size = Vector2(380, 36)
	slider.value_changed.connect(callback)
	box.add_child(slider)

	if is_sensitivity:
		sensitivity_value = value_label
		_on_sensitivity_changed(initial)
	else:
		volume_value = value_label
		_on_volume_changed(initial)
	return box

func _option_row(label_text: String, items: Array[String], selected_index: int, callback: Callable, is_color: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(380, 42)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 34)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(250, 34)
	for item in items:
		option.add_item(item)
	option.select(clampi(selected_index, 0, items.size() - 1))
	option.item_selected.connect(callback)
	row.add_child(option)

	if is_color:
		crosshair_color_option = option
	else:
		crosshair_size_option = option
	return row

func _crosshair_color_index() -> int:
	match crosshair_color:
		"white":
			return 0
		"red":
			return 1
		"blue":
			return 2
		_:
			return 0

func _crosshair_size_index() -> int:
	match crosshair_size:
		"small":
			return 0
		"medium":
			return 1
		"large":
			return 2
		_:
			return 1

func _build_audio() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGM"
	bgm_player.stream = _make_bgm_stream()
	add_child(bgm_player)

	shot_player = AudioStreamPlayer.new()
	shot_player.name = "ShotSound"
	shot_player.stream = _make_shot_stream()
	add_child(shot_player)

	hit_player = AudioStreamPlayer.new()
	hit_player.name = "HitSound"
	hit_player.stream = _make_hit_stream()
	add_child(hit_player)

func _make_bgm_stream() -> AudioStreamWAV:
	var duration := 4.0
	var bytes := PackedByteArray()
	var notes := [261.63, 329.63, 392.0, 523.25, 392.0, 329.63, 293.66, 440.0]
	var total_samples := int(SAMPLE_RATE * duration)
	for i in total_samples:
		var t := float(i) / SAMPLE_RATE
		var beat := int(t * 2.0) % notes.size()
		var local := fmod(t * 2.0, 1.0)
		var env := minf(local * 8.0, 1.0) * maxf(1.0 - local * 0.55, 0.0)
		var sample := sin(TAU * notes[beat] * t) * 0.14 * env
		sample += sin(TAU * notes[(beat + 2) % notes.size()] * 0.5 * t) * 0.06
		_append_i16(bytes, int(clamp(sample, -1.0, 1.0) * 32767.0))
	return _wav(bytes, true)

func _make_shot_stream() -> AudioStreamWAV:
	var duration := 0.11
	var bytes := PackedByteArray()
	var total_samples := int(SAMPLE_RATE * duration)
	for i in total_samples:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 42.0)
		var noise := randf_range(-1.0, 1.0) * 0.45
		var thump := sin(TAU * 86.0 * t) * 0.55
		_append_i16(bytes, int(clamp((noise + thump) * env, -1.0, 1.0) * 32767.0))
	return _wav(bytes, false)

func _make_hit_stream() -> AudioStreamWAV:
	var duration := 0.18
	var bytes := PackedByteArray()
	var total_samples := int(SAMPLE_RATE * duration)
	for i in total_samples:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 12.0)
		var sample := sin(TAU * 880.0 * t) * 0.28 + sin(TAU * 1320.0 * t) * 0.18
		_append_i16(bytes, int(clamp(sample * env, -1.0, 1.0) * 32767.0))
	return _wav(bytes, false)

func _wav(bytes: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = bytes.size() / 2
	return stream

func _append_i16(bytes: PackedByteArray, value: int) -> void:
	var sample := clampi(value, -32768, 32767)
	if sample < 0:
		sample += 65536
	bytes.append(sample & 0xff)
	bytes.append((sample >> 8) & 0xff)

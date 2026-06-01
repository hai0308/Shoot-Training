extends CanvasLayer

const SAMPLE_RATE := 44100
const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_ONLINE_API_BASE := "https://six-target-fps-20260526.netlify.app"

var sensitivity := 1.0
var volume := 0.75
var crosshair_color := "white"
var crosshair_size := "medium"
var training_duration := 60
var online_api_base := DEFAULT_ONLINE_API_BASE
var online_username := ""
var online_token := ""
var pending_online_action := ""
var difficulty := "normal"
var high_scores := {
	"sixshot": [],
	"tracking": [],
	"tracking_fast": [],
	"reaction": []
}
var selected_mode := "sixshot"
var in_game := false
var paused := false
var settings_return := "main"
var scenes_return := "main"
var finishing := false
var starting_game := false
var menu_time := 0.0

var main_panel: PanelContainer
var pause_panel: PanelContainer
var settings_panel: PanelContainer
var scenes_panel: PanelContainer
var result_panel: PanelContainer
var countdown_panel: PanelContainer
var auth_panel: PanelContainer
var online_scores_panel: PanelContainer
var high_scores_panel: PanelContainer
var high_scores_label: Label
var auth_status_label: Label
var auth_username_input: LineEdit
var auth_password_input: LineEdit
var api_base_input: LineEdit
var online_status_label: Label
var online_scores_label: Label
var result_title_label: Label
var result_score_label: Label
var result_grade_label: Label
var result_note_label: Label
var countdown_label: Label
var background_marks: Array[ColorRect] = []
var background_speeds: Array[float] = []
var selected_scene_label: Label
var sensitivity_value: Label
var volume_value: Label
var crosshair_color_option: OptionButton
var crosshair_size_option: OptionButton
var duration_option: OptionButton
var difficulty_option: OptionButton
var bgm_player: AudioStreamPlayer
var shot_player: AudioStreamPlayer
var hit_player: AudioStreamPlayer
var countdown_player: AudioStreamPlayer
var combo_player: AudioStreamPlayer
var http_request: HTTPRequest

@onready var player: Node = $"../Player"
@onready var hud: CanvasLayer = $"../HUD"
@onready var arena: Node = $".."

func _ready() -> void:
	add_to_group("game_menu")
	add_to_group("game_audio")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_load_settings()
	_build_network()
	_build_audio()
	_build_ui()
	_apply_volume()
	_apply_crosshair_settings()
	_show_main_menu()

func _process(delta: float) -> void:
	menu_time += delta
	for i in background_marks.size():
		var mark := background_marks[i]
		if mark == null:
			continue
		var speed := background_speeds[i]
		var offset := sin(menu_time * speed + float(i) * 0.73) * 9.0
		mark.position.x += delta * speed * 4.0
		mark.position.y += sin(menu_time * 0.55 + float(i)) * delta * 3.0
		mark.modulate.a = 0.18 + 0.18 * abs(sin(menu_time * speed + float(i)))
		if mark.position.x > 760:
			mark.position.x = -760
		mark.rotation = offset * 0.002

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

func play_combo() -> void:
	if combo_player:
		combo_player.stop()
		combo_player.play()

func _build_network() -> void:
	http_request = HTTPRequest.new()
	http_request.name = "OnlineHTTPRequest"
	http_request.request_completed.connect(_on_online_request_completed)
	add_child(http_request)

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
	var final_score := 0
	if hud and hud.has_method("get_score"):
		final_score = hud.get_score()
	var new_high_score := _is_new_high_score(final_score, selected_mode)
	_record_high_score(final_score)
	_submit_online_score(final_score)
	if bgm_player:
		bgm_player.stop()
	if hud and hud.has_method("stop_training"):
		hud.stop_training()
	var summary := {}
	if hud and hud.has_method("get_summary"):
		summary = hud.get_summary()
	_show_result_screen(final_score, new_high_score, summary)
	await get_tree().create_timer(3.2).timeout
	_return_to_main_menu()
	finishing = false

func _start_game() -> void:
	if starting_game:
		return
	starting_game = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	in_game = true
	paused = false
	finishing = false
	visible = true
	_hide_all_panels()
	countdown_panel.visible = true
	if arena and arena.has_method("start_mode"):
		if arena.has_method("set_difficulty"):
			arena.set_difficulty(difficulty)
		arena.start_mode(selected_mode)
	if bgm_player:
		bgm_player.play()
	for text in ["3", "2", "1", "GO"]:
		countdown_label.text = text
		if countdown_player:
			countdown_player.stop()
			countdown_player.play()
		await get_tree().create_timer(0.62 if text != "GO" else 0.42).timeout
	countdown_panel.visible = false
	visible = false
	if hud:
		hud.player = player
		_apply_crosshair_settings()
		hud.start_training(selected_mode, float(training_duration))
	if player and player.has_method("start_training"):
		player.start_training(sensitivity)
	starting_game = false

func _return_to_main_menu() -> void:
	in_game = false
	paused = false
	starting_game = false
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

func _show_auth() -> void:
	_hide_all_panels()
	auth_panel.visible = true
	if api_base_input:
		api_base_input.text = online_api_base
	_update_auth_status()

func _show_online_scores() -> void:
	_hide_all_panels()
	online_scores_panel.visible = true
	online_scores_label.text = "正在获取联机排行榜..."
	online_status_label.text = _online_status_text()
	_get_online_leaderboards()

func _show_settings() -> void:
	_hide_all_panels()
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
	_hide_all_panels()
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
	_hide_all_panels()
	main_panel.visible = true
	high_scores_panel.visible = true

func _show_pause_menu() -> void:
	_hide_all_panels()
	pause_panel.visible = true

func _show_result_screen(final_score: int, new_high_score: bool, summary: Dictionary = {}) -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_hide_all_panels()
	result_panel.visible = true
	if new_high_score:
		result_title_label.text = "恭喜突破最高分!"
		result_title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.42))
		result_note_label.text = "新的%s纪录已经保存" % _mode_display_name(selected_mode)
	else:
		result_title_label.text = "训练完成"
		result_title_label.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0))
		result_note_label.text = "%s成绩已记录" % _mode_display_name(selected_mode)
	var accuracy := int(summary.get("accuracy", 0))
	var best_combo := int(summary.get("best_combo", 0))
	result_score_label.text = "本次得分  %d\n命中率  %d%%\n最佳连击  %d" % [final_score, accuracy, best_combo]
	result_grade_label.text = "评级  %s" % _grade_for_score(final_score)

func _hide_all_panels() -> void:
	if main_panel:
		main_panel.visible = false
	if pause_panel:
		pause_panel.visible = false
	if settings_panel:
		settings_panel.visible = false
	if scenes_panel:
		scenes_panel.visible = false
	if result_panel:
		result_panel.visible = false
	if countdown_panel:
		countdown_panel.visible = false
	if auth_panel:
		auth_panel.visible = false
	if online_scores_panel:
		online_scores_panel.visible = false
	if high_scores_panel:
		high_scores_panel.visible = false

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

func _on_duration_selected(index: int) -> void:
	var values := [30, 60, 90]
	if index >= 0 and index < values.size():
		training_duration = values[index]
	_save_settings()

func _on_difficulty_selected(index: int) -> void:
	var values := ["easy", "normal", "hard"]
	if index >= 0 and index < values.size():
		difficulty = values[index]
	_save_settings()

func _register_online() -> void:
	_send_auth_request("register")

func _login_online() -> void:
	_send_auth_request("login")

func _logout_online() -> void:
	online_username = ""
	online_token = ""
	_save_settings()
	_update_auth_status()

func _send_auth_request(action: String) -> void:
	if _online_busy():
		return
	_apply_api_base_from_input()
	var username := auth_username_input.text.strip_edges().to_lower()
	var password := auth_password_input.text
	if username.length() < 3 or password.length() < 6:
		auth_status_label.text = "用户名或密码格式不正确"
		return
	pending_online_action = action
	auth_status_label.text = "正在%s..." % ("注册" if action == "register" else "登录")
	_post_json("/api/%s" % action, {
		"username": username,
		"password": password
	})

func _submit_online_score(score_value: int) -> void:
	if online_token.is_empty() or _online_busy():
		return
	pending_online_action = "submit-score"
	_post_json("/api/submit-score", {
		"token": online_token,
		"mode": selected_mode,
		"score": score_value
	})

func _get_online_leaderboards() -> void:
	if _online_busy():
		return
	_apply_api_base_from_input()
	pending_online_action = "leaderboards"
	_get_json("/api/leaderboards")

func _post_json(path: String, body: Dictionary) -> void:
	var headers := ["Content-Type: application/json"]
	var error := http_request.request(_api_url(path), headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		_handle_online_error("无法连接在线服务")

func _get_json(path: String) -> void:
	var error := http_request.request(_api_url(path), [], HTTPClient.METHOD_GET)
	if error != OK:
		_handle_online_error("无法连接在线服务")

func _api_url(path: String) -> String:
	return online_api_base.trim_suffix("/") + path

func _apply_api_base_from_input() -> void:
	if api_base_input == null:
		return
	var value := api_base_input.text.strip_edges().trim_suffix("/")
	if value.begins_with("http://") or value.begins_with("https://"):
		online_api_base = value
		_save_settings()

func _online_busy() -> bool:
	return not pending_online_action.is_empty()

func _on_online_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var action := pending_online_action
	pending_online_action = ""
	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text)
	if response_code < 200 or response_code >= 300 or typeof(data) != TYPE_DICTIONARY:
		_handle_online_error(_online_error_text(data))
		return
	match action:
		"register":
			auth_status_label.text = "注册成功，现在可以登录"
		"login":
			online_username = str(data.get("username", ""))
			online_token = str(data.get("token", ""))
			auth_password_input.text = ""
			_save_settings()
			_update_auth_status()
		"submit-score":
			pass
		"leaderboards":
			_render_online_leaderboards(data.get("leaderboards", {}))

func _handle_online_error(message: String) -> void:
	pending_online_action = ""
	if auth_panel and auth_panel.visible and auth_status_label:
		auth_status_label.text = message
	if online_scores_panel and online_scores_panel.visible and online_scores_label:
		online_scores_label.text = message

func _online_error_text(data) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "在线服务返回异常"
	match str(data.get("error", "")):
		"username_taken":
			return "用户名已被注册"
		"login_failed":
			return "用户名或密码错误"
		"invalid_credentials":
			return "用户名或密码格式不正确"
		"unauthorized":
			return "登录已过期，请重新登录"
		_:
			return "在线服务暂时不可用"

func _update_auth_status() -> void:
	if auth_status_label == null:
		return
	auth_status_label.text = _online_status_text()
	if auth_username_input and not online_username.is_empty():
		auth_username_input.text = online_username

func _online_status_text() -> String:
	if online_username.is_empty():
		return "未登录 - 在线排行需要登录后提交分数"
	return "已登录: %s" % online_username

func _render_online_leaderboards(leaderboards) -> void:
	if online_scores_label == null:
		return
	if typeof(leaderboards) != TYPE_DICTIONARY:
		online_scores_label.text = "暂无在线排行数据"
		return
	var lines: Array[String] = []
	for mode in ["sixshot", "tracking", "tracking_fast", "reaction"]:
		lines.append(_mode_display_name(mode))
		var rows: Array = leaderboards.get(mode, [])
		if rows.is_empty():
			lines.append("暂无记录")
		else:
			var limit = mini(rows.size(), 10)
			for i in limit:
				var row: Dictionary = rows[i]
				lines.append("%02d. %-12s %d" % [i + 1, str(row.get("username", "---")), int(row.get("score", 0))])
		lines.append("")
	online_scores_label.text = "\n".join(lines)

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
	training_duration = int(config.get_value("gameplay", "duration", training_duration))
	if not [30, 60, 90].has(training_duration):
		training_duration = 60
	difficulty = str(config.get_value("gameplay", "difficulty", difficulty))
	if not ["easy", "normal", "hard"].has(difficulty):
		difficulty = "normal"
	online_api_base = str(config.get_value("online", "api_base", online_api_base))
	if online_api_base == "http://localhost:8888":
		online_api_base = DEFAULT_ONLINE_API_BASE
	online_username = str(config.get_value("online", "username", online_username))
	online_token = str(config.get_value("online", "token", online_token))
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
	config.set_value("gameplay", "duration", training_duration)
	config.set_value("gameplay", "difficulty", difficulty)
	config.set_value("audio", "volume", volume)
	config.set_value("crosshair", "color", crosshair_color)
	config.set_value("crosshair", "size", crosshair_size)
	config.set_value("online", "api_base", online_api_base)
	config.set_value("online", "username", online_username)
	config.set_value("online", "token", online_token)
	for mode in high_scores.keys():
		config.set_value("scores", mode, high_scores[mode])
	config.save(SETTINGS_PATH)

func _record_high_score(value: int) -> void:
	var scores: Array = high_scores.get(selected_mode, [])
	scores.append(value)
	high_scores[selected_mode] = _sort_and_trim_scores(scores)
	_save_settings()
	_update_high_scores_label()

func _is_new_high_score(value: int, mode: String) -> bool:
	var scores: Array = high_scores.get(mode, [])
	if scores.is_empty():
		return true
	return value > int(scores[0])

func _grade_for_score(value: int) -> String:
	var per_minute := float(value) / maxf(float(training_duration), 1.0) * 60.0
	if per_minute >= 42000.0:
		return "S"
	if per_minute >= 30000.0:
		return "A"
	if per_minute >= 19000.0:
		return "B"
	if per_minute >= 9000.0:
		return "C"
	return "D"

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
	while sorted_scores.size() > 3:
		sorted_scores.pop_back()
	return sorted_scores

func _update_high_scores_label() -> void:
	if high_scores_label == null:
		return
	var lines: Array[String] = []
	for mode in ["sixshot", "tracking", "tracking_fast", "reaction"]:
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
	background.color = Color(0.035, 0.043, 0.048, 0.98)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var top_band := ColorRect.new()
	top_band.color = Color(0.08, 0.105, 0.115, 0.85)
	top_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_band.offset_bottom = 86
	root.add_child(top_band)

	var bottom_band := ColorRect.new()
	bottom_band.color = Color(0.02, 0.025, 0.028, 0.72)
	bottom_band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_band.offset_top = -46
	bottom_band.offset_bottom = 0
	root.add_child(bottom_band)

	var accent_line := ColorRect.new()
	accent_line.color = Color(0.05, 0.82, 0.9, 0.85)
	accent_line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	accent_line.offset_top = 84
	accent_line.offset_bottom = 86
	root.add_child(accent_line)
	_build_dynamic_background(root)

	var title := Label.new()
	title.text = "SHOOT TRAINING"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-260, 96)
	title.size = Vector2(520, 58)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.72))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Aim, flick, track, repeat."
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(-220, 152)
	subtitle.size = Vector2(440, 28)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.58, 0.72, 0.76))
	root.add_child(subtitle)

	var footer := Label.new()
	footer.text = "Esc 暂停    鼠标瞄准    左键射击"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -42
	footer.offset_bottom = -8
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", Color(0.62, 0.72, 0.74))
	root.add_child(footer)

	main_panel = _panel(Vector2(-180, -190), Vector2(340, 470))
	root.add_child(main_panel)
	var main_box := _vbox(main_panel)
	main_box.add_child(_section_title("主菜单"))
	main_box.add_child(_button("开始游戏", _start_game))
	selected_scene_label = Label.new()
	selected_scene_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_scene_label.add_theme_font_size_override("font_size", 16)
	selected_scene_label.add_theme_color_override("font_color", Color(0.56, 0.86, 0.92))
	selected_scene_label.custom_minimum_size = Vector2(300, 28)
	main_box.add_child(selected_scene_label)
	main_box.add_child(_button("选择场景", _show_scenes_from_main))
	main_box.add_child(_button("登录/注册", _show_auth))
	main_box.add_child(_button("联机排行", _show_online_scores))
	main_box.add_child(_button("设置", _show_settings_from_main))
	main_box.add_child(_button("退出游戏", _quit_game))
	_update_selected_scene_label()

	high_scores_panel = _panel(Vector2(230, -190), Vector2(330, 440))
	root.add_child(high_scores_panel)
	var scores_box := _vbox(high_scores_panel)
	scores_box.add_child(_section_title("历史最高分"))
	high_scores_label = Label.new()
	high_scores_label.custom_minimum_size = Vector2(290, 340)
	high_scores_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	high_scores_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	high_scores_label.add_theme_font_size_override("font_size", 16)
	high_scores_label.add_theme_color_override("font_color", Color(0.82, 0.9, 0.92))
	scores_box.add_child(high_scores_label)
	_update_high_scores_label()

	pause_panel = _panel(Vector2(-170, -120), Vector2(340, 300))
	root.add_child(pause_panel)
	var pause_box := _vbox(pause_panel)
	pause_box.add_child(_section_title("暂停"))
	pause_box.add_child(_button("继续游戏", resume_game))
	pause_box.add_child(_button("选择场景", _show_scenes_from_pause))
	pause_box.add_child(_button("设置", _show_settings_from_pause))
	pause_box.add_child(_button("返回主菜单", _return_to_main_menu))

	scenes_panel = _panel(Vector2(-230, -200), Vector2(460, 450))
	root.add_child(scenes_panel)
	var scenes_box := _vbox(scenes_panel)
	scenes_box.add_child(_section_title("选择场景"))
	scenes_box.add_child(_note_label("选择后会直接开始对应训练"))
	scenes_box.add_child(_button("六目标训练", func() -> void: _select_mode("sixshot")))
	scenes_box.add_child(_button("跟枪训练", func() -> void: _select_mode("tracking")))
	scenes_box.add_child(_button("快速跟枪", func() -> void: _select_mode("tracking_fast")))
	scenes_box.add_child(_button("反应训练", func() -> void: _select_mode("reaction")))
	scenes_box.add_child(_button("返回", _back_from_scenes))

	auth_panel = _panel(Vector2(-250, -235), Vector2(500, 520))
	root.add_child(auth_panel)
	var auth_box := _vbox(auth_panel)
	auth_box.add_child(_section_title("账号登录"))
	auth_status_label = _note_label("")
	auth_status_label.custom_minimum_size = Vector2(420, 34)
	auth_box.add_child(auth_status_label)
	api_base_input = _line_edit("服务器地址，例如 https://xxx.netlify.app", false)
	api_base_input.text = online_api_base
	auth_box.add_child(api_base_input)
	auth_username_input = _line_edit("用户名 3-18 位字母数字下划线", false)
	auth_box.add_child(auth_username_input)
	auth_password_input = _line_edit("密码至少 6 位", true)
	auth_box.add_child(auth_password_input)
	auth_box.add_child(_button("注册", _register_online))
	auth_box.add_child(_button("登录", _login_online))
	auth_box.add_child(_button("退出登录", _logout_online))
	auth_box.add_child(_button("返回", _show_main_menu))

	online_scores_panel = _panel(Vector2(-280, -235), Vector2(560, 540))
	root.add_child(online_scores_panel)
	var online_box := _vbox(online_scores_panel)
	online_box.add_child(_section_title("联机排行榜"))
	online_status_label = _note_label("")
	online_status_label.custom_minimum_size = Vector2(520, 28)
	online_box.add_child(online_status_label)
	online_scores_label = Label.new()
	online_scores_label.custom_minimum_size = Vector2(520, 360)
	online_scores_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_scores_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	online_scores_label.add_theme_font_size_override("font_size", 15)
	online_scores_label.add_theme_color_override("font_color", Color(0.82, 0.9, 0.92))
	online_box.add_child(online_scores_label)
	online_box.add_child(_button("刷新", _get_online_leaderboards))
	online_box.add_child(_button("返回", _show_main_menu))

	result_panel = _panel(Vector2(-230, -165), Vector2(460, 370))
	root.add_child(result_panel)
	var result_box := _vbox(result_panel)
	result_title_label = _section_title("训练完成")
	result_title_label.add_theme_font_size_override("font_size", 30)
	result_box.add_child(result_title_label)
	result_score_label = Label.new()
	result_score_label.custom_minimum_size = Vector2(420, 120)
	result_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_score_label.add_theme_font_size_override("font_size", 34)
	result_score_label.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0))
	result_box.add_child(result_score_label)
	result_grade_label = Label.new()
	result_grade_label.custom_minimum_size = Vector2(420, 44)
	result_grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_grade_label.add_theme_font_size_override("font_size", 28)
	result_grade_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.38))
	result_box.add_child(result_grade_label)
	result_note_label = _note_label("即将返回主菜单")
	result_note_label.custom_minimum_size = Vector2(420, 34)
	result_box.add_child(result_note_label)
	var return_label := _note_label("3 秒后返回主菜单")
	return_label.custom_minimum_size = Vector2(420, 28)
	result_box.add_child(return_label)

	countdown_panel = _panel(Vector2(-160, -110), Vector2(320, 220))
	root.add_child(countdown_panel)
	var countdown_box := _vbox(countdown_panel)
	countdown_box.add_child(_section_title("准备"))
	countdown_label = Label.new()
	countdown_label.text = "3"
	countdown_label.custom_minimum_size = Vector2(280, 120)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 74)
	countdown_label.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0))
	countdown_box.add_child(countdown_label)

	settings_panel = _panel(Vector2(-250, -275), Vector2(500, 590))
	root.add_child(settings_panel)
	var settings_box := _vbox(settings_panel)
	settings_box.add_child(_section_title("设置"))

	settings_box.add_child(_slider_row("灵敏度", 0.1, 10.0, 0.1, sensitivity, _on_sensitivity_changed, true))
	settings_box.add_child(_slider_row("音量", 0.0, 100.0, 1.0, volume * 100.0, _on_volume_changed, false))
	settings_box.add_child(_option_row("准星颜色", ["白色", "红色", "蓝色"], _crosshair_color_index(), _on_crosshair_color_selected, true))
	settings_box.add_child(_option_row("准星大小", ["小", "中", "大"], _crosshair_size_index(), _on_crosshair_size_selected, false))
	settings_box.add_child(_option_row("训练时长", ["30 秒", "60 秒", "90 秒"], _duration_index(), _on_duration_selected, false))
	settings_box.add_child(_option_row("难度", ["简单", "普通", "困难"], _difficulty_index(), _on_difficulty_selected, false))
	settings_box.add_child(_button("返回", _back_from_settings))

func _panel(pos: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = pos
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.08, 0.088, 0.93)
	style.border_color = Color(0.10, 0.75, 0.82, 0.52)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 18
	style.content_margin_top = 18
	style.content_margin_right = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _vbox(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	parent.add_child(box)
	return box

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(300, 48)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", Color(0.90, 0.98, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.09, 0.13, 0.14, 0.95), Color(0.10, 0.45, 0.50, 0.85)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.08, 0.24, 0.27, 0.98), Color(0.12, 0.88, 0.95, 0.95)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.04, 0.16, 0.18, 1.0), Color(0.7, 0.98, 1.0, 1.0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(callback)
	return button

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_top = 8
	style.content_margin_right = 12
	style.content_margin_bottom = 8
	return style

func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(300, 34)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.88, 0.97, 1.0))
	return label

func _note_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(300, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.58, 0.72, 0.76))
	return label

func _line_edit(placeholder: String, secret: bool) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = secret
	input.custom_minimum_size = Vector2(380, 42)
	input.add_theme_font_size_override("font_size", 16)
	return input

func _build_dynamic_background(root: Control) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in 42:
		var mark := ColorRect.new()
		mark.color = Color(0.05, 0.88, 0.95, 0.22)
		mark.set_anchors_preset(Control.PRESET_CENTER)
		mark.position = Vector2(rng.randf_range(-720, 720), rng.randf_range(-340, 340))
		mark.size = Vector2(rng.randf_range(22, 90), 1.5)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(mark)
		background_marks.append(mark)
		background_speeds.append(rng.randf_range(0.18, 0.72))

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
		"reaction":
			return "反应训练"
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
		if label_text == "准星大小":
			crosshair_size_option = option
		elif label_text == "训练时长":
			duration_option = option
		else:
			difficulty_option = option
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

func _duration_index() -> int:
	match training_duration:
		30:
			return 0
		60:
			return 1
		90:
			return 2
		_:
			return 1

func _difficulty_index() -> int:
	match difficulty:
		"easy":
			return 0
		"normal":
			return 1
		"hard":
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

	countdown_player = AudioStreamPlayer.new()
	countdown_player.name = "CountdownSound"
	countdown_player.stream = _make_countdown_stream()
	add_child(countdown_player)

	combo_player = AudioStreamPlayer.new()
	combo_player.name = "ComboSound"
	combo_player.stream = _make_combo_stream()
	add_child(combo_player)

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

func _make_countdown_stream() -> AudioStreamWAV:
	var duration := 0.13
	var bytes := PackedByteArray()
	var total_samples := int(SAMPLE_RATE * duration)
	for i in total_samples:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 16.0)
		var sample := sin(TAU * 660.0 * t) * 0.24 * env
		_append_i16(bytes, int(clamp(sample, -1.0, 1.0) * 32767.0))
	return _wav(bytes, false)

func _make_combo_stream() -> AudioStreamWAV:
	var duration := 0.24
	var bytes := PackedByteArray()
	var total_samples := int(SAMPLE_RATE * duration)
	for i in total_samples:
		var t := float(i) / SAMPLE_RATE
		var env := exp(-t * 8.0)
		var sample := (sin(TAU * 740.0 * t) + sin(TAU * 990.0 * t)) * 0.18 * env
		_append_i16(bytes, int(clamp(sample, -1.0, 1.0) * 32767.0))
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

extends CanvasLayer

var score := 0
var score_float := 0.0
var shots := 0
var hits := 0
var combo := 0
var best_combo := 0
var tracking_samples := 0
var tracking_on_samples := 0
var tracking_was_on_target := false
var tracking_hit_sound_timer := 0.0
var tracking_combo_timer := 0.0
var last_shot_time := -1.0
var time_left := 60.0
var current_mode := "sixshot"
var training_active := false
var paused := false
var finish_notified := false
var crosshair_scale := 1.0
var crosshair_size_scale := 1.0
var crosshair_color := Color(0.05, 0.92, 1.0, 0.88)
var status_token := 0
var tracking_feedback_timer := 0.0
var reaction_hint_timer := 0.0

var score_label: Label
var time_label: Label
var accuracy_label: Label
var combo_label: Label
var status_label: Label
var mode_hint_label: Label
var crosshair: Control
var crosshair_rects: Array[ColorRect] = []
var player: Node

func _ready() -> void:
	add_to_group("hud")
	visible = false
	_build_hud()
	_update_score()
	_update_accuracy()
	_update_time()

func _process(delta: float) -> void:
	if training_active and not paused:
		time_left = maxf(time_left - delta, 0.0)
		if current_mode == "tracking" or current_mode == "tracking_fast":
			_update_tracking_score(delta)
		elif current_mode == "reaction":
			_update_reaction_hint(delta)
		_update_time()
		if time_left <= 0.0:
			training_active = false
			finish_notified = true
			if player and player.has_method("stop_training"):
				player.stop_training()
			set_status("FINISH")
			var menu := get_tree().get_first_node_in_group("game_menu")
			if menu and menu.has_method("training_finished"):
				menu.training_finished()
	crosshair_scale = lerpf(crosshair_scale, 1.0, delta * 12.0)
	if crosshair:
		crosshair.scale = Vector2.ONE * crosshair_scale * crosshair_size_scale

func is_training_active() -> bool:
	return training_active and not paused

func start_training(mode: String = "sixshot", duration: float = 60.0) -> void:
	score = 0
	score_float = 0.0
	shots = 0
	hits = 0
	combo = 0
	best_combo = 0
	tracking_samples = 0
	tracking_on_samples = 0
	tracking_was_on_target = false
	tracking_hit_sound_timer = 0.0
	tracking_combo_timer = 0.0
	reaction_hint_timer = 0.0
	last_shot_time = -1.0
	time_left = duration
	current_mode = mode
	training_active = true
	paused = false
	finish_notified = false
	visible = true
	set_status("")
	_update_score()
	_update_accuracy()
	_update_combo()
	_update_time()

func stop_training() -> void:
	training_active = false
	paused = false
	visible = false

func set_paused(value: bool) -> void:
	paused = value
	if paused:
		set_status("PAUSED")
	else:
		set_status("")

func record_shot(hit: bool) -> void:
	if not training_active:
		return
	shots += 1
	var now := Time.get_ticks_msec() / 1000.0
	if hit:
		hits += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		var points := _score_for_hit_time(now)
		var bonus := _combo_bonus()
		points += bonus
		score_float += points
		score = int(round(score_float))
		_update_score()
		_update_combo()
		if bonus > 0:
			set_status("+%d COMBO" % points)
			var audio := get_tree().get_first_node_in_group("game_audio")
			if audio and audio.has_method("play_combo"):
				audio.play_combo()
		else:
			set_status("+%d" % points)
		_flash_mode_hint("HIT", Color(0.2, 0.95, 1.0))
	else:
		combo = 0
		score_float -= 1000.0
		score = int(round(score_float))
		_update_score()
		_update_combo()
		set_status("-1000")
		_flash_mode_hint("MISS", Color(1.0, 0.25, 0.22))
	last_shot_time = now
	_update_accuracy()
	_clear_status_later(status_token, 0.65)

func get_score() -> int:
	return score

func get_summary() -> Dictionary:
	return {
		"score": score,
		"shots": shots,
		"hits": hits,
		"accuracy": _current_accuracy(),
		"best_combo": best_combo
	}

func set_status(text: String) -> void:
	if status_label == null:
		return
	status_token += 1
	status_label.text = text
	status_label.modulate.a = 1.0

func _clear_status_later(token: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if training_active and token == status_token:
		status_label.text = ""

func pulse_crosshair() -> void:
	if crosshair == null:
		return
	crosshair_scale = 1.8

func configure_crosshair(color_name: String, size_name: String) -> void:
	crosshair_color = _crosshair_color_from_name(color_name)
	crosshair_size_scale = _crosshair_size_from_name(size_name)
	for rect in crosshair_rects:
		if rect:
			rect.color = crosshair_color
	if crosshair:
		crosshair.scale = Vector2.ONE * crosshair_size_scale

func _update_score() -> void:
	if score_label == null:
		return
	score_label.text = "PTS %06d" % score

func _update_time() -> void:
	if time_label == null:
		return
	var seconds := int(ceil(time_left))
	time_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]

func _update_accuracy() -> void:
	if accuracy_label == null:
		return
	accuracy_label.text = "%d%%" % _current_accuracy()

func _current_accuracy() -> int:
	var accuracy := 0
	if (current_mode == "sixshot" or current_mode == "reaction") and shots > 0:
		accuracy = int(round(float(hits) / float(shots) * 100.0))
	elif current_mode != "sixshot" and tracking_samples > 0:
		accuracy = int(round(float(tracking_on_samples) / float(tracking_samples) * 100.0))
	return accuracy

func _update_combo() -> void:
	if combo_label == null:
		return
	if combo > 1:
		combo_label.text = "COMBO x%d" % combo
	else:
		combo_label.text = ""

func _score_for_hit_time(now: float) -> int:
	if last_shot_time < 0.0:
		return 1200
	var interval := now - last_shot_time
	var t := clampf((interval - 0.15) / (1.35 - 0.15), 0.0, 1.0)
	return int(round(lerpf(1200.0, 800.0, t)))

func _combo_bonus() -> int:
	if combo > 0 and combo % 5 == 0:
		return 350
	return 0

func _update_tracking_score(delta: float) -> void:
	if player == null or not player.has_method("is_aiming_at_tracking_target"):
		return
	var on_target: bool = player.is_aiming_at_tracking_target()
	tracking_samples += 1
	tracking_hit_sound_timer -= delta
	if on_target:
		tracking_on_samples += 1
		score_float += 1000.0 * delta
		tracking_combo_timer += delta
		if tracking_combo_timer >= 0.18:
			tracking_combo_timer = 0.0
			combo += 1
			best_combo = maxi(best_combo, combo)
		if not tracking_was_on_target or tracking_hit_sound_timer <= 0.0:
			var audio := get_tree().get_first_node_in_group("game_audio")
			if audio and audio.has_method("play_hit"):
				audio.play_hit()
			tracking_hit_sound_timer = 0.16
	else:
		score_float -= 450.0 * delta
		tracking_hit_sound_timer = 0.0
		tracking_combo_timer = 0.0
		combo = 0
	tracking_was_on_target = on_target
	score = int(round(score_float))
	_update_score()
	_update_accuracy()
	_update_combo()
	tracking_feedback_timer -= delta
	if tracking_feedback_timer <= 0.0:
		tracking_feedback_timer = 0.3
		if on_target:
			set_status("+")
		else:
			set_status("-")

func _update_reaction_hint(delta: float) -> void:
	reaction_hint_timer -= delta
	if reaction_hint_timer > 0.0 or mode_hint_label == null:
		return
	reaction_hint_timer = 0.28
	var has_visible_target := false
	for target in get_tree().get_nodes_in_group("targets"):
		if target is Node3D and target.visible:
			has_visible_target = true
			break
	if has_visible_target:
		mode_hint_label.text = "READY"
		mode_hint_label.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0))
	else:
		mode_hint_label.text = "WAIT"
		mode_hint_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.82))

func _flash_mode_hint(text: String, color: Color) -> void:
	if mode_hint_label == null:
		return
	mode_hint_label.text = text
	mode_hint_label.add_theme_color_override("font_color", color)
	reaction_hint_timer = 0.45

func _build_hud() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top_group := Control.new()
	top_group.name = "TopStats"
	top_group.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_group.position = Vector2(-285, 8)
	top_group.size = Vector2(570, 34)
	top_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_group)

	var left_bar := ColorRect.new()
	left_bar.color = Color(0.12, 0.11, 0.34, 0.88)
	left_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_bar.position = Vector2(0, 0)
	left_bar.size = Vector2(230, 30)
	top_group.add_child(left_bar)

	score_label = _label("PTS 000000", 17, HORIZONTAL_ALIGNMENT_CENTER)
	score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_label.position = left_bar.position
	score_label.size = left_bar.size
	top_group.add_child(score_label)

	var center_bar := ColorRect.new()
	center_bar.color = Color(0.16, 0.16, 0.24, 0.82)
	center_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_bar.position = Vector2(231, -2)
	center_bar.size = Vector2(108, 34)
	top_group.add_child(center_bar)

	time_label = _label("01:00", 18, HORIZONTAL_ALIGNMENT_CENTER)
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_label.position = center_bar.position
	time_label.size = center_bar.size
	top_group.add_child(time_label)

	var right_bar := ColorRect.new()
	right_bar.color = Color(0.12, 0.11, 0.34, 0.88)
	right_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_bar.position = Vector2(340, 0)
	right_bar.size = Vector2(230, 30)
	top_group.add_child(right_bar)

	accuracy_label = _label("0%", 17, HORIZONTAL_ALIGNMENT_CENTER)
	accuracy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accuracy_label.position = right_bar.position
	accuracy_label.size = right_bar.size
	top_group.add_child(accuracy_label)

	status_label = _label("", 20, HORIZONTAL_ALIGNMENT_CENTER)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.set_anchors_preset(Control.PRESET_CENTER)
	status_label.position = Vector2(-120, 54)
	status_label.size = Vector2(240, 42)
	status_label.add_theme_font_size_override("font_size", 30)
	status_label.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0))
	root.add_child(status_label)

	combo_label = _label("", 18, HORIZONTAL_ALIGNMENT_CENTER)
	combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_label.set_anchors_preset(Control.PRESET_CENTER)
	combo_label.position = Vector2(-110, 95)
	combo_label.size = Vector2(220, 28)
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.38))
	root.add_child(combo_label)

	mode_hint_label = _label("", 16, HORIZONTAL_ALIGNMENT_CENTER)
	mode_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_hint_label.set_anchors_preset(Control.PRESET_CENTER)
	mode_hint_label.position = Vector2(-90, -84)
	mode_hint_label.size = Vector2(180, 28)
	mode_hint_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.82))
	root.add_child(mode_hint_label)

	_build_crosshair(root)

func _build_crosshair(root: Control) -> void:
	crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2.ZERO
	crosshair.size = Vector2(1, 1)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	_add_crosshair_rect(Vector2(-1, -1), Vector2(2, 2))
	_add_crosshair_rect(Vector2(-18, -1), Vector2(8, 2))
	_add_crosshair_rect(Vector2(10, -1), Vector2(8, 2))
	_add_crosshair_rect(Vector2(-1, -18), Vector2(2, 8))
	_add_crosshair_rect(Vector2(-1, 10), Vector2(2, 8))

func _add_crosshair_rect(pos: Vector2, size: Vector2) -> void:
	var rect := ColorRect.new()
	rect.color = crosshair_color
	rect.position = pos
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.add_child(rect)
	crosshair_rects.append(rect)

func _crosshair_color_from_name(color_name: String) -> Color:
	match color_name:
		"white":
			return Color(1.0, 1.0, 1.0, 0.92)
		"red":
			return Color(1.0, 0.1, 0.08, 0.92)
		"blue":
			return Color(0.1, 0.55, 1.0, 0.92)
		_:
			return Color(1.0, 1.0, 1.0, 0.92)

func _crosshair_size_from_name(size_name: String) -> float:
	match size_name:
		"small":
			return 0.75
		"medium":
			return 1.0
		"large":
			return 1.35
		_:
			return 1.0

func _label(text: String, size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

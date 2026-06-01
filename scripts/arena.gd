extends Node3D

const TARGET_SCRIPT := preload("res://scripts/target.gd")
const SPARK_SCRIPT := preload("res://scripts/spark.gd")
const TARGET_COUNT := 6
const TARGET_Z := -10.55
const TARGET_MIN_DISTANCE := 0.95
const TARGET_X_LIMIT := 4.6
const TARGET_Y_MIN := 1.1
const TARGET_Y_MAX := 4.25
const MODE_SIXSHOT := "sixshot"
const MODE_TRACKING := "tracking"
const MODE_TRACKING_FAST := "tracking_fast"
const MODE_REACTION := "reaction"

var wall_mat: StandardMaterial3D
var floor_mat: StandardMaterial3D
var trim_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D
var cyan_mat: StandardMaterial3D
var target_mat: StandardMaterial3D
var impact_mat: StandardMaterial3D
var targets: Array[Area3D] = []
var current_mode := MODE_SIXSHOT
var tracking_target: Area3D
var tracking_velocity := Vector3.ZERO
var tracking_speed := 2.1
var arena_time := 0.0
var pulse_light: OmniLight3D
var target_size_multiplier := 1.0
var speed_multiplier := 1.0

func _ready() -> void:
	_create_materials()
	_build_lighting()
	_build_room()
	var player := get_node_or_null("Player")
	if player:
		player.arena = self

func _process(delta: float) -> void:
	arena_time += delta
	if pulse_light:
		pulse_light.light_energy = 0.75 + abs(sin(arena_time * 1.7)) * 0.65
	if _is_tracking_mode() and _is_training_active():
		_update_tracking_target(delta)

func start_mode(mode: String) -> void:
	current_mode = mode
	_clear_targets()
	if _is_tracking_mode():
		tracking_speed = (3.1 if current_mode == MODE_TRACKING_FAST else 2.1) * speed_multiplier
		_build_tracking_target()
	elif current_mode == MODE_REACTION:
		_build_reaction_target()
	else:
		_build_targets()

func is_click_scoring_mode() -> bool:
	return current_mode == MODE_SIXSHOT or current_mode == MODE_REACTION

func get_mode_name() -> String:
	return current_mode

func set_difficulty(difficulty: String) -> void:
	match difficulty:
		"easy":
			target_size_multiplier = 1.18
			speed_multiplier = 0.82
		"hard":
			target_size_multiplier = 0.82
			speed_multiplier = 1.22
		_:
			target_size_multiplier = 1.0
			speed_multiplier = 1.0

func spawn_impact(point: Vector3, normal: Vector3, hit_target: bool) -> void:
	var mark := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.045 if hit_target else 0.032
	mesh.height = mesh.radius * 2.0
	mark.mesh = mesh
	mark.material_override = cyan_mat if hit_target else impact_mat
	add_child(mark)
	mark.global_position = point + normal.normalized() * 0.035
	_spawn_sparks(point, normal, hit_target)
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(mark.queue_free)

func _create_materials() -> void:
	floor_mat = _mat(Color(0.70, 0.72, 0.70), 0.6)
	wall_mat = _mat(Color(0.48, 0.51, 0.50), 0.72)
	trim_mat = _mat(Color(0.34, 0.37, 0.36), 0.85)
	dark_mat = _mat(Color(0.12, 0.13, 0.14), 0.8)
	impact_mat = _mat(Color(0.04, 0.04, 0.045), 0.9)
	cyan_mat = _mat(Color(0.05, 0.92, 1.0), 0.2, Color(0.0, 0.85, 1.0), 1.4)
	target_mat = _mat(Color(0.08, 0.72, 0.82), 0.3, Color(0.02, 0.65, 0.8), 0.9)

func _mat(albedo: Color, roughness: float, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material

func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.18, 0.20, 0.22)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.78, 0.82)
	environment.ambient_light_energy = 0.8
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "SoftDirectionalLight"
	sun.light_energy = 1.9
	sun.rotation_degrees = Vector3(-52, -32, 0)
	add_child(sun)

	var fill := OmniLight3D.new()
	fill.name = "ArenaFillLight"
	fill.position = Vector3(0, 3.6, 1.5)
	fill.light_energy = 1.3
	fill.omni_range = 18.0
	add_child(fill)

	pulse_light = OmniLight3D.new()
	pulse_light.name = "PulseTrainingLight"
	pulse_light.position = Vector3(0, 2.8, -6.8)
	pulse_light.light_color = Color(0.08, 0.82, 1.0)
	pulse_light.light_energy = 0.85
	pulse_light.omni_range = 7.0
	add_child(pulse_light)

func _build_room() -> void:
	_add_block("Floor", Vector3(0, -0.08, 0), Vector3(18, 0.16, 22), floor_mat)
	_add_block("Ceiling", Vector3(0, 5.25, 0), Vector3(18, 0.28, 22), wall_mat)
	_add_block("BackWall", Vector3(0, 2.55, -10.9), Vector3(18, 5.2, 0.28), wall_mat)
	_add_block("FrontWall", Vector3(0, 2.55, 10.9), Vector3(18, 5.2, 0.28), wall_mat)
	_add_block("LeftWall", Vector3(-8.9, 2.55, 0), Vector3(0.28, 5.2, 22), wall_mat)
	_add_block("RightWall", Vector3(8.9, 2.55, 0), Vector3(0.28, 5.2, 22), wall_mat)
	_add_block("TargetRail", Vector3(0, 0.95, -10.2), Vector3(14.5, 0.2, 0.5), trim_mat)
	_add_grid_lines()

func _add_grid_lines() -> void:
	for x in range(-8, 9):
		_add_visual_box("FloorLineX", Vector3(float(x), 0.006, 0), Vector3(0.018, 0.018, 21.5), dark_mat)
	for z in range(-10, 11):
		_add_visual_box("FloorLineZ", Vector3(0, 0.008, float(z)), Vector3(17.5, 0.018, 0.018), dark_mat)
	for x in range(-8, 9):
		_add_visual_box("BackWallVLine", Vector3(float(x), 2.65, -10.74), Vector3(0.018, 5.0, 0.018), trim_mat)
	for y in range(1, 6):
		_add_visual_box("BackWallHLine", Vector3(0, float(y), -10.73), Vector3(17.5, 0.018, 0.018), trim_mat)

func _build_targets() -> void:
	for i in TARGET_COUNT:
		_add_target("Target%02d" % i, _random_target_position())

func get_next_target_position(target: Area3D) -> Vector3:
	return _random_target_position(target)

func get_target_respawn_delay(_target: Area3D) -> float:
	if current_mode == MODE_REACTION:
		return randf_range(0.35, 1.05)
	return 0.18

func _random_target_position(ignore_target: Area3D = null) -> Vector3:
	for attempt in 80:
		var candidate := Vector3(
			randf_range(-TARGET_X_LIMIT, TARGET_X_LIMIT),
			randf_range(TARGET_Y_MIN, TARGET_Y_MAX),
			TARGET_Z
		)
		if _is_target_position_clear(candidate, ignore_target):
			return candidate
	return Vector3(randf_range(-TARGET_X_LIMIT, TARGET_X_LIMIT), randf_range(TARGET_Y_MIN, TARGET_Y_MAX), TARGET_Z)

func _is_target_position_clear(candidate: Vector3, ignore_target: Area3D) -> bool:
	for target in targets:
		if target == ignore_target:
			continue
		if not is_instance_valid(target):
			continue
		if candidate.distance_to(target.global_position) < TARGET_MIN_DISTANCE:
			return false
	return true

func _add_target(node_name: String, position: Vector3) -> void:
	var target := Area3D.new()
	target.name = node_name
	target.script = TARGET_SCRIPT
	target.score_value = 100
	target.spawn_origin = position
	target.arena = self
	target.hit_material = cyan_mat
	target.idle_material = target_mat
	target.add_to_group("targets")
	add_child(target)
	targets.append(target)
	target.global_position = position

	var mesh := MeshInstance3D.new()
	mesh.name = "TargetMesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.24 * target_size_multiplier
	sphere.height = 0.48 * target_size_multiplier
	mesh.mesh = sphere
	mesh.material_override = target_mat
	target.add_child(mesh)

	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.25 * target_size_multiplier
	shape.shape = sphere_shape
	target.add_child(shape)

	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(0.1, 0.95, 1.0)
	glow.light_energy = 0.18
	glow.omni_range = 1.4
	target.add_child(glow)

func _build_reaction_target() -> void:
	_add_target("ReactionTarget", _random_target_position())
	if targets.size() > 0:
		var target := targets[0]
		target.scale = Vector3.ONE * 1.12
		var mesh := target.get_node_or_null("TargetMesh") as MeshInstance3D
		if mesh:
			var sphere := SphereMesh.new()
			sphere.radius = 0.32 * target_size_multiplier
			sphere.height = 0.64 * target_size_multiplier
			mesh.mesh = sphere
		var shape := target.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape and shape.shape is SphereShape3D:
			(shape.shape as SphereShape3D).radius = 0.34 * target_size_multiplier

func _build_tracking_target() -> void:
	tracking_target = Area3D.new()
	tracking_target.name = "TrackingTarget"
	tracking_target.add_to_group("targets")
	tracking_target.add_to_group("tracking_target")
	add_child(tracking_target)
	targets.append(tracking_target)
	tracking_target.global_position = Vector3(0.0, 2.65, TARGET_Z)
	tracking_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-0.7, 0.7), 0.0).normalized() * tracking_speed

	var mesh := MeshInstance3D.new()
	mesh.name = "TrackingTargetMesh"
	var sphere := SphereMesh.new()
	sphere.radius = 0.32 * target_size_multiplier
	sphere.height = 0.64 * target_size_multiplier
	mesh.mesh = sphere
	mesh.material_override = cyan_mat
	tracking_target.add_child(mesh)

	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.34 * target_size_multiplier
	shape.shape = sphere_shape
	tracking_target.add_child(shape)

	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.light_color = Color(0.1, 0.95, 1.0)
	glow.light_energy = 0.42
	glow.omni_range = 2.1
	tracking_target.add_child(glow)

func _update_tracking_target(delta: float) -> void:
	if tracking_target == null or not is_instance_valid(tracking_target):
		return
	var pos := tracking_target.global_position + tracking_velocity * delta
	if pos.x < -TARGET_X_LIMIT or pos.x > TARGET_X_LIMIT:
		tracking_velocity.x *= -1.0
		pos.x = clampf(pos.x, -TARGET_X_LIMIT, TARGET_X_LIMIT)
	if pos.y < TARGET_Y_MIN or pos.y > TARGET_Y_MAX:
		tracking_velocity.y *= -1.0
		pos.y = clampf(pos.y, TARGET_Y_MIN, TARGET_Y_MAX)
	if randf() < delta * 0.85:
		var turn := Vector3(randf_range(-0.8, 0.8), randf_range(-0.65, 0.65), 0.0)
		tracking_velocity = (tracking_velocity.normalized() + turn).normalized() * tracking_speed
	tracking_target.global_position = pos
	tracking_target.scale = Vector3.ONE * (1.0 + sin(arena_time * 8.0) * 0.045)

func _clear_targets() -> void:
	for target in targets:
		if is_instance_valid(target):
			target.queue_free()
	targets.clear()
	tracking_target = null

func _is_tracking_mode() -> bool:
	return current_mode == MODE_TRACKING or current_mode == MODE_TRACKING_FAST

func _is_training_active() -> bool:
	var hud := get_tree().get_first_node_in_group("hud")
	return hud and hud.has_method("is_training_active") and hud.is_training_active()

func _add_block(node_name: String, position: Vector3, size: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.add_to_group("bullet_surface")
	add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _add_visual_box(node_name: String, position: Vector3, size: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	add_child(mesh_instance)

func _spawn_sparks(point: Vector3, normal: Vector3, hit_target: bool) -> void:
	var count := 9 if hit_target else 5
	for i in count:
		var spark := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.025
		mesh.height = 0.05
		spark.mesh = mesh
		spark.material_override = cyan_mat if hit_target else floor_mat
		spark.script = SPARK_SCRIPT
		add_child(spark)
		spark.global_position = point + normal * 0.06
		var jitter := Vector3(randf_range(-0.8, 0.8), randf_range(-0.35, 0.9), randf_range(-0.8, 0.8))
		spark.velocity = (normal + jitter).normalized() * randf_range(2.0, 5.0)
		spark.life = randf_range(0.18, 0.38)

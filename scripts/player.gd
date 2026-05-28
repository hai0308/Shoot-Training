extends CharacterBody3D

@export var mouse_sensitivity := 0.0022
@export var fire_rate := 0.13
@export var ray_distance := 90.0

var arena: Node
var active := false
var sensitivity_multiplier := 1.0
var pitch := 0.0
var next_shot_time := 0.0
var weapon_base_position := Vector3.ZERO
var recoil := 0.0
var bob_time := 0.0

@onready var camera: Camera3D = $Camera3D
@onready var gun_pivot: Node3D = $Camera3D/GunPivot
@onready var hud: CanvasLayer = $"../HUD"

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	weapon_base_position = gun_pivot.position
	_build_weapon()

func start_training(multiplier: float) -> void:
	active = true
	sensitivity_multiplier = multiplier
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func stop_training() -> void:
	active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var actual_sensitivity := mouse_sensitivity * sensitivity_multiplier
		rotate_y(-event.relative.x * actual_sensitivity)
		pitch = clamp(pitch - event.relative.y * actual_sensitivity, deg_to_rad(-84), deg_to_rad(84))
		camera.rotation.x = pitch
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_shoot()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			var menu := get_tree().get_first_node_in_group("game_menu")
			if menu and menu.has_method("pause_game"):
				menu.pause_game()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_update_weapon(delta)

func _shoot() -> void:
	if hud and hud.has_method("is_training_active") and not hud.is_training_active():
		return
	if arena and arena.has_method("is_click_scoring_mode") and not arena.is_click_scoring_mode():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < next_shot_time:
		return

	next_shot_time = now + fire_rate
	recoil = min(recoil + 0.12, 0.32)
	var audio := get_tree().get_first_node_in_group("game_audio")
	if audio and audio.has_method("play_shot"):
		audio.play_shot()
	if hud:
		hud.pulse_crosshair()

	var origin := camera.global_position
	var end := origin + -camera.global_transform.basis.z * ray_distance
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [self]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var hit_target := false
	if hit:
		var collider: Object = hit.collider
		if collider and collider.has_method("take_hit"):
			hit_target = collider.take_hit(hit.position, hit.normal)
		if arena and arena.has_method("spawn_impact"):
			arena.spawn_impact(hit.position, hit.normal, hit_target)
	if hit_target and audio and audio.has_method("play_hit"):
		audio.play_hit()
	if hud and hud.has_method("record_shot"):
		hud.record_shot(hit_target)

func is_aiming_at_tracking_target() -> bool:
	if not active:
		return false
	var origin := camera.global_position
	var end := origin + -camera.global_transform.basis.z * ray_distance
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [self]
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit:
		return false
	var collider: Object = hit.collider
	return collider is Node and collider.is_in_group("tracking_target")

func _update_weapon(delta: float) -> void:
	recoil = lerpf(recoil, 0.0, delta * 10.0)
	var bob := Vector3(sin(Time.get_ticks_msec() * 0.004) * 0.004, cos(Time.get_ticks_msec() * 0.003) * 0.004, 0.0)
	gun_pivot.position = weapon_base_position + bob + Vector3(0.0, -recoil * 0.35, recoil * 0.42)
	gun_pivot.rotation_degrees.x = -recoil * 28.0

func _build_weapon() -> void:
	gun_pivot.scale = Vector3.ONE * 0.78
	gun_pivot.position += Vector3(0.06, -0.05, 0.08)
	var slide_mat := _make_material(Color(0.022, 0.025, 0.026), 0.34, 0.72)
	var frame_mat := _make_material(Color(0.012, 0.013, 0.014), 0.62, 0.28)
	var grip_mat := _make_material(Color(0.018, 0.019, 0.018), 0.82, 0.08)
	var edge_mat := _make_material(Color(0.11, 0.12, 0.12), 0.44, 0.38)
	var black_mat := _make_material(Color(0.002, 0.002, 0.002), 0.72, 0.15)
	var sight_mat := _make_material(Color(0.82, 0.86, 0.78), 0.5, 0.0)
	var glove_mat := _make_material(Color(0.018, 0.019, 0.018), 0.9, 0.0)
	var sleeve_mat := _make_material(Color(0.035, 0.038, 0.037), 0.95, 0.0)

	_add_box(gun_pivot, "Slide", Vector3(0.0, 0.045, -0.04), Vector3(0.26, 0.18, 0.72), slide_mat)
	_add_box(gun_pivot, "SlideTopFlat", Vector3(0.0, 0.155, -0.04), Vector3(0.18, 0.035, 0.62), edge_mat)
	_add_box(gun_pivot, "SlideFrontFace", Vector3(0.0, 0.04, -0.43), Vector3(0.245, 0.155, 0.045), black_mat)
	_add_box(gun_pivot, "MuzzleShadow", Vector3(0.0, 0.038, -0.462), Vector3(0.105, 0.09, 0.024), black_mat)
	_add_cylinder(gun_pivot, "Barrel", Vector3(0.0, 0.04, -0.49), 0.045, 0.16, edge_mat, Vector3(90, 0, 0))
	_add_cylinder(gun_pivot, "BarrelBore", Vector3(0.0, 0.04, -0.575), 0.026, 0.018, black_mat, Vector3(90, 0, 0))

	_add_box(gun_pivot, "Frame", Vector3(0.0, -0.105, 0.03), Vector3(0.22, 0.115, 0.52), frame_mat)
	_add_box(gun_pivot, "DustCover", Vector3(0.0, -0.06, -0.24), Vector3(0.2, 0.08, 0.28), frame_mat)
	_add_box(gun_pivot, "AccessoryRail", Vector3(0.0, -0.125, -0.22), Vector3(0.19, 0.028, 0.24), edge_mat)
	_add_box(gun_pivot, "MagazineWell", Vector3(0.0, -0.345, 0.14), Vector3(0.2, 0.08, 0.2), frame_mat, Vector3(-12, 0, 0))
	_add_box(gun_pivot, "GripCore", Vector3(0.0, -0.32, 0.19), Vector3(0.205, 0.43, 0.18), grip_mat, Vector3(-12, 0, 0))
	_add_box(gun_pivot, "GripBackstrap", Vector3(0.0, -0.305, 0.285), Vector3(0.21, 0.34, 0.045), black_mat, Vector3(-12, 0, 0))
	_add_box(gun_pivot, "MagazineBase", Vector3(0.0, -0.535, 0.135), Vector3(0.24, 0.055, 0.24), edge_mat, Vector3(-12, 0, 0))

	_add_box(gun_pivot, "EjectionPort", Vector3(0.0, 0.16, -0.11), Vector3(0.13, 0.024, 0.145), black_mat)
	_add_box(gun_pivot, "Chamber", Vector3(0.0, 0.171, -0.11), Vector3(0.085, 0.018, 0.1), edge_mat)
	_add_box(gun_pivot, "RearSightBlock", Vector3(0.0, 0.18, 0.27), Vector3(0.145, 0.06, 0.055), black_mat)
	_add_box(gun_pivot, "RearSightNotch", Vector3(0.0, 0.216, 0.27), Vector3(0.052, 0.025, 0.06), sight_mat)
	_add_box(gun_pivot, "FrontSight", Vector3(0.0, 0.18, -0.335), Vector3(0.052, 0.06, 0.045), black_mat)
	_add_box(gun_pivot, "FrontSightDot", Vector3(0.0, 0.218, -0.335), Vector3(0.024, 0.018, 0.018), sight_mat)

	for side in [-1.0, 1.0]:
		_add_box(gun_pivot, "SlideSidePanel", Vector3(side * 0.136, 0.045, -0.04), Vector3(0.018, 0.145, 0.61), edge_mat)
		_add_box(gun_pivot, "GripPanel", Vector3(side * 0.112, -0.32, 0.18), Vector3(0.024, 0.31, 0.13), black_mat, Vector3(-12, 0, 0))
		for i in 5:
			_add_box(
				gun_pivot,
				"RearSerration",
				Vector3(side * 0.151, 0.052, 0.165 + float(i) * 0.035),
				Vector3(0.018, 0.13, 0.012),
				black_mat,
				Vector3(0, 0, side * 18.0)
			)
		for i in 4:
			_add_box(
				gun_pivot,
				"GripGroove",
				Vector3(side * 0.128, -0.205 - float(i) * 0.055, 0.112),
				Vector3(0.016, 0.014, 0.14),
				edge_mat,
				Vector3(-12, 0, side * 12.0)
			)

	_add_box(gun_pivot, "TriggerGuardFront", Vector3(0.0, -0.205, -0.075), Vector3(0.19, 0.045, 0.035), frame_mat)
	_add_box(gun_pivot, "TriggerGuardBottom", Vector3(0.0, -0.265, 0.005), Vector3(0.18, 0.035, 0.18), frame_mat)
	_add_box(gun_pivot, "TriggerGuardRear", Vector3(0.0, -0.22, 0.095), Vector3(0.17, 0.08, 0.035), frame_mat)
	_add_box(gun_pivot, "Trigger", Vector3(0.0, -0.23, 0.025), Vector3(0.055, 0.13, 0.04), black_mat, Vector3(-18, 0, 0))
	_add_box(gun_pivot, "SlideStop", Vector3(-0.145, -0.045, 0.05), Vector3(0.02, 0.028, 0.15), edge_mat)
	_add_box(gun_pivot, "TakeDownLever", Vector3(-0.145, -0.06, -0.16), Vector3(0.02, 0.024, 0.09), edge_mat)

	_add_capsule(gun_pivot, "RightForearm", Vector3(0.13, -0.58, 0.35), Vector3(74, -3, -8), sleeve_mat, 0.105, 0.78)
	_add_capsule(gun_pivot, "RightGlove", Vector3(0.02, -0.39, 0.20), Vector3(78, 0, -6), glove_mat, 0.09, 0.42)
	_add_capsule(gun_pivot, "LeftGlove", Vector3(-0.18, -0.43, 0.10), Vector3(70, -22, 18), glove_mat, 0.082, 0.38)
	_add_capsule(gun_pivot, "LeftForearm", Vector3(-0.31, -0.64, 0.25), Vector3(67, -28, 20), sleeve_mat, 0.095, 0.62)

func _make_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat

func _add_box(parent: Node, node_name: String, pos: Vector3, size: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rot
	parent.add_child(mesh_instance)

func _add_cylinder(parent: Node, node_name: String, pos: Vector3, radius: float, height: float, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rot
	parent.add_child(mesh_instance)

func _add_capsule(parent: Node, node_name: String, pos: Vector3, rot: Vector3, mat: Material, radius: float = 0.075, height: float = 0.42) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	mesh_instance.mesh = mesh
	mesh_instance.material_override = mat
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = rot
	parent.add_child(mesh_instance)

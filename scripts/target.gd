extends Area3D

@export var score_value := 500

var arena: Node
var spawn_origin := Vector3.ZERO
var idle_material: Material
var hit_material: Material
var alive := true
var mesh_instance: MeshInstance3D

func _ready() -> void:
	call_deferred("_cache_mesh")

func _cache_mesh() -> void:
	mesh_instance = get_node_or_null("TargetMesh") as MeshInstance3D

func take_hit(_point: Vector3, _normal: Vector3) -> bool:
	if not alive:
		return false
	alive = false
	_cache_mesh()
	if mesh_instance and hit_material:
		mesh_instance.material_override = hit_material
	_hide_and_respawn()
	return true

func _hide_and_respawn() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 1.65, 0.08)
	tween.tween_property(self, "scale", Vector3.ZERO, 0.18)
	await tween.finished
	monitorable = false
	visible = false
	await get_tree().create_timer(0.18).timeout
	if arena and arena.has_method("get_next_target_position"):
		spawn_origin = arena.get_next_target_position(self)
	global_position = spawn_origin
	scale = Vector3.ONE
	visible = true
	monitorable = true
	alive = true
	if mesh_instance and idle_material:
		mesh_instance.material_override = idle_material

extends MeshInstance3D

var velocity := Vector3.ZERO
var life := 0.25
var age := 0.0

func _process(delta: float) -> void:
	age += delta
	velocity.y -= 7.0 * delta
	global_position += velocity * delta
	var t: float = clamp(1.0 - age / life, 0.0, 1.0)
	scale = Vector3.ONE * t
	if age >= life:
		queue_free()

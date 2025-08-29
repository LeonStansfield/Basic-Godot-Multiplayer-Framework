extends RigidBody3D

@export var sync_rate := 0.05
var _sync_timer := 0.0

func _ready():
	if not is_multiplayer_authority():
		set_physics_process(false)

func _physics_process(delta):
	if is_multiplayer_authority():
		_sync_timer += delta
		if _sync_timer >= sync_rate:
			_sync_timer = 0.0
			sync_state.rpc(global_transform, linear_velocity, angular_velocity)

@rpc("any_peer", "unreliable")
func sync_state(t: Transform3D, lin_vel: Vector3, ang_vel: Vector3):
	if not is_multiplayer_authority():
		global_transform = t
		linear_velocity = lin_vel
		angular_velocity = ang_vel


func _on_despawn_timer_timeout():
	queue_free()

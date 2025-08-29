extends RigidBody3D

var forward_impulse: float = 10.0
var net_ready: bool = false
var networked_object_id: String = ""

@export var sync_rate := 0.05
var _sync_timer := 0.0

# When adding networked objects, things that would normally be called in ready should be called here
# This is to ensure all the normal 'ready' behavior occurs on all instances of the object across all clients
func network_ready() -> void:
	net_ready = true
	apply_forward_impulse()

# Function used to set network ready. 
# This is needed as when deleting objects, set network ready needs to be set to false 
# so its network code wont run between first being despawned and then actually despawned on all clients.
func _set_network_ready(v: bool) -> void:
	net_ready = v

func _ready():
	if not is_multiplayer_authority():
		set_physics_process(false)

func apply_forward_impulse():
	if is_multiplayer_authority():
		apply_central_impulse(-transform.basis.z * forward_impulse)

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

# When despawning objects, ensure you call the network manager to clean up all instances of the object
# Then you can call queue free deffered to ensure it is deleted on all other clients first.
func _on_despawn_timer_timeout():
	if multiplayer.is_server():
		var network_manager = get_tree().get_root().get_node("NetworkManager")
		if networked_object_id != "":
			network_manager.despawn_networked_object(networked_object_id) # Ensure network manager deletes all clients objects
	
	call_deferred("queue_free") # Delete object locally next frame

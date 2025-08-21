extends CharacterBody3D

@export var speed: float = 5.0
var net_ready: bool = false

func set_network_ready(v: bool) -> void:
	net_ready = v

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority() and net_ready:
		var direction: Vector3 = Vector3.ZERO
		
		if Input.is_action_pressed("move_forward"):
			direction.z -= 1.0
		if Input.is_action_pressed("move_back"):
			direction.z += 1.0
		if Input.is_action_pressed("move_left"):
			direction.x -= 1.0
		if Input.is_action_pressed("move_right"):
			direction.x += 1.0
		
		velocity.x = direction.normalized().x * speed
		velocity.z = direction.normalized().z * speed
		move_and_slide()
		
		# Send the local player's transform to all other peers.
		update_position.rpc(global_transform)

@rpc("any_peer", "unreliable")
func update_position(new_transform: Transform3D) -> void:
	# Only update the position if the player is not the authority for this node.
	if not is_multiplayer_authority():
		global_transform = new_transform

extends CharacterBody3D

@export var speed: float = 5.0
@onready var cam: Camera3D = get_node_or_null("Camera3D")

func _ready():
	# Camera is optional; only enable on local authority
	if cam:
		cam.current = is_multiplayer_authority()

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		var dir := Vector3.ZERO
		if Input.is_action_pressed("move_forward"): dir.z -= 1.0
		if Input.is_action_pressed("move_back"):    dir.z += 1.0
		if Input.is_action_pressed("move_left"):    dir.x -= 1.0
		if Input.is_action_pressed("move_right"):   dir.x += 1.0
		dir = dir.normalized()

		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		move_and_slide()

		# Broadcast our transform to everyone (unreliable is fine for movement)
		update_position.rpc(global_transform)

@rpc("any_peer", "unreliable")
func update_position(new_transform: Transform3D) -> void:
	# Only remote proxies should apply incoming transforms
	if !is_multiplayer_authority():
		global_transform = new_transform

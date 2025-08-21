extends CharacterBody3D

@export var speed: float = 5.0
@onready var cam = $Camera3D

func _ready():
	# Disable camera for remote players
	if !is_multiplayer_authority():
		if cam:
			cam.current = false

func _physics_process(delta):
	if is_multiplayer_authority():  # Only local player controls movement
		var dir = Vector3.ZERO
		if Input.is_action_pressed("move_forward"): dir.z -= 1
		if Input.is_action_pressed("move_back"): dir.z += 1
		if Input.is_action_pressed("move_left"): dir.x -= 1
		if Input.is_action_pressed("move_right"): dir.x += 1

		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		move_and_slide()

		# Send transform to others
		update_position.rpc(global_transform)

@rpc("any_peer", "unreliable")
func update_position(new_transform: Transform3D):
	if !is_multiplayer_authority():
		global_transform = new_transform

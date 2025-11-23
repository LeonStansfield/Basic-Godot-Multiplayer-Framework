extends RigidBody3D
 
var forward_impulse: float = 10.0
 
func _ready():
	if is_multiplayer_authority():
		apply_central_impulse(-transform.basis.z * forward_impulse)

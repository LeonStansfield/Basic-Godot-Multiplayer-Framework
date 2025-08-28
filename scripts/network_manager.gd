extends Node

signal hosting_started
signal hosting_failed(err_code: int)
signal connecting_started(ip: String)
signal connected
signal connection_failed
signal disconnected

@export var spawn_root: NodePath   # Assign to a Node3D in editor (e.g., "SpawnRoot")

const PORT: int = 12345
const MAX_PLAYERS: int = 4

# ===========================
# Registry for spawnable objects
# ===========================
var spawnable_scenes: Dictionary = {  # Register types here
	"player": preload("res://Prefabs/player.tscn"),
	"ball": preload("res://Prefabs/ball.tscn")
}

# Tracks all spawned objects: { object_id: { "type": String, "node": Node } }
var networked_objects: Dictionary = {}

var _spawn_root_node: Node

func _ready() -> void:
	_spawn_root_node = get_node(spawn_root)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# ======================
# SERVER / CLIENT SETUP
# ======================
func host_game() -> Error:
	reset_game_state()

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		printerr("Failed to host server: ", err)
		emit_signal("hosting_failed", err)
		return err

	multiplayer.multiplayer_peer = peer
	print("Hosting server on port %d" % PORT)
	emit_signal("hosting_started")

	# Host spawns themselves immediately as a player
	spawn_networked_object("player", str(multiplayer.get_unique_id()), multiplayer.get_unique_id())
	return OK

func join_game(ip: String) -> Error:
	var addr := ip.strip_edges()
	if addr == "" or (addr != "localhost" and not ip.is_valid_ip_address()):
		printerr("Join refused: invalid IP/hostname '%s'" % addr)
		return ERR_INVALID_PARAMETER

	reset_game_state()

	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(addr, PORT)
	if err != OK:
		printerr("Failed to create client peer: ", err)
		return err

	multiplayer.multiplayer_peer = peer
	print("Connecting to %s:%d..." % [addr, PORT])
	emit_signal("connecting_started", addr)
	return OK


func exit_game() -> void:
	_close_peer()
	reset_game_state()
	emit_signal("disconnected")

# ======================
# CONNECTION EVENTS
# ======================
func _on_connected_to_server() -> void:
	print("Connected to server")
	emit_signal("connected")

func _on_connection_failed() -> void:
	print("Connection failed")
	_close_peer()
	reset_game_state()
	emit_signal("connection_failed")

func _on_server_disconnected() -> void:
	print("Disconnected from server")
	_close_peer()
	reset_game_state()
	emit_signal("disconnected")

# ======================
# PEER EVENTS (server-side spawning)
# ======================
func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)

	if multiplayer.is_server():
		var spawn_pos = _spawn_root_node.global_position + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
		spawn_networked_object("player", str(id), id, spawn_pos)

		# Tell the new peer about all existing objects
		for object_id in networked_objects.keys():
			var rec = networked_objects[object_id]
			var node: Node = rec.node
			var obj_type: String = rec.type
			var auth: int = node.get_multiplayer_authority()
			var pos: Vector3 = node.global_position if node is Node3D else Vector3.ZERO
			rpc_id(id, "spawn_remote_object", obj_type, object_id, auth, pos)

		# Tell all existing peers about the new player's object
		for peer_id in multiplayer.get_peers():
			if peer_id != id:
				rpc_id(peer_id, "spawn_remote_object", "player", str(id), id, spawn_pos)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	if multiplayer.is_server():
		# Remove their player object
		despawn_networked_object(str(id))
		rpc("despawn_remote_object", str(id))

# ======================
# GENERIC NETWORKED OBJECT MANAGEMENT
# ======================
func spawn_networked_object(object_type: String, object_id: String, authority: int = 1, position: Vector3 = Vector3.ZERO) -> void:
	if not spawnable_scenes.has(object_type):
		printerr("Unknown object type: %s" % object_type)
		return

	if networked_objects.has(object_id):
		despawn_networked_object(object_id)

	var scene: PackedScene = spawnable_scenes[object_type]
	var node: Node = scene.instantiate()
	node.name = "%s_%s" % [object_type.capitalize(), object_id]
	_spawn_root_node.add_child(node)

	node.set_multiplayer_authority(authority)

	if node is Node3D:
		if position != Vector3.ZERO:
			node.global_position = position
		elif multiplayer.is_server():
			var random_offset = Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
			node.global_position = _spawn_root_node.global_position + random_offset

	if node.has_method("set_network_ready"):
		node.call("set_network_ready", true)

	networked_objects[object_id] = { "type": object_type, "node": node }
	print("Spawned %s with ID %s (authority: %d) at %s" % [object_type, object_id, authority, node.global_position])

@rpc("any_peer", "reliable")
func spawn_remote_object(object_type: String, object_id: String, authority: int, position: Vector3) -> void:
	spawn_networked_object(object_type, object_id, authority, position)

func despawn_networked_object(object_id: String) -> void:
	if networked_objects.has(object_id):
		var node: Node = networked_objects[object_id].node
		if is_instance_valid(node):
			node.queue_free()
		networked_objects.erase(object_id)


@rpc("any_peer", "reliable")
func despawn_remote_object(object_id: String) -> void:
	despawn_networked_object(object_id)

# ======================
# RESET/CLEANUP
# ======================
func reset_game_state() -> void:
	for id in networked_objects.keys():
		var node: Node = networked_objects[id].node
		if is_instance_valid(node):
			node.queue_free()
	networked_objects.clear()
	print("Game state reset")

func _close_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		var p := multiplayer.multiplayer_peer
		multiplayer.multiplayer_peer = null
		if p is ENetMultiplayerPeer:
			(p as ENetMultiplayerPeer).close()

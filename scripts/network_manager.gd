extends Node

signal hosting_started
signal hosting_failed(err_code: int)
signal connecting_started(ip: String)
signal connected
signal connection_failed
signal disconnected

const PORT: int = 8080
const MAX_PLAYERS: int = 16

# Registry for spawnable objects
var spawnable_scenes: Dictionary = {  # Register types here
	"player": preload("res://Prefabs/player.tscn"),
	"ball": preload("res://Prefabs/ball.tscn")
}

# Tracks all spawned objects: { object_id: { "type": String, "node": Node } }
var networked_objects: Dictionary = {}

var spawn_root: Node3D

func _ready() -> void:
	spawn_root = Node3D.new()
	spawn_root.name = "SpawnRoot"
	add_child(spawn_root)

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# SERVER / CLIENT SETUP
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

	# Spawn the host's player object. We'll give them a small offset to start with.
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var spawn_offset = Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
	var host_spawn_pos = spawn_root.global_position + spawn_offset
	spawn_networked_object("player", str(multiplayer.get_unique_id()), multiplayer.get_unique_id(), host_spawn_pos, Vector3.ZERO, Vector3.ONE, false)
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

# CONNECTION EVENTS
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

# PEER EVENTS (server-side spawning)
func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)

	if multiplayer.is_server():
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		var spawn_offset = Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
		var spawn_pos = spawn_root.global_position + spawn_offset
		# Spawn server-side but don't announce here (we will explicitly tell peers below)
		spawn_networked_object("player", str(id), id, spawn_pos, Vector3.ZERO, Vector3.ONE, false)

		# 1) Tell the new peer about ALL existing objects (including this new player's object)
		for object_id in networked_objects.keys():
			var rec = networked_objects[object_id]
			var node: Node = rec.node
			var obj_type: String = rec.type
			var auth: int = node.get_multiplayer_authority()
			var pos: Vector3 = node.global_position if node is Node3D else Vector3.ZERO
			rpc_id(id, "spawn_remote_object", obj_type, object_id, auth, pos, Vector3.ZERO, Vector3.ONE)

		# 2) Tell all existing peers about the new player's object (avoid sending to the newly-connected peer)
		for peer_id in multiplayer.get_peers():
			if peer_id != id:
				rpc_id(peer_id, "spawn_remote_object", "player", str(id), id, spawn_pos, Vector3.ZERO, Vector3.ONE)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	if multiplayer.is_server():
		# Remove their player object
		despawn_networked_object(str(id))
		rpc("despawn_remote_object", str(id))

# GENERIC NETWORKED OBJECT MANAGEMENT
func spawn_networked_object(object_type: String, object_id: String, authority: int = 1, position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE, announce: bool = true) -> void:
	# Check if the object type is valid
	if not spawnable_scenes.has(object_type):
		printerr("Unknown object type: %s" % object_type)
		return

	if networked_objects.has(object_id): # If the object already exists, despawn it before spawning a new one
		despawn_networked_object(object_id)

	# Create the new object
	var scene: PackedScene = spawnable_scenes[object_type]
	var node: Node = scene.instantiate()
	node.name = "%s_%s" % [object_type.capitalize(), object_id]
	spawn_root.add_child(node)
	
	# Set transforms
	if node is Node3D:
		node.global_position = position
		node.rotation_degrees = rotation
		node.scale = scale

	# Set ID
	if node.networked_object_id != null:
		node.networked_object_id = object_id

	node.set_multiplayer_authority(authority)

	# Call network_ready now objects are initialised
	if node.has_method("network_ready"):
		node.call("network_ready")

	networked_objects[object_id] = { "type": object_type, "node": node }
	print("Spawned %s with ID %s (authority: %d) at position: %s rotation: %s scale: %s " % [object_type, object_id, authority, node.global_position, node.rotation_degrees, node.scale])

	# Announce the new object to all peers
	if multiplayer.is_server() and announce:
		for peer_id in multiplayer.get_peers():
			rpc_id(peer_id, "spawn_remote_object", object_type, object_id, authority, node.global_position, node.rotation_degrees, node.scale)

@rpc("any_peer", "reliable")
func spawn_remote_object(object_type: String, object_id: String, authority: int, position: Vector3, rotation: Vector3, scale: Vector3) -> void:
	spawn_networked_object(object_type, object_id, authority, position, rotation, scale)

func despawn_networked_object(object_id: String) -> void:
	if networked_objects.has(object_id):
		var node: Node = networked_objects[object_id].node
		if node.has_method("_set_network_ready"):
			node.call("_set_network_ready", false)
		networked_objects.erase(object_id)  # Remove reference first
		if is_instance_valid(node) and is_instance_valid(node):
			node.call_deferred("queue_free") # Call queue free on the next frame

@rpc("any_peer", "reliable")
func despawn_remote_object(object_id: String) -> void:
	despawn_networked_object(object_id)

# RESET/CLEANUP
func reset_game_state() -> void:
	print("Resetting game state...")
	
	# Make a copy of keys
	var object_ids = networked_objects.keys()
	for id in object_ids:
		var rec = networked_objects.get(id, null)
		if rec != null:
			var node: Node = rec.node
			if is_instance_valid(node) and is_instance_valid(node):
				if node.has_method("_set_network_ready"):
					node.call("_set_network_ready", false)
				# Use deferred call to delete on the next frame
				node.call_deferred("queue_free")
	
	# Clear after freeing requests have been queued
	networked_objects.clear()

func _close_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		var p := multiplayer.multiplayer_peer
		multiplayer.multiplayer_peer = null
		if p is ENetMultiplayerPeer:
			(p as ENetMultiplayerPeer).close()

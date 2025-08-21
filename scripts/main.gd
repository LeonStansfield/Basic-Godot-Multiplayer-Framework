extends Node

@onready var ip_input: LineEdit = $Control/IPAddress
@onready var host_button: Button = $Control/Host
@onready var join_button: Button = $Control/Join
@onready var exit_button: Button = $Control/Exit
@onready var start_area: Node3D = $SpawnPoint

const PORT: int = 12345
const MAX_PLAYERS: int = 4
var player_scene: PackedScene = preload("res://Prefabs/player.tscn")

var players: Dictionary = {}

func _ready() -> void:
	host_button.pressed.connect(host_game)
	join_button.pressed.connect(join_game)
	exit_button.pressed.connect(exit_game)

	ip_input.text_changed.connect(_on_ip_text_changed)
	update_join_button_state()

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_ip_text_changed(new_text: String) -> void:
	update_join_button_state()

func update_join_button_state() -> void:
	join_button.disabled = ip_input.text.strip_edges() == ""

func host_game() -> void:
	reset_game_state()
	_show_game_ui(true)
	
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		printerr("Failed to create server peer: ", error)
		_show_game_ui(false)
		return
	
	multiplayer.multiplayer_peer = peer
	print("Hosting on port %d" % PORT)
	spawn_local(multiplayer.get_unique_id())

func join_game() -> void:
	if join_button.disabled:
		return

	reset_game_state()
	_show_game_ui(true)

	var ip: String = ip_input.text.strip_edges()
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(ip, PORT)
	if error != OK:
		printerr("Failed to create client peer: ", error)
		_show_game_ui(false)
		return
		
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s..." % ip)

func exit_game() -> void:
	reset_game_state()
	_show_game_ui(false)

func _on_connected_to_server() -> void:
	print("Connected to server")

func _on_connection_failed() -> void:
	print("Connection failed")
	reset_game_state()
	_show_game_ui(false)

func _on_server_disconnected() -> void:
	print("Disconnected from server")
	reset_game_state()
	_show_game_ui(false)

func _show_game_ui(in_game: bool) -> void:
	host_button.visible = not in_game
	join_button.visible = not in_game
	ip_input.editable = not in_game
	exit_button.visible = in_game

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Peer connected: %d" % id)
	spawn_local(id)
	
	spawn_remote.rpc_id(id, id)
	for existing_id in players.keys():
		if existing_id != id:
			spawn_remote.rpc_id(id, existing_id)
	
	for peer_id in multiplayer.get_peers():
		if peer_id != id:
			spawn_remote.rpc_id(peer_id, id)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("Peer disconnected: %d" % id)
	despawn_local(id)
	despawn_remote.rpc_id(id, id)

func spawn_local(peer_id: int) -> void:
	if players.has(peer_id):
		despawn_local(peer_id)
		
	var p: CharacterBody3D = player_scene.instantiate() as CharacterBody3D
	p.name = "Player_%d" % peer_id
	add_child(p)
	p.set_multiplayer_authority(peer_id)
	
	if is_instance_valid(start_area):
		var pos: Vector3 = start_area.global_position
		p.global_position = pos + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-5.0, 5.0))
		
	if p.has_method("set_network_ready"):
		p.call("set_network_ready", true)
		
	players[peer_id] = p
	print("Spawned local player node for peer %d" % peer_id)

@rpc("authority", "reliable")
func spawn_remote(peer_id: int) -> void:
	spawn_local(peer_id)

@rpc("authority", "reliable")
func despawn_remote(peer_id: int) -> void:
	despawn_local(peer_id)

func despawn_local(peer_id: int) -> void:
	if players.has(peer_id):
		var n: Node = players[peer_id]
		if is_instance_valid(n):
			n.queue_free()
		players.erase(peer_id)
		
func reset_game_state() -> void:
	for id in players.keys():
		var n: Node = players[id]
		if is_instance_valid(n):
			n.queue_free()
	players.clear()
	multiplayer.multiplayer_peer = null
	print("Game state reset to initial state")
	update_join_button_state()

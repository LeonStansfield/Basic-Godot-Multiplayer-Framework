extends Node

@onready var ip_input = $Control/IPAddress
@onready var host_button = $Control/Host
@onready var join_button = $Control/Join
@onready var start_area = $SpawnPoint

const PORT = 12345
const MAX_PLAYERS = 4
var player_scene = preload("res://Prefabs/player.tscn")

func _ready():
	host_button.pressed.connect(host_game)
	join_button.pressed.connect(join_game)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.peer_connected.connect(_on_peer_connected)

func host_game():
	var peer = ENetMultiplayerPeer.new()
	peer.create_server(PORT, MAX_PLAYERS)
	multiplayer.multiplayer_peer = peer
	print("Hosting on port %d" % PORT)
	spawn_player(multiplayer.get_unique_id())

func join_game():
	var ip = ip_input.text.strip_edges()
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(ip, PORT)
	if err != OK:
		print("Failed to connect")
		return
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s..." % ip)

func _on_connected():
	print("Connected to server")
	# When client connects, spawn their own player
	spawn_player(multiplayer.get_unique_id())

func _on_peer_connected(id):
	print("Peer connected: %d" % id)
	# Host sends the new peer a list of all existing players
	if multiplayer.is_server():
		_send_existing_players.rpc_id(id)
		# Then tell everyone to spawn the new player
		spawn_player.rpc(id)

@rpc("authority")
func _send_existing_players():
	# This runs on the client that just connected
	var players = []
	for child in get_children():
		if child is CharacterBody3D:
			players.append(child.get_multiplayer_authority())
	# Spawn all players we know about (host and others)
	for peer_id in players:
		if peer_id != multiplayer.get_unique_id():
			spawn_player(peer_id)

@rpc("any_peer")
func spawn_player(peer_id):
	# If player already exists, skip
	for child in get_children():
		if child is CharacterBody3D and child.get_multiplayer_authority() == peer_id:
			return
	var player = player_scene.instantiate()
	# Randomize spawn position slightly
	player.global_position = start_area.global_position + Vector3(randf() * 5, 0, randf() * 5)
	add_child(player)
	player.set_multiplayer_authority(peer_id)
	print("Spawned player for peer %d" % peer_id)

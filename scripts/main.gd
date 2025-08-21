extends Node

@onready var host_button: Button = $Control/Host
@onready var join_button: Button = $Control/Join
@onready var exit_button: Button = $Control/Exit
@onready var ip_input: LineEdit = $Control/IPInput
@onready var player_scene: PackedScene = preload("res://Prefabs/player.tscn")

var peer: ENetMultiplayerPeer
var is_in_game: bool = false

func _ready() -> void:
	join_button.disabled = true
	exit_button.visible = false
	ip_input.text_changed.connect(_on_ip_input_changed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

func _on_ip_input_changed(new_text: String) -> void:
	join_button.disabled = new_text.strip_edges() == ""

func _on_host_pressed() -> void:
	peer = ENetMultiplayerPeer.new()
	peer.create_server(9000)
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	_start_game()

func _on_join_pressed() -> void:
	var ip: String = ip_input.text.strip_edges()
	if ip == "":
		return
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, 9000)
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_start_game)

func _on_exit_pressed() -> void:
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()

func _start_game() -> void:
	is_in_game = true
	host_button.visible = false
	join_button.visible = false
	ip_input.visible = false
	exit_button.visible = true

	if multiplayer.is_server():
		_spawn_player(multiplayer.get_unique_id())
	else:
		rpc_id(1, "_request_spawn", multiplayer.get_unique_id())

func _on_peer_connected(id: int) -> void:
	rpc_id(id, "_request_spawn", multiplayer.get_unique_id())

@rpc("any_peer", "call_remote", "reliable")
func _request_spawn(id: int) -> void:
	_spawn_player(id)

func _spawn_player(id: int) -> void:
	var player = player_scene.instantiate()
	player.name = str(id)
	add_child(player)

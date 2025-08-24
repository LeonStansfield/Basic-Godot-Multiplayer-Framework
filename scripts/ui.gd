extends Control

@onready var ip_input: LineEdit = $VBoxContainer/IPAddress
@onready var host_button: Button = $VBoxContainer/Host
@onready var join_button: Button = $VBoxContainer/Join
@onready var exit_button: Button = $VBoxContainer/Exit

@export var network_manager_path: NodePath
var nm: Node

var _is_connecting := false
var _in_game := false

func _ready() -> void:
	nm = get_node(network_manager_path)

	# Buttons
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	ip_input.text_changed.connect(_on_ip_text_changed)

	# NetworkManager signals
	nm.connect("hosting_started", Callable(self, "_on_hosting_started"))
	nm.connect("hosting_failed", Callable(self, "_on_hosting_failed"))
	nm.connect("connecting_started", Callable(self, "_on_connecting_started"))
	nm.connect("connected", Callable(self, "_on_connected"))
	nm.connect("connection_failed", Callable(self, "_on_connection_failed"))
	nm.connect("disconnected", Callable(self, "_on_disconnected"))

	_update_ui()

# ======================
# BUTTON HANDLERS
# ======================
func _on_host_pressed() -> void:
	var err: Error = nm.host_game()
	if err != OK:
		# Stay in menu; nothing else to do. (hosting_failed signal also fires)
		return

func _on_join_pressed() -> void:
	var ip := ip_input.text.strip_edges()
	# Try to start connecting. If invalid IP or immediate error, do nothing visible.
	var err: Error = nm.join_game(ip)
	if err != OK:
		_is_connecting = false
		_in_game = false
		_update_ui()
		return
	# If OK, we will get "connecting_started" soon. Until then, keep the menu as-is.

func _on_exit_pressed() -> void:
	# Works both while in-game and while connecting (acts as cancel).
	nm.exit_game()
	# UI is updated via "disconnected" signal, but keep it responsive now too.
	_is_connecting = false
	_in_game = false
	_update_ui()

func _on_ip_text_changed(_new_text: String) -> void:
	_update_ui()

# ======================
# NETWORK SIGNAL HANDLERS
# ======================
func _on_hosting_started() -> void:
	_in_game = true
	_is_connecting = false
	_update_ui()

func _on_hosting_failed(_err_code: int) -> void:
	_in_game = false
	_is_connecting = false
	_update_ui()

func _on_connecting_started(_ip: String) -> void:
	# Show "connecting" state: keep menu visible but lock inputs; EXIT stays enabled.
	_is_connecting = true
	_in_game = false
	_update_ui()

func _on_connected() -> void:
	# Only after real connection do we switch into in-game UI.
	_in_game = true
	_is_connecting = false
	_update_ui()

func _on_connection_failed() -> void:
	_is_connecting = false
	_in_game = false
	_update_ui()

func _on_disconnected() -> void:
	_is_connecting = false
	_in_game = false
	_update_ui()

# ======================
# UI STATE
# ======================
func _update_ui() -> void:
	# Exit is always available and enabled
	exit_button.visible = true
	exit_button.disabled = false

	if _in_game:
		# In-game: hide menu controls, keep EXIT visible/enabled
		host_button.visible = false
		join_button.visible = false
		ip_input.editable = false
		host_button.disabled = true
		join_button.disabled = true
		exit_button.disabled = false
	else:
		# Menu visible
		host_button.visible = true
		join_button.visible = true
		exit_button.disabled = true

		# While connecting: lock host/join/ip, but keep exit enabled
		if _is_connecting:
			host_button.disabled = true
			join_button.disabled = true
			ip_input.editable = false
		else:
			host_button.disabled = false
			join_button.disabled = ip_input.text.strip_edges() == ""
			ip_input.editable = true

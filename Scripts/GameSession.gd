##
# GameSession.gd
#
# A GameSession represents a single match in progress.  It manages
# players, Alaska (the NPC to be rescued), Dr. Grimshaw (the boss),
# and power‑ups.  The GameServer will create multiple GameSession
# nodes when more players join than can be accommodated in a single
# session.  Each session runs independently and has its own set of
# players.
#
# Instances of GameSession are created on the server only.  The
# server has authority over spawning players, NPC movement, and
# overall game state.  Clients receive their assigned session ID via
# the GameServer and control only their own player characters.
#
# This script is thoroughly commented for maintainability.  Because
# networked games can become complex very quickly, clear comments
# help future developers understand the design choices and
# responsibilities.

extends Node2D

## Unique identifier for this session assigned by the GameServer.
@export var session_id : int = 0

## Resource references used to instantiate players and power ups.  By
## exposing them here via @onready we avoid repeated calls to
## preload() at runtime.
@onready var _player_scene : PackedScene = preload("res://Scenes/Player.tscn")
@onready var _powerup_scene : PackedScene = preload("res://Scenes/PowerUp.tscn")

## Dictionary mapping peer IDs to their corresponding player nodes.
## This is used by the server to manage connected clients.
var _players : Dictionary = {}

## Timer used to spawn power ups at regular intervals.  The
## configuration values for interval and radius can be tuned here or
## exposed to the editor for balancing purposes.
var _powerup_timer : Timer

## Interval in seconds between spawning power ups.  Power ups allow
## players to restore their scale and Alaska's scale to normal.
@export var powerup_interval : float = 30.0

## Radius of the area of effect for each power up.  This value
## roughly defines one quarter of the playable space and should be
## adjusted according to map size.
@export var powerup_radius : float = 200.0

## Reference to Alaska and Grimshaw nodes within this session.  These
## are assigned in _ready().  Alaska starts small and cannot be
## restored to full size except via a power up.  Grimshaw is
## controlled by the server to fire rays at players.
var alaska : CharacterBody2D
var grimshaw : CharacterBody2D

## Called when the GameSession enters the scene tree.  Performs
## initialisation such as finding child nodes and starting timers.
func _ready() -> void:
	# Cache references to Alaska and Grimshaw.  These nodes are
	# present in the scene because GameSession.tscn instantiates them.
	alaska = get_node("Alaska")
	grimshaw = get_node("Grimshaw")
	# Mark Alaska as extremely small by default.  The scale factor is
	# expressed via the Alaska.gd script.  Here we ensure the
	# character starts at a tiny size for immediate gameplay impact.
	if alaska.has_method("set_scale_factor"):
		alaska.set_scale_factor(0.1)
	# Set up power up timer only on the server.  Clients do not spawn
	# power ups locally; they simply see them appear when the server
	# adds them to the scene.
	if multiplayer.is_server():
		_powerup_timer = Timer.new()
		_powerup_timer.wait_time = powerup_interval
		_powerup_timer.one_shot = false
		_powerup_timer.autostart = true
		_powerup_timer.timeout.connect(_on_powerup_timer_timeout)
		add_child(_powerup_timer)
## Spawns a player character for the peer with the given ID.  This
## method should only be called on the server.  It instantiates
## Player.tscn, assigns network authority to the connecting peer and
## positions the player within the map.  Players are stored in the
## `_players` dictionary for later management.
func spawn_player(peer_id : int) -> void:
	if not get_tree().is_multiplayer_server():
		return
	if _players.has(peer_id):
		return
	var player : CharacterBody2D = _player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	# Assign network authority to the connecting peer.  This allows
	# the client to control its own character while the server
	# replicates its state to other clients.
	player.set_multiplayer_authority(peer_id)
	# Randomise initial position within a central area.  In a full
	# implementation this could be a spawn point list to avoid
	# overlapping spawns.
	player.position = Vector2(randf() * 400 - 200, randf() * 400 - 200)
	# Add to the scene and track in dictionary
	$PlayersRoot.add_child(player)
	_players[peer_id] = player
	# Initialise the player.  The init_player function lives in
	# Player.gd and assigns peer_id and colour.
	if player.has_method("init_player"):
		player.init_player(peer_id)
	print("Spawned player %d in session %d" % [peer_id, session_id])

## Removes a player from the session.  When a peer disconnects the
## GameServer calls this method to clean up the character.  Only
## the server should invoke this.
func remove_player(peer_id : int) -> void:
	if not get_tree().is_multiplayer_server():
		return
	if _players.has(peer_id):
		var player : Node = _players[peer_id]
		player.queue_free()
		_players.erase(peer_id)
		print("Removed player %d from session %d" % [peer_id, session_id])

## Server callback for the power up timer.  Spawns a new power up in
## a random quadrant of the map.  The power up will restore the
## scale of any characters (including Alaska) inside its radius.
func _on_powerup_timer_timeout() -> void:
	# Do not spawn power ups if there are no players; this saves
	# resources on unused sessions.
	if _players.is_empty():
		return
	var power_up : Node2D = _powerup_scene.instantiate()
	# Attempt to set the radius property on the instance.  If the
	# PowerUp script defines `radius` as exported, this will take
	# effect.  Otherwise the default size is used.
	if power_up.has_variable("radius"):
		power_up.set("radius", powerup_radius)
	# Determine a quadrant for placement.  The classroom is conceptually
	# divided into four quadrants.  Position the power up in the
	# centre of one quadrant.  For a more dynamic map consider using
	# actual geometry bounds.
	var viewport_size : Vector2 = get_viewport_rect().size
	var quadrant : int = randi() % 4
	var pos := Vector2.ZERO
	match quadrant:
		0:
			pos = viewport_size * Vector2(0.25, 0.25)
		1:
			pos = viewport_size * Vector2(0.75, 0.25)
		2:
			pos = viewport_size * Vector2(0.25, 0.75)
		3:
			pos = viewport_size * Vector2(0.75, 0.75)
	power_up.position = pos
	$PowerUps.add_child(power_up)
	print("Spawned power up in session %d at %s" % [session_id, str(pos)])

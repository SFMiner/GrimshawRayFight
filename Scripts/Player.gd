##
# Player.gd
#
# The Player script controls a student avatar.  Each player is a
# CharacterBody2D with a simple square visual.  Players move based
# on local input if they have network authority over their instance.
# They maintain a `scale_factor` which determines both their speed
# and physical size.  When scaled down they move more slowly and
# their collision size shrinks; when scaled up they move faster and
# their collision size expands.  Setting the scale factor should be
# done via `set_scale_factor()` to ensure visual updates are
# propagated correctly.

extends CharacterBody2D

## Base movement speed in pixels per second.  This value is
## multiplied by the current scale factor to derive actual speed.
@export var base_speed : float = 100.0

## Current scale factor.  1.0 means normal size.  Values less than
## one shrink the player and slow them down.  Values greater than
## one enlarge the player and speed them up.
var scale_factor : float = 1.0:
	set(new_value):
		# Custom logic when the variable is set
		print("Setting scale_factor to:", new_value)
		scale_factor = new_value # Important: assign the new value to the variable
	get:
		# Custom logic when the variable is accessed
		print("Getting scale_factor")
		return scale_factor

## Unique peer identifier controlling this player.  This value is
## assigned by the GameSession when the player is spawned.  It is
## used to determine if local input should drive movement.
var peer_id : int = 0

## Called once the player node is added to the scene.  Performs
## initialisation tasks such as setting a random colour based on
## peer ID.
func _ready() -> void:
	# Randomise the colour based on the peer ID to differentiate
	# players.  A simple hash modulates the hue.
	var hue : float = float((peer_id * 23) % 360) / 360.0
	var colour : Color = Color.from_hsv(hue, 0.7, 1.0)
	$Visual.color = colour
	# Initialise visual size according to scale factor
	_update_visual()

	# Ensure a collision shape exists.  If none is defined in the
	# scene the player may pass through obstacles.  Create a
	# RectangleShape2D on the fly.  This will be resized later in
	# _update_visual().
	if has_node("CollisionShape2D"):
		var cs := $CollisionShape2D
		if cs.shape == null:
			cs.shape = RectangleShape2D.new()

## Initialises the player with a peer identifier.  This method is
## called by GameSession on the server when spawning the player.
func init_player(id: int) -> void:
	peer_id = id
	# Force colour update now that peer ID is known
	var hue : float = float((peer_id * 23) % 360) / 360.0
	var colour : Color = Color.from_hsv(hue, 0.7, 1.0)
	$Visual.color = colour
	# Add this node to a group so other nodes (e.g. Alaska or
	# Grimshaw) can find all players without maintaining a separate
	# registry.  The group name "players" is used throughout the
	# project.
	add_to_group("players")

## Sets the scale factor and updates the player's visual size.  This
## method should be used whenever modifying scale_factor to ensure
## consistency between the numeric value and the actual scale on
## screen.  It can be called locally or via RPC.
@rpc
func set_scale_factor(value: float) -> void:
	scale_factor = clamp(value, 0.05, 20.0)
	_update_visual()

## Returns the player's current scale factor.  This helper is used
## when computing reciprocals or applying additional scaling.
func get_scale_factor() -> float:
	return scale_factor

## Applies a new scale by multiplying the current factor with the
## provided multiplier.  This is called when another student fires
## the wrong scale factor at this player.  To restore a player to
## normal size call `set_scale_factor(1.0)`.
@rpc
func multiply_scale(multiplier: float) -> void:
	set_scale_factor(scale_factor * multiplier)

## Updates the visual representation of the player according to the
## current scale factor.  Both the visual square and the collision
## shape are resized.  In a more complete implementation you might
## use separate sprites for different animations.
func _update_visual() -> void:
	var size_base := Vector2(32, 32)
	var new_size := size_base * scale_factor
	if $Visual and $Visual.has_method("set_size"):
		$Visual.size = new_size
	# Adjust collision shape to match new bounds if present
	if has_node("CollisionShape2D"):
		var shape = $CollisionShape2D.shape
		if shape and shape is RectangleShape2D:
			shape.extents = new_size / 2

## Handles movement input.  Only executes on the authority (the
## controlling peer).  Moves the player relative to the current
## scale.  Uses built in CharacterBody2D `velocity` property.
func _physics_process(delta: float) -> void:
	# Only process movement on the controlling client or on the
	# server for non-player characters. `multiplayer` is the
	# MultiplayerAPI attached to this node.
	var mp := multiplayer
	var is_authority := mp.is_server() or mp.get_unique_id() == peer_id

	if not is_authority:
		return
	var direction := Vector2.ZERO
	# Movement uses standard WASD or arrow keys.  These actions
	# should be configured in the project settings input map.  If
	# running from within the editor without a configured input map
	# these keys may need to be added manually via Project Settings.
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if direction.length() > 0:
		direction = direction.normalized()
	# Actual speed is the base speed scaled by the current scale
	# factor.  Enlarged players move faster, shrunk players move
	# slower.
	velocity = direction * base_speed * scale_factor
	move_and_slide()

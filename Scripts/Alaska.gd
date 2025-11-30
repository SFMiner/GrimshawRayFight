##
# Alaska.gd
#
# This script controls Alaska, the NPC student who starts shrunken
# and must be restored to normal size via power ups.  Alaska is
# derived from CharacterBody2D (not Player) because she does not
# accept user input and instead follows the nearest player.
#
# On the server Alaska will attempt to move towards the closest
# player character within a limited radius.  Her movement speed is
# intentionally slower than a normal player to reflect her tiny
# size.  Clients simply interpolate her position based on state
# replicated from the server.

extends CharacterBody2D

## Base movement speed for Alaska.  She moves slower than players.
@export var base_speed : float = 800.0
@onready var sprint = $Sprite2D
@onready var ap = $AnimationPlayer
## Current scale factor.  Alaska starts very small.  Only the server
## may modify this property directly via set_scale_factor().  Clients
## should treat Alaska as read‑only.
var scale_factor : float = 0.2:
	set(new_value):
		# Custom logic when the variable is set
		print("Alaska scale_factor.set() to:", new_value)
		scale_factor = new_value # Important: assign the new value to the variable
	get:
		# Custom logic when the variable is accessed
#		print("Getting scale_factor")
		return scale_factor

var ai_enabled: bool = false
func set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled
	
## Called when Alaska enters the scene tree.  Assign an initial
## extremely small scale factor and update the visual accordingly.
func _ready() -> void:
	scale_factor = 0.2
	scale = Vector2(0.2, 0.2)
	print("Alaska's starting scale factor is ", str(scale_factor))

	# Ensure there is a collision shape so Alaska can participate in
	# collisions and power up detection.  Create a RectangleShape2D
	# if none exists.
	if has_node("CollisionShape2D"):
		var cs := $CollisionShape2D
		if cs.shape == null:
			cs.shape = RectangleShape2D.new()

## Sets Alaska's scale factor and adjusts her visual accordingly.
## Because Alaska is not controlled by any player, this method is
## invoked only by the server (either when she is shrunk further by
## Grimshaw or restored by a power up).  Clients receive the
## updated scale via RPC.
#@rpc
func set_scale_factor(value: float) -> void:
	print("Alaska set_scale_factor(" + str(value) + ")") 
	scale_factor = clamp(value, 0.05, 8.0)
	_update_visual()

## Multiplies Alaska's scale factor by the provided multiplier.  This
## is used when she is hit by Grimshaw's ray.  To fully restore
## Alaska use set_scale_factor(1.0).
#@rpc
func multiply_scale(multiplier: float) -> void:
	print("Alaska multiply_scale(" + str(multiplier) + ")") 
	set_scale_factor(scale_factor * multiplier)

## Updates Alaska's visual size based on the current scale factor.
func _update_visual() -> void:
	print("Alaska' update_visual: scale_factor =" + str(scale_factor))
	scale = Vector2(scale_factor, scale_factor)
	print("Alaska' update_visual: scale =" + str(scale))
	#var size_base := Vector2(24, 24)
#	var new_size := size_base * scale_factor
#	if $Visual and $Visual.has_method("set_size"):
#		$Visual.size = new_size
#	if has_node("CollisionShape2D"):
#		var shape = $CollisionShape2D.shape
#		if shape and shape is RectangleShape2D:
#			shape.extents = new_size / 2

## Alaska's movement logic.  Only executes on the server to prevent
## multiple authorities moving the same character.  Alaska will
## constantly move towards the nearest player if any exist.  If
## she reaches a player (within a small threshold) she stops.
func _physics_process(delta: float) -> void:
	# Only run on the server and only when AI is enabled.
	if not multiplayer.is_server():
		return
	if not ai_enabled:
		return

	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Find the closest player to Alaska
	var closest : Node = null
	var closest_dist : float = INF
	for p in players:
		if p is CharacterBody2D:
			var d := global_position.distance_squared_to(p.global_position)
			if d < closest_dist:
				closest = p
				closest_dist = d
	if closest == null:
		return
	# Compute direction to the closest player and move
	var direction : Vector2 = (closest.global_position - global_position)
	var distance : float = direction.length()
	# Stop if within a small distance
	if distance < 16.0:
		velocity = Vector2.ZERO
		return
	direction = direction.normalized()
	
	var angle_deg := rad_to_deg(direction.angle())
	if angle_deg < 0:
		angle_deg += 360
	var state := ""

	if angle_deg >= 45 and angle_deg < 135:
		state = "walk_down"
	elif angle_deg >= 135 and angle_deg < 225:
		state = "walk_left"
	elif angle_deg >= 225 and angle_deg < 315:
		state = "walk_up"
	else:
		state = "walk_right"
	# Actual speed is the base speed scaled by the current scale
	# factor.  Enlarged players move faster, shrunk players move
	# slower.
	
	velocity = direction * base_speed * scale_factor
	if velocity == Vector2.ZERO:
		ap.stop()
	else:
		ap.play(state)
		z_index = global_position.y/5
	move_and_slide()

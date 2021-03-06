tool
class_name Function_ClimbMovement
extends MovementProvider

##
## Movement Provider for Climbing
##
## @desc:
##     This script works with the Function_Climb_movement asset to provide
##     climbing movement for the player. This script works with the PlayerBody
##     attached to the players ARVROrigin.
##
##     StaticBody objects can be marked as climbable by adding the
##     Object_climbable script to them
##
##     When climbing, the global velocity of the PlayerBody is averaged for
##     velocity_averages samples, and upon release the velocity is applied
##     to the PlayerBody so the player can fling themselves up walls if
##     desired.
##

## Signal invoked when the player starts climing
signal player_climb_start

## Signal invoked when the player ends climbing
signal player_climb_end


# Horizontal vector (multiply by this to get only the horizontal components
const HORIZONTAL := Vector3(1.0, 0.0, 1.0)


## Movement provider order
export var order := 15

## Push forward when flinging
export var forward_push := 1.0

## Velocity multiplier when flinging up walls
export var fling_multiplier := 1.0

## Averages for velocity measurement
export var velocity_averages := 5

## Pickup function for the left hand
export (NodePath) var left_pickup

## Pickup function for the right hand
export (NodePath) var right_pickup


# Velocity averaging fields
var _distances = Array()
var _deltas = Array()


# Node references
onready var _left_pickup_node: Function_Pickup = get_node(left_pickup)
onready var _right_pickup_node: Function_Pickup = get_node(right_pickup)


func physics_movement(delta: float, player_body: PlayerBody, disabled: bool):
	# Disable climbing if requested
	if disabled or !enabled:
		_set_climbing(false, player_body)
		return

	# Get the left-hand climbable
	var left_climbable := _left_pickup_node.picked_up_object as Object_climbable
	if !is_instance_valid(left_climbable):
		left_climbable = null

	# Get the right-hand climbable
	var right_climbable := _right_pickup_node.picked_up_object as Object_climbable
	if !is_instance_valid(right_climbable):
		right_climbable = null

	# Update climbing
	_set_climbing(left_climbable or right_climbable, player_body)

	# Skip if not actively climbing
	if !is_active:
		return

	# Calculate how much the player has moved
	var offset := Vector3.ZERO
	if left_climbable:
		var left_pickup_pos := _left_pickup_node.global_transform.origin
		var left_grab_pos := left_climbable.get_grab_location(_left_pickup_node)
		offset += left_pickup_pos - left_grab_pos
	if right_climbable:
		var right_pickup_pos := _right_pickup_node.global_transform.origin
		var right_grab_pos := right_climbable.get_grab_location(_right_pickup_node)
		offset += right_pickup_pos - right_grab_pos

	# Average the offset if we have two hands moving
	if left_climbable and right_climbable:
		offset *= 0.5
	
	#Trying (New Code) if not enough y movement and mostly x or z movement, shrink player collision shape then restore it after move
	#This is because we assume the person is trying to vault a shape or get to the top of the wall when that occurs.
	
	#print("The offset for climbing is " + str(offset))  --> Just debug text if needed.
	var normal_collision_height = player_body._collision_node.shape.height 
	var normal_collision_radius = player_body._collision_node.shape.radius
	#print("The player's normal height is " + str(normal_collision_height) + " and the normal radius is " + str(normal_collision_radius)) --> just debut text
	
	#if abs(offset.y) >= .02*world_scale: #trying arbitrary number to test if we are climbing vertically or not
		#print("Not trying the smaller body shape here, because climbing vertically") --> This was all just for debug to make sure it was not triggering all the time
	
	if abs(offset.y) < .02*ARVRServer.world_scale: #test if we are climbing vertically or not, .02 was trial and error
		player_body._collision_node.shape.radius *= .05 #arbitrary reduction in size for testing
		player_body._collision_node.shape.height *= .05 #arbitrary reduction in size for testing
		#print("Trying to apply smaller kinematic node collision shape to see if that helps")  #--> Just debug text
		#print("The player's height now is " + str(player_body._collision_node.shape.height) + " and new radius is" + str(player_body._collision_node.shape.radius))  --> Just debug text
	
	# Move the player by the offset
	var old_position := player_body.kinematic_node.global_transform.origin
	player_body.kinematic_node.move_and_collide(-offset)
	player_body.velocity = Vector3.ZERO
	
	#always reset the collision shape at the end of movement in case we changed it for lateral movement
	player_body.velocity = Vector3.ZERO
	player_body._collision_node.shape.radius = lerp(player_body._collision_node.shape.radius, normal_collision_radius, delta)
	player_body._collision_node.shape.height = lerp(player_body._collision_node.shape.height, normal_collision_height, delta)
	

	# Update the players average-velocity data
	var distance := player_body.kinematic_node.global_transform.origin - old_position
	_update_velocity(delta, distance)

	# Report exclusive motion performed (to bypass gravity)
	return true


func _set_climbing(active: bool, player_body: PlayerBody) -> void:
	# Skip if no change
	if active == is_active:
		return

	# Update state
	is_active = active

	# Handle state change
	if is_active:
		_distances.clear()
		_deltas.clear()
		emit_signal("player_climb_start")
	else:
		var velocity := _average_velocity()
		var dir_forward = -(player_body.camera_node.global_transform.basis.z * HORIZONTAL).normalized()
		player_body.velocity = (velocity * fling_multiplier) + (dir_forward * forward_push)
		emit_signal("player_climb_end")


# Update player velocity averaging data
func _update_velocity(delta: float, distance: Vector3):
	# Add delta and distance to averaging arrays
	_distances.push_back(distance)
	_deltas.push_back(delta)
	if _distances.size() > velocity_averages:
		_distances.pop_front()
		_deltas.pop_front()

# Calculate average player velocity
func _average_velocity() -> Vector3:
	# Calculate the total time
	var total_time := 0.0
	for dt in _deltas:
		total_time += dt

	# Calculate the total distance
	var total_distance := Vector3(0.0, 0.0, 0.0)
	for dd in _distances:
		total_distance += dd

	# Return the average
	return total_distance / total_time

# This method verifies the MovementProvider has a valid configuration.
func _get_configuration_warning():
	# Verify the left controller
	var test_left_pickup_node = get_node_or_null(left_pickup) if left_pickup else null
	if !test_left_pickup_node or !test_left_pickup_node is Function_Pickup:
		return "Unable to find left Function_Pickup"

	# Verify the right controller
	var test_right_pickup_node = get_node_or_null(right_pickup) if right_pickup else null
	if !test_right_pickup_node or !test_right_pickup_node is Function_Pickup:
		return "Unable to find right Function_Pickup"

	# Verify velocity averages
	if velocity_averages < 2:
		return "Minimum of 2 velocity averages needed"

	# Call base class
	return ._get_configuration_warning()

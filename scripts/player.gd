extends Node3D
## Runner: switches between three lanes and jumps. Forward motion is driven by Main.

signal hit_obstacle
signal picked_crystal(crystal: Node3D)

const MODEL_PATH := "res://assets/models/explorer.glb"
const LANE_WIDTH := 2.5
const LANE_SWITCH_SPEED := 16.0
const JUMP_VELOCITY := 8.5
const GRAVITY := 24.0
const MAX_LEAN := 0.25

var lane := 0
var vertical_velocity := 0.0
var alive := true
var anim: AnimationPlayer

@onready var model_root: Node3D = $Model
@onready var hitbox: Area3D = $Hitbox


func _ready() -> void:
	hitbox.area_entered.connect(_on_area_entered)
	if ResourceLoader.exists(MODEL_PATH):
		var model: Node3D = load(MODEL_PATH).instantiate()
		model_root.add_child(model)
		# The glTF character faces +Z; the runner moves toward -Z.
		model.rotation.y = PI
		anim = model.find_children("*", "AnimationPlayer", true, false).pop_front()
	if anim and anim.get_animation_list().size() > 0:
		var run_name: StringName = anim.get_animation_list()[0]
		anim.get_animation(run_name).loop_mode = Animation.LOOP_LINEAR
		anim.play(run_name)


func is_grounded() -> bool:
	return position.y <= 0.0 and vertical_velocity <= 0.0


## Called by Main every frame while the round is running.
func tick(delta: float, run_speed: float) -> void:
	if Input.is_action_just_pressed("move_left"):
		lane = maxi(lane - 1, -1)
	if Input.is_action_just_pressed("move_right"):
		lane = mini(lane + 1, 1)
	if Input.is_action_just_pressed("jump") and is_grounded():
		vertical_velocity = JUMP_VELOCITY

	vertical_velocity -= GRAVITY * delta
	position.y += vertical_velocity * delta
	if position.y <= 0.0:
		position.y = 0.0
		vertical_velocity = 0.0

	var target_x := lane * LANE_WIDTH
	var gap := target_x - position.x
	position.x = move_toward(position.x, target_x, LANE_SWITCH_SPEED * delta)
	model_root.rotation.z = lerpf(model_root.rotation.z, clampf(-gap, -1.0, 1.0) * MAX_LEAN, 12.0 * delta)
	if anim:
		anim.speed_scale = run_speed / 12.0


func die() -> void:
	alive = false
	if anim:
		anim.pause()
	var tween := create_tween()
	tween.tween_property(model_root, "rotation:x", -1.2, 0.35).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "position:y", 0.0, 0.25)


func _on_area_entered(area: Area3D) -> void:
	if not alive:
		return
	if area.is_in_group("obstacle"):
		hit_obstacle.emit()
	elif area.is_in_group("crystal"):
		picked_crystal.emit(area)

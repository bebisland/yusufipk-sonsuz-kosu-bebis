extends Node3D
## Round flow: forward speed, obstacle and crystal spawning, scoring, sunset and restart.

const ROUND_TIME := 90.0
const START_SPEED := 12.0
const SPEED_STEP := 1.08 # speed multiplier applied every SPEED_INTERVAL seconds
const SPEED_INTERVAL := 10.0
const SPAWN_AHEAD := 120.0
const DESPAWN_BEHIND := 12.0
const FIRST_ROW_Z := -45.0
const CRYSTAL_POINTS := 25
const LANE_WIDTH := 2.5

const LAYER_OBSTACLE := 2
const LAYER_CRYSTAL := 4

# Each model is scaled uniformly so the given axis ("x" width or "y" height) hits the
# target size in meters. `hit_shrink` makes the collision box a bit smaller than the
# mesh so near misses feel fair.
const MODELS := {
	"barrier": {"path": "res://assets/models/barrier.glb", "axis": "x", "size": 2.3, "long_x": true, "hit_shrink": Vector3(0.9, 0.75, 0.7)},
	"pillar": {"path": "res://assets/models/pillar.glb", "axis": "y", "size": 3.8, "long_x": false, "hit_shrink": Vector3(0.75, 1.0, 0.75)},
	"cart": {"path": "res://assets/models/cart.glb", "axis": "x", "size": 4.8, "long_x": true, "hit_shrink": Vector3(0.9, 0.9, 0.8)},
	"crystal": {"path": "res://assets/models/crystal.glb", "axis": "y", "size": 0.9, "long_x": false, "hit_shrink": Vector3(1.4, 1.2, 1.4)},
}

enum State { RUNNING, OVER }

## Dev-only: steers and jumps on its own so a round can be checked from the editor
## without keyboard input (set it with play_scene's on_ready writes).
@export var autopilot := false

var state := State.RUNNING
var elapsed := 0.0
var speed := START_SPEED
var distance := 0.0
var crystals := 0
var next_row_z := FIRST_ROW_Z
var next_decor_z := -6.0
var shake := 0.0
var templates := {}
var crystal_glow: StandardMaterial3D

@onready var player: Node3D = $Player
@onready var camera: Camera3D = $Camera
@onready var spawned: Node3D = $Spawned
@onready var road: MeshInstance3D = $Road
@onready var ground: MeshInstance3D = $Ground
@onready var sun: DirectionalLight3D = $Sun
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	randomize()
	_ensure_input_actions()
	crystal_glow = StandardMaterial3D.new()
	crystal_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crystal_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crystal_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	crystal_glow.albedo_color = Color(0.2, 0.9, 1.0, 0.35)
	for key in MODELS:
		if ResourceLoader.exists(MODELS[key].path):
			templates[key] = _build_template(key)
		else:
			push_warning("Missing model, %s will not spawn: %s" % [key, MODELS[key].path])
	player.hit_obstacle.connect(_on_player_hit)
	player.picked_crystal.connect(_on_crystal_picked)
	_update_sunset(0.0)
	_update_camera(1.0)
	hud.set_crystals(0)
	hud.set_score(0)
	hud.set_time_left(ROUND_TIME)


func _exit_tree() -> void:
	# Templates never enter the tree, so they are not freed with the scene.
	for template in templates.values():
		template.free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if state == State.RUNNING:
		elapsed += delta
		var target_speed := START_SPEED * pow(SPEED_STEP, floorf(elapsed / SPEED_INTERVAL))
		speed = move_toward(speed, target_speed, 3.0 * delta)
		player.position.z -= speed * delta
		distance += speed * delta
		if autopilot:
			var plan := _autopilot_plan()
			player.tick(delta, speed, plan.lane, plan.jump)
		else:
			player.tick(delta, speed)
		_spawn_ahead()
		_despawn_behind()
		_update_sunset(elapsed / ROUND_TIME)
		hud.set_score(_score())
		hud.set_time_left(ROUND_TIME - elapsed)
		if elapsed >= ROUND_TIME:
			_end_round("Gün battı!")
	road.position.z = player.position.z - 120.0
	ground.position.z = player.position.z - 120.0
	shake = maxf(shake - delta * 2.5, 0.0)
	_update_camera(delta)


func _score() -> int:
	return int(distance) + crystals * CRYSTAL_POINTS


func _end_round(title: String) -> void:
	state = State.OVER
	player.stop()
	print("Round over: %s after %.1f s, score %d, crystals %d" % [title, elapsed, _score(), crystals])
	hud.set_score(_score())
	hud.show_end(title, _score(), crystals)


func _on_player_hit() -> void:
	if state != State.RUNNING:
		return
	player.die()
	shake = 1.0
	_end_round("Çarptın!")


func _on_crystal_picked(crystal: Node3D) -> void:
	if state != State.RUNNING:
		return
	crystals += 1
	hud.set_crystals(crystals)
	crystal.queue_free()


# --- Camera and lighting ---------------------------------------------------

func _update_camera(delta: float) -> void:
	var p := player.position
	var target := Vector3(p.x * 0.7, 2.6 + p.y * 0.35, p.z + 4.3)
	camera.position = camera.position.lerp(target, clampf(10.0 * delta, 0.0, 1.0))
	camera.position.z = target.z
	if shake > 0.0:
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * shake * 0.15
	camera.look_at(Vector3(p.x * 0.5, 1.3, p.z - 7.0))


## t runs from 0 (round start) to 1 (sun down).
func _update_sunset(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	sun.rotation = Vector3(deg_to_rad(lerpf(-24.0, -4.0, t)), deg_to_rad(160.0), 0.0)
	sun.light_color = Color(1.0, 0.78, 0.55).lerp(Color(1.0, 0.45, 0.3), t)
	sun.light_energy = lerpf(1.6, 0.5, t)
	var env := world_env.environment
	env.ambient_light_energy = lerpf(1.0, 0.45, t)
	env.fog_light_color = Color(0.95, 0.6, 0.4).lerp(Color(0.45, 0.22, 0.3), t)
	var sky_mat := env.sky.sky_material as ShaderMaterial
	sky_mat.set_shader_parameter("brightness", lerpf(1.0, 0.5, t))


# --- Spawning ----------------------------------------------------------------

func _row_gap() -> float:
	var t := clampf(elapsed / ROUND_TIME, 0.0, 1.0)
	return lerpf(30.0, 18.0, t) + randf_range(-2.0, 3.0)


func _spawn_ahead() -> void:
	var horizon := player.position.z - SPAWN_AHEAD
	while next_row_z > horizon:
		_spawn_row(next_row_z)
		next_row_z -= _row_gap()
	while next_decor_z > horizon:
		_spawn_decor(next_decor_z)
		next_decor_z -= randf_range(7.0, 14.0)


func _despawn_behind() -> void:
	var limit := player.position.z + DESPAWN_BEHIND
	for child in spawned.get_children():
		if child.position.z > limit:
			child.queue_free()


func _spawn_row(z: float) -> void:
	var lanes := [-1, 0, 1]
	lanes.shuffle()
	var roll := randf()
	var late := elapsed > 30.0
	if roll < 0.35:
		# Low barriers: jump over. One lane early, up to all three later.
		var count := 1 if not late else randi_range(1, 3)
		for i in count:
			_place("barrier", lanes[i] * LANE_WIDTH, z)
		if randf() < 0.5:
			_crystal_arc(lanes[0], z)
		elif count < 3:
			_crystal_line(lanes[count], z)
	elif roll < 0.7:
		# Tall pillars: change lane. Never all three lanes.
		var count := 1 if randf() < 0.6 else 2
		for i in count:
			_place("pillar", lanes[i] * LANE_WIDTH, z)
		if late and count == 1 and randf() < 0.5:
			_place("barrier", lanes[1] * LANE_WIDTH, z)
			_crystal_line(lanes[2], z)
		else:
			_crystal_line(lanes[count], z)
	else:
		# Cart covers two lanes; the third one is the way through.
		var free_lane := -1 if randf() < 0.5 else 1
		_place("cart", -free_lane * LANE_WIDTH * 0.5, z)
		_crystal_line(free_lane, z)


func _spawn_decor(z: float) -> void:
	var key: String = ["pillar", "pillar", "barrier"].pick_random()
	if not templates.has(key):
		return
	var side := -1.0 if randf() < 0.5 else 1.0
	var node: Node3D = templates[key].get_node("Visual").duplicate()
	node.position = Vector3(side * randf_range(6.5, 11.0), 0.0, z)
	node.rotation.y = randf_range(-0.6, 0.6)
	node.scale *= randf_range(0.8, 1.3)
	spawned.add_child(node)


func _crystal_line(lane: int, row_z: float) -> void:
	for i in 5:
		_place("crystal", lane * LANE_WIDTH, row_z + 14.0 - i * 2.5, 0.5)


func _crystal_arc(lane: int, row_z: float) -> void:
	for i in 5:
		var k := (i - 2) / 2.0
		_place("crystal", lane * LANE_WIDTH, row_z + k * 4.0, 0.6 + 1.3 * (1.0 - k * k))


func _place(key: String, x: float, z: float, y := 0.0) -> Node3D:
	if not templates.has(key):
		return null
	var node: Node3D = templates[key].duplicate()
	node.position = Vector3(x, y, z)
	spawned.add_child(node)
	return node


## Builds a reusable Area3D (collision box + scaled model) for one model type.
func _build_template(key: String) -> Area3D:
	var info: Dictionary = MODELS[key]
	var area := Area3D.new()
	area.name = key.capitalize()
	area.set_meta("kind", key)
	area.monitoring = false
	area.collision_mask = 0
	var is_crystal := key == "crystal"
	area.collision_layer = LAYER_CRYSTAL if is_crystal else LAYER_OBSTACLE
	area.add_to_group("crystal" if is_crystal else "obstacle")
	if is_crystal:
		area.set_script(preload("res://scripts/crystal.gd"))

	var visual := Node3D.new()
	visual.name = "Visual"
	area.add_child(visual)
	var model: Node3D = load(info.path).instantiate()
	visual.add_child(model)

	var box := _mesh_aabb(model, model)
	if info.long_x and box.size.z > box.size.x:
		model.rotation.y = PI * 0.5
		box = _mesh_aabb(model, visual)
	var axis_size: float = box.size.x if info.axis == "x" else box.size.y
	var s: float = info.size / maxf(axis_size, 0.001)
	visual.scale = Vector3.ONE * s
	var center := box.get_center()
	model.position -= Vector3(center.x, box.position.y, center.z)
	if is_crystal:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_overlay = crystal_glow

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size * s * (info.hit_shrink as Vector3)
	shape.shape = box_shape
	shape.position.y = box.size.y * s * 0.5
	area.add_child(shape)
	return area


## Combined AABB of all meshes under `node`, expressed in `space`'s local coordinates.
## Works on nodes that are not in the tree yet.
func _mesh_aabb(node: Node3D, space: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mesh
		while n != space and n != null:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var box: AABB = xf * (mesh as MeshInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


## Picks a lane that is clear for the next few meters (preferring crystals) and
## jumps when a barrier is right ahead in the current lane.
func _autopilot_plan() -> Dictionary:
	var blocked := {-1: false, 0: false, 1: false}
	var gems := {-1: false, 0: false, 1: false}
	var barrier_near := false
	for child in spawned.get_children():
		if not child.has_meta("kind"):
			continue
		var ahead: float = player.position.z - child.position.z
		if ahead < -1.5 or ahead > 16.0:
			continue
		var kind: String = child.get_meta("kind")
		var lane := clampi(roundi(child.position.x / LANE_WIDTH), -1, 1)
		match kind:
			"crystal":
				gems[lane] = true
			"barrier":
				if lane == player.lane and ahead < speed * 0.28 + 1.0 and ahead > 0.0:
					barrier_near = true
			"pillar":
				blocked[lane] = true
			"cart":
				for x in [child.position.x - LANE_WIDTH * 0.5, child.position.x + LANE_WIDTH * 0.5]:
					blocked[clampi(roundi(x / LANE_WIDTH), -1, 1)] = true
	var best: int = player.lane
	var best_cost := INF
	for lane in [-1, 0, 1]:
		var cost := absf(lane - player.lane) + (100.0 if blocked[lane] else 0.0) - (1.5 if gems[lane] else 0.0)
		if cost < best_cost:
			best_cost = cost
			best = lane
	return {"lane": best, "jump": barrier_near}


func _ensure_input_actions() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE, KEY_W, KEY_UP],
		"restart": [KEY_R],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

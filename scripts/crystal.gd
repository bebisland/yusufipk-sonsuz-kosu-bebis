extends Area3D
## Collectible crystal: spins and bobs in place until the player picks it up.

const SPIN_SPEED := 2.2
const BOB_HEIGHT := 0.15
const BOB_SPEED := 3.0

var base_y := 0.0
var phase := 0.0


func _ready() -> void:
	base_y = position.y
	phase = randf() * TAU


func _process(delta: float) -> void:
	phase += delta * BOB_SPEED
	rotation.y += SPIN_SPEED * delta
	position.y = base_y + sin(phase) * BOB_HEIGHT

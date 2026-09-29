extends CanvasLayer
## Score, crystal count, remaining time and the end-of-round panel.

@onready var crystal_label: Label = %CrystalLabel
@onready var score_label: Label = %ScoreLabel
@onready var time_label: Label = %TimeLabel
@onready var end_panel: Control = %EndPanel
@onready var end_title: Label = %EndTitle
@onready var end_stats: Label = %EndStats


func _ready() -> void:
	end_panel.hide()


func set_crystals(count: int) -> void:
	crystal_label.text = str(count)


func set_score(score: int) -> void:
	score_label.text = str(score)


func set_time_left(seconds: float) -> void:
	var s := int(ceil(maxf(seconds, 0.0)))
	time_label.text = "%d:%02d" % [s / 60, s % 60]


func show_end(title: String, score: int, crystals: int) -> void:
	end_title.text = title
	end_stats.text = "Skor: %d    Kristal: %d" % [score, crystals]
	end_panel.show()

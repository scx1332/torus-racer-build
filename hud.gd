extends CanvasLayer
## Presentation only: body telemetry arrives after each physics integration.

@export var target: TorusBody
@export var debug_view: Node3D
@export var race_manager: Node
@export var phase_label: String = "Phase 2 controls"
@export var location_hint: String = ""
@export var panel_width: float = 600.0

var _speed_label: Label
var _hint_label: Label
var _debug_box: VBoxContainer
var _readout: Label
var _rescue_label: Label
var _race_box: VBoxContainer
var _lap_label: Label
var _lap_history_label: Label
var _race_status_label: Label
var _assist_readout: Label


func _ready() -> void:
	layer = 10
	_build_hud()
	if is_instance_valid(race_manager) and race_manager.has_signal(&"race_updated"):
		race_manager.connect(&"race_updated", _on_race_updated)
		if race_manager.has_method(&"get_snapshot"):
			_on_race_updated(race_manager.call(&"get_snapshot"))
	if target == null:
		push_warning("HUD requires a TorusBody target.")
		return
	target.physics_sampled.connect(_on_physics_sampled)
	if target.input_reader != null:
		target.input_reader.device_changed.connect(_on_device_changed)
		_on_device_changed(target.input_reader.using_gamepad, target.input_reader.active_joypad)
	if debug_view != null:
		debug_view.connect(&"toggled", _on_debug_toggled)
		_on_debug_toggled(bool(debug_view.get(&"enabled")))


func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.name = "TelemetryPanel"
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size.x = panel_width
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.045, 0.065, 0.88)
	background.content_margin_left = 14.0
	background.content_margin_right = 14.0
	background.content_margin_top = 10.0
	background.content_margin_bottom = 10.0
	background.set_corner_radius_all(8)
	panel.add_theme_stylebox_override(&"panel", background)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 7)
	panel.add_child(column)
	var title := Label.new()
	title.text = "TORUS RACER  /  " + phase_label
	title.add_theme_color_override(&"font_color", Color("9cb7ce"))
	column.add_child(title)
	if not location_hint.is_empty():
		var location := Label.new()
		location.text = location_hint
		location.add_theme_font_size_override(&"font_size", 14)
		location.add_theme_color_override(&"font_color", Color("c9bca1"))
		column.add_child(location)
	_speed_label = Label.new()
	_speed_label.text = "0.0 km/h"
	_speed_label.add_theme_font_size_override(&"font_size", 28)
	column.add_child(_speed_label)
	_build_race_panel(column)
	_rescue_label = Label.new()
	_rescue_label.text = "IN THE WATER / returning to checkpoint" if is_instance_valid(race_manager) \
		else "IN THE WATER / returning to start"
	_rescue_label.add_theme_color_override(&"font_color", Color("77e3db"))
	_rescue_label.visible = false
	column.add_child(_rescue_label)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override(&"font_size", 15)
	column.add_child(_hint_label)
	_on_device_changed(false, -1)

	_debug_box = VBoxContainer.new()
	_debug_box.visible = false
	_debug_box.add_theme_constant_override(&"separation", 6)
	column.add_child(_debug_box)
	_debug_box.add_child(HSeparator.new())
	_readout = Label.new()
	_readout.add_theme_font_size_override(&"font_size", 16)
	_debug_box.add_child(_readout)
	_assist_readout = Label.new()
	_assist_readout.add_theme_font_size_override(&"font_size", 14)
	_assist_readout.add_theme_color_override(&"font_color", Color("9cb7ce"))
	_debug_box.add_child(_assist_readout)
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.scroll_active = false
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.add_theme_font_size_override(&"normal_font_size", 14)
	legend.text = (
		"[color=#ffffff]● Contact[/color]   [color=#65e572]↑ Normal[/color]   "
		+ "[color=#ffad42]↑ Traction (estimated)[/color]   [color=#48cfff]↑ Velocity[/color]\n"
		+ "[color=#cb86ff]↑ Angular velocity[/color]   [color=#fff06a]↑ Player torque[/color]\n"
		+ "[color=#ff73b4]↑ Assist torque[/color]   [color=#ff5f65]↑ Gyro torque[/color]\n"
		+ "[color=#64e4c6]↑ Bank pivot force[/color]"
	)
	_debug_box.add_child(legend)


func _build_race_panel(column: VBoxContainer) -> void:
	_race_box = VBoxContainer.new()
	_race_box.name = "RacePanel"
	_race_box.visible = is_instance_valid(race_manager)
	_race_box.add_theme_constant_override(&"separation", 3)
	column.add_child(_race_box)
	_lap_label = Label.new()
	_lap_label.add_theme_font_size_override(&"font_size", 22)
	_race_box.add_child(_lap_label)
	_lap_history_label = Label.new()
	_lap_history_label.add_theme_font_size_override(&"font_size", 15)
	_lap_history_label.add_theme_color_override(&"font_color", Color("9cb7ce"))
	_race_box.add_child(_lap_history_label)
	_race_status_label = Label.new()
	_race_status_label.add_theme_font_size_override(&"font_size", 15)
	_race_box.add_child(_race_status_label)
	_on_race_updated({})


func _on_race_updated(snapshot: Dictionary) -> void:
	var lap := maxi(1, int(snapshot.get("lap_number", 1)))
	_lap_label.text = "LAP %d  |  %s" % [lap, _format_time(snapshot.get("lap_time", 0.0))]
	var best: float = snapshot.get("best_lap", 0.0)
	var previous: float = snapshot.get("last_lap", 0.0)
	_lap_history_label.text = "Best %s  ·  Last %s" % [
		_format_time(best) if best > 0.0 else "—", _format_time(previous) if previous > 0.0 else "—"]
	var valid: bool = snapshot.get("lap_valid", true)
	_race_status_label.add_theme_color_override(&"font_color", Color("77e3db") if valid else Color("ffb478"))
	if not snapshot.get("started", false):
		_race_status_label.text = "Cross the start line"
		return
	var count := maxi(1, int(snapshot.get("checkpoint_count", 6)))
	var next := clampi(int(snapshot.get("next_gate", 1)), 0, count)
	var passed := count if next == 0 else next - 1
	_race_status_label.text = "Checkpoints %d/%d  ·  %s" % [passed, count,
		"Finish ahead" if next == 0 else "Next CP %d" % next]
	if not valid:
		_race_status_label.text += "\nLAP INVALID — reset used"


static func _format_time(seconds: float) -> String:
	var milliseconds := maxi(0, int(round(seconds * 1000.0)))
	return "%d:%02d.%03d" % [milliseconds / 60000, (milliseconds / 1000) % 60, milliseconds % 1000]


func _on_physics_sampled(snapshot: Dictionary) -> void:
	var speed: float = snapshot.get("speed", 0.0)
	_speed_label.text = "%.1f km/h" % (speed * 3.6)
	_rescue_label.visible = snapshot.get("water_pending", false)
	if not _debug_box.visible:
		return
	var spin: float = snapshot.get("spin_rate", 0.0)
	var lean: float = snapshot.get("lean_degrees", 0.0)
	var grounded: bool = snapshot.get("grounded", false)
	var slip: float = snapshot.get("slip_ratio", 0.0)
	_readout.text = (
		"Speed %.2f m/s  |  Spin %.2f rad/s (%.0f rpm)\n"
		+ "Lean %+.1f°  |  Grounded %s  |  Slip %.3f"
	) % [speed, spin, spin * 60.0 / TAU, lean, "yes" if grounded else "no", slip]
	_update_assist_readout()


func _update_assist_readout() -> void:
	if target != null and target.tuning != null and target.tuning.direct_lean:
		_assist_readout.text = "Direct lean · tap to bank\nBank-pivot assist: off"
		return
	var pivot := target.tuning.lean_pivot_strength if target != null and target.tuning != null else 0.0
	_assist_readout.text = "Bank-pivot strength %.2f\nPhase 3 assists: not implemented" % pivot


func _on_device_changed(gamepad: bool, _device: int) -> void:
	if gamepad:
		_hint_label.text = (
			"RT Accelerate · LT Brake · Left stick Lean\n"
			+ "A / Cross Hop · Y / Triangle Reset · Back / Select Physics debug"
		)
	else:
		_hint_label.text = (
			"↑ Accelerate · ↓ Brake · ← / → Lean\n"
			+ "Space Hop · R Reset · D Physics debug"
		)


func _on_debug_toggled(value: bool) -> void:
	_debug_box.visible = value
	if value:
		_update_assist_readout()

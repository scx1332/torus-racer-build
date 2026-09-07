extends SceneTree
## Frozen presentation fixtures: race signals and live tuning never write physics.

const HUD := preload("res://hud.gd")
const LAB := preload("res://controls_lab.tscn")

class TestRace extends Node:
	signal race_updated(snapshot: Dictionary)
	var snapshot: Dictionary = {}
	func get_snapshot() -> Dictionary:
		return snapshot

var _checks: int = 0
var _failures: int = 0
var _hud: CanvasLayer
var _race: TestRace


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lab := LAB.instantiate()
	var body := lab.get_node("Torus") as TorusBody
	body.freeze = true
	root.add_child(lab)
	var legacy := lab.get_node("HUD")
	_check(legacy.race_manager == null and not legacy._race_box.visible,
		"Controls lab loads without race state or a race panel")
	_check(not legacy._debug_box.visible, "Physics debug remains off by default")
	body.physics_sampled.emit({"speed": 10.0, "water_pending": true})
	_check(legacy._speed_label.text == "36.0 km/h" and legacy._rescue_label.visible,
		"Legacy speed and water-rescue telemetry still work")
	_race = TestRace.new()
	root.add_child(_race)
	_hud = HUD.new()
	_hud.target = body
	_hud.debug_view = lab.get_node("TorusDebug")
	_hud.race_manager = _race
	root.add_child(_hud)
	_check(_hud._rescue_label.text == "IN THE WATER / returning to checkpoint"
		and legacy._rescue_label.text == "IN THE WATER / returning to start",
		"Race rescue names the checkpoint while the lab keeps its original start hint")
	var before := body.transform
	var linear := body.linear_velocity
	var angular := body.angular_velocity
	_test_race_signals()
	_test_late_join(body)
	_test_debug(body, lab.get_node("TorusDebug"))
	_check(body.transform == before and body.linear_velocity == linear and body.angular_velocity == angular,
		"Race HUD and debug updates do not alter body state")
	_hud.free()
	_race.free()
	lab.free()
	print("RACE HUD %s checks=%d failures=%d" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_race_signals() -> void:
	_check(_hud._race_box.visible and _hud._race_status_label.text == "Cross the start line",
		"Race panel starts with a start-line hint")
	_check(_hud._lap_label.text == "LAP 1  |  0:00.000", "Unstarted clock shows the first lap at zero")
	_check(_hud._lap_history_label.text == "Best —  ·  Last —", "Missing records use placeholders")
	_check(HUD._format_time(61.234) == "1:01.234", "Lap timer formats minutes, seconds, milliseconds")
	_check(HUD._format_time(59.9996) == "1:00.000", "Rounding across a minute carries correctly")
	_check(HUD._format_time(600.001) == "10:00.001", "Long laps preserve minute digits")
	_check(HUD._format_time(-1.0) == "0:00.000", "Clock never displays negative time")
	var sample := {"started": true, "lap_number": 1, "lap_time": 12.345,
		"best_lap": 0.0, "last_lap": 0.0, "next_gate": 1, "checkpoint_count": 6, "lap_valid": true}
	_race.race_updated.emit(sample)
	_check(_hud._lap_label.text == "LAP 1  |  0:12.345", "Race signal updates the running timer")
	_check(_hud._race_status_label.text == "Checkpoints 0/6  ·  Next CP 1", "Started lap shows the first checkpoint")
	sample.next_gate = 4
	_race.race_updated.emit(sample)
	_check(_hud._race_status_label.text == "Checkpoints 3/6  ·  Next CP 4", "Checkpoint progress updates in order")
	sample.next_gate = 0
	_race.race_updated.emit(sample)
	_check(_hud._race_status_label.text == "Checkpoints 6/6  ·  Finish ahead", "Final checkpoint directs the player to finish")
	sample.lap_number = 2
	sample.lap_time = 0.125
	sample.best_lap = 63.789
	sample.last_lap = 64.012
	sample.next_gate = 1
	_race.race_updated.emit(sample)
	_check(_hud._lap_label.text == "LAP 2  |  0:00.125", "New lap updates the number and resets the displayed clock")
	_check(_hud._lap_history_label.text == "Best 1:03.789  ·  Last 1:04.012", "Best and last laps have millisecond precision")
	sample.lap_valid = false
	_race.race_updated.emit(sample)
	_check(_hud._race_status_label.text.contains("LAP INVALID — reset used"), "Reset invalidation is explicit")
	_check(_hud._lap_history_label.text.contains("Best 1:03.789"), "Invalid lap does not hide the established best")
	sample.lap_valid = true
	_race.race_updated.emit(sample)
	_check(not _hud._race_status_label.text.contains("INVALID"), "A valid next lap clears the invalid status")


func _test_debug(body: TorusBody, debug: Node3D) -> void:
	debug.toggled.emit(true)
	_check(_hud._debug_box.visible, "Physics debug signal reveals the tuning panel")
	_check(_hud._assist_readout.text.contains("Direct lean") \
		and _hud._assist_readout.text.contains("Bank-pivot assist: off"),
		"Default direct lean reports the inactive pivot truthfully")
	body.tuning.direct_lean = false
	body.physics_sampled.emit({"speed": 0.0})
	_check(_hud._assist_readout.text.contains("Bank-pivot strength %.2f" % body.tuning.lean_pivot_strength),
		"Existing pivot strength is shown truthfully")
	_check(_hud._assist_readout.text.contains("Phase 3 assists: not implemented"), "HUD does not imply deferred assists exist")
	var initial_strength := body.tuning.lean_pivot_strength
	body.tuning.lean_pivot_strength = 0.35
	body.physics_sampled.emit({"speed": 7.0, "lean_degrees": -20.0, "grounded": true, "water_pending": false})
	_check(_hud._assist_readout.text.contains("Bank-pivot strength 0.35"), "Inspector tuning changes appear on the next sample")
	_check(_hud._speed_label.text == "25.2 km/h" and not _hud._rescue_label.visible,
		"Race HUD retains normal physics and rescue updates")
	_check(_hud._readout.text.contains("Lean -20.0°"), "Existing detailed physics readout remains intact")
	body.tuning.lean_pivot_strength = initial_strength
	body.tuning.direct_lean = true
	debug.toggled.emit(false)
	_check(not _hud._debug_box.visible and _hud._race_box.visible, "Hiding debug leaves race information visible")


func _test_late_join(body: TorusBody) -> void:
	var race := TestRace.new()
	race.snapshot = {"started": true, "lap_number": 3, "lap_time": 20.5, "next_gate": 2}
	root.add_child(race)
	var hud := HUD.new()
	hud.target = body
	hud.race_manager = race
	root.add_child(hud)
	_check(hud._lap_label.text == "LAP 3  |  0:20.500", "Late HUD initialization reads the manager's current snapshot")
	_check(hud._race_status_label.text == "Checkpoints 1/6  ·  Next CP 2", "Late HUD initialization preserves checkpoint progress")
	hud.free()
	race.free()


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures += 1
		push_error("FAIL: " + message)

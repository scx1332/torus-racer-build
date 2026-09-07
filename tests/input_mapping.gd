extends SceneTree
## Exercise real mapped events, including overlapping keyboard/gamepad sources.

var _reader: TorusInput
var _failures: Array[String] = []
var _checks: int = 0
var _device: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Input.use_accumulated_input = false
	_reader = TorusInput.new()
	_reader.tuning = TorusTuning.new()
	root.add_child(_reader)
	_test_mappings()
	_test_analog()
	_test_overlapping_sources()
	_test_stick_drift()
	_test_device_hints()
	_clear_events()
	for failure in _failures:
		push_error("FAIL: " + failure)
	print("INPUT MAPPING %s checks=%d failures=%d" % [
		"PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _test_mappings() -> void:
	var keys := {
		&"accelerate": KEY_UP, &"brake": KEY_DOWN,
		&"lean_left": KEY_LEFT, &"lean_right": KEY_RIGHT,
		&"hop": KEY_SPACE, &"reset": KEY_R, &"debug_toggle": KEY_D,
	}
	for action in keys:
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		_check(InputMap.action_has_event(action, key), "%s keyboard mapping" % action)
		_near(InputMap.action_get_deadzone(action), 0.0, "%s deadzone applied in reader" % action)
	for entry in [
		[&"accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0],
		[&"brake", JOY_AXIS_TRIGGER_LEFT, 1.0],
		[&"lean_left", JOY_AXIS_LEFT_X, -1.0],
		[&"lean_right", JOY_AXIS_LEFT_X, 1.0],
	]:
		var event := InputEventJoypadMotion.new()
		event.device = -1
		event.axis = entry[1]
		event.axis_value = entry[2]
		_check(InputMap.action_has_event(entry[0], event), "%s gamepad axis mapping" % entry[0])
	for entry in [[&"hop", JOY_BUTTON_A], [&"reset", JOY_BUTTON_Y], [&"debug_toggle", JOY_BUTTON_BACK]]:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = entry[1]
		_check(InputMap.action_has_event(entry[0], event), "%s gamepad button mapping" % entry[0])
	var extra_key := InputEventKey.new()
	extra_key.physical_keycode = KEY_W
	InputMap.action_add_event(&"accelerate", extra_key)
	TorusInput.install_actions()
	_check(InputMap.action_has_event(&"accelerate", extra_key), "install preserves custom bindings")
	_check(InputMap.action_get_events(&"accelerate").size() == 3, "install is idempotent")
	InputMap.action_erase_event(&"accelerate", extra_key)


func _test_analog() -> void:
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.25)
	_near(_reader.sample().x, 0.25, "RT keeps proportional quarter strength")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.6)
	_near(_reader.sample().x, 0.25, "RT remains held when LT is pressed")
	_near(_reader.sample().y, 0.6, "LT independently keeps proportional strength")
	_axis(JOY_AXIS_LEFT_X, 0.1)
	_near(_reader.sample().z, 0.0, "positive stick noise is inside deadzone")
	_axis(JOY_AXIS_LEFT_X, -0.1)
	_near(_reader.sample().z, 0.0, "negative stick noise is inside deadzone")
	_axis(JOY_AXIS_LEFT_X, 0.575)
	_near(_reader.sample().z, pow(0.5, 1.5), "stick deadzone remaps before response curve")
	_axis(JOY_AXIS_LEFT_X, -0.575)
	_near(_reader.sample().z, -pow(0.5, 1.5), "left steering uses same response curve")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_key(KEY_LEFT, true)
	_near(_reader.sample().z, -1.0, "left keyboard steering remains full strength")
	_key(KEY_LEFT, false)
	_key(KEY_RIGHT, true)
	_near(_reader.sample().z, 1.0, "right keyboard steering remains full strength")
	_key(KEY_RIGHT, false)
	_clear_events()


func _test_overlapping_sources() -> void:
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.4)
	_key(KEY_UP, true)
	_near(_reader.sample().x, 1.0, "keyboard overrides weaker held trigger")
	_key(KEY_UP, false)
	_near(_reader.sample().x, 0.4, "key release preserves held trigger")
	_key(KEY_UP, true)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_near(_reader.sample().x, 1.0, "trigger release preserves held keyboard key")
	_key(KEY_UP, false)
	_near(_reader.sample().x, 0.0, "both sources released clears acceleration")
	_axis(JOY_AXIS_LEFT_X, 0.575)
	_key(KEY_RIGHT, true)
	_near(_reader.sample().z, 1.0, "keyboard steering overrides weaker held stick")
	_key(KEY_RIGHT, false)
	_near(_reader.sample().z, pow(0.5, 1.5), "key release preserves held analog steering")
	# Intentional opposing input subtracts each direction's shaped strength.
	# A half-response stick contributes 0.5^1.5 against a full-strength key.
	_axis(JOY_AXIS_LEFT_X, -0.575)
	_key(KEY_RIGHT, true)
	_near(_reader.sample().z, 1.0 - pow(0.5, 1.5), "left stick opposes right key after shaping")
	_key(KEY_LEFT, true)
	_near(_reader.sample().z, 0.0, "both full-strength keys cancel with a held stick")
	_key(KEY_RIGHT, false)
	_near(_reader.sample().z, -1.0, "left key overrides same-side analog steering")
	_key(KEY_LEFT, false)
	_near(_reader.sample().z, -pow(0.5, 1.5), "left key release preserves held stick")
	_axis(JOY_AXIS_LEFT_X, 0.575)
	_key(KEY_LEFT, true)
	_near(_reader.sample().z, pow(0.5, 1.5) - 1.0, "right stick opposes left key after shaping")
	_axis(JOY_AXIS_LEFT_X, -0.575)
	_near(_reader.sample().z, -1.0, "stick crossing sides restores full held key strength")
	_axis(JOY_AXIS_LEFT_X, 0.0)
	_near(_reader.sample().z, -1.0, "stick release preserves held left key")
	_clear_events()


func _test_stick_drift() -> void:
	for noise in [0.1, -0.1, 0.14, -0.14]:
		_axis(JOY_AXIS_LEFT_X, noise)
		_near(_reader.sample().z, 0.0, "idle stick drift %+.2f is ignored" % noise)
		_key(KEY_LEFT, true)
		_near(_reader.sample().z, -1.0, "left key stays full with stick drift %+.2f" % noise)
		_key(KEY_LEFT, false)
		_near(_reader.sample().z, 0.0, "released key leaves only ignored drift %+.2f" % noise)
		_key(KEY_RIGHT, true)
		_near(_reader.sample().z, 1.0, "right key stays full with stick drift %+.2f" % noise)
		_key(KEY_RIGHT, false)
	_clear_events()


func _test_device_hints() -> void:
	_key(KEY_UP, true)
	_check(not _reader.using_gamepad and _reader.active_joypad == -1, "keyboard switches hints")
	_axis(JOY_AXIS_LEFT_X, 0.1)
	_check(not _reader.using_gamepad, "stick noise does not switch hints")
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.01)
	_check(not _reader.using_gamepad, "trigger noise does not switch hints")
	_axis(JOY_AXIS_LEFT_X, 0.3)
	_check(_reader.using_gamepad and _reader.active_joypad == _device, "meaningful stick input selects controller")
	_key(KEY_UP, false)
	_check(_reader.using_gamepad, "key release does not switch hints")
	_key(KEY_D, true)
	_check(not _reader.using_gamepad, "debug key switches back to keyboard hints")
	_key(KEY_D, false)
	_button(JOY_BUTTON_A, true)
	_check(_reader.using_gamepad, "controller button switches hints")
	_check(Input.is_action_pressed(&"hop"), "A button activates hop")
	_button(JOY_BUTTON_A, false)
	_button(JOY_BUTTON_Y, true)
	_check(Input.is_action_pressed(&"reset"), "Y button activates reset")
	_button(JOY_BUTTON_Y, false)
	_button(JOY_BUTTON_BACK, true)
	_check(Input.is_action_pressed(&"debug_toggle"), "Back button activates debug")
	_button(JOY_BUTTON_BACK, false)
	# Simulate the disconnect notification without disconnecting real hardware.
	Input.joy_connection_changed.emit(_device, false)
	_check(not _reader.using_gamepad and _reader.active_joypad == -1, "unplug falls back to keyboard hints")


func _axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = _device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = _device
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _clear_events() -> void:
	for code in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SPACE, KEY_R, KEY_D]:
		_key(code, false)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	_axis(JOY_AXIS_LEFT_X, 0.0)


func _near(actual: float, expected: float, context: String) -> void:
	_check(absf(actual - expected) < 0.0001, "%s: expected %.5f, got %.5f" % [context, expected, actual])


func _check(passed: bool, context: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(context)

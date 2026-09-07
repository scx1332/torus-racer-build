class_name TorusInput
extends Node
## Samples shared keyboard/gamepad actions without applying any physics.

signal device_changed(using_gamepad: bool, device: int)

const ACTIONS: Array[StringName] = [
	&"accelerate", &"brake", &"lean_left", &"lean_right", &"hop", &"reset", &"debug_toggle"
]
const TRIGGER_ACTIVITY_THRESHOLD: float = 0.05

@export var tuning: TorusTuning

var active_joypad: int = -1
var using_gamepad: bool = false


static func install_actions() -> void:
	# The configurable stick deadzone is applied exactly once, in sample().
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.0)
		InputMap.action_set_deadzone(action, 0.0)
	_add_key(&"accelerate", KEY_UP)
	_add_key(&"brake", KEY_DOWN)
	_add_key(&"lean_left", KEY_LEFT)
	_add_key(&"lean_right", KEY_RIGHT)
	_add_key(&"hop", KEY_SPACE)
	_add_key(&"reset", KEY_R)
	_add_key(&"debug_toggle", KEY_D)
	_add_axis(&"accelerate", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_axis(&"brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_axis(&"lean_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis(&"lean_right", JOY_AXIS_LEFT_X, 1.0)
	_add_button(&"hop", JOY_BUTTON_A)
	_add_button(&"reset", JOY_BUTTON_Y)
	_add_button(&"debug_toggle", JOY_BUTTON_BACK)


static func _add_key(action: StringName, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	_add_event(action, event)


static func _add_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = -1 # Every connected controller shares the same action map.
	event.axis = axis
	event.axis_value = value
	_add_event(action, event)


static func _add_button(action: StringName, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	_add_event(action, event)


static func _add_event(action: StringName, event: InputEvent) -> void:
	# Reopening the scene must not duplicate mappings or discard custom bindings.
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _ready() -> void:
	install_actions()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func sample() -> Vector3:
	# Separate strengths allow both triggers to contribute to the same tick.
	var acceleration := Input.get_action_strength(&"accelerate")
	var braking := Input.get_action_strength(&"brake")
	var right := Input.get_action_strength(&"lean_right")
	var left := Input.get_action_strength(&"lean_left")
	var deadzone := _stick_deadzone()
	var exponent := maxf(tuning.response_exponent, 0.01) if tuning != null else 1.5
	# Filter each direction before mixing: opposite stick drift must not weaken
	# a held key. Intentional opposing inputs subtract their shaped strengths.
	right = pow(clampf((right - deadzone) / (1.0 - deadzone), 0.0, 1.0), exponent)
	left = pow(clampf((left - deadzone) / (1.0 - deadzone), 0.0, 1.0), exponent)
	return Vector3(acceleration, braking, right - left)


func _stick_deadzone() -> float:
	return clampf(tuning.stick_deadzone, 0.0, 0.95) if tuning != null else 0.15


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		for action in ACTIONS:
			if event.is_action(action):
				_set_active_device(-1)
				return
	elif event is InputEventJoypadButton and event.pressed:
		_set_active_device(event.device)
	elif event is InputEventJoypadMotion:
		var meaningful := false
		if event.axis == JOY_AXIS_LEFT_X:
			meaningful = absf(event.axis_value) > _stick_deadzone()
		elif event.axis == JOY_AXIS_TRIGGER_LEFT or event.axis == JOY_AXIS_TRIGGER_RIGHT:
			meaningful = event.axis_value > TRIGGER_ACTIVITY_THRESHOLD
		if meaningful:
			_set_active_device(event.device)


func _set_active_device(device: int) -> void:
	if active_joypad == device:
		return
	active_joypad = device
	using_gamepad = device >= 0
	device_changed.emit(using_gamepad, active_joypad)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected and device == active_joypad:
		_set_active_device(-1)

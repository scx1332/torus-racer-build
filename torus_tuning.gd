class_name TorusTuning
extends Resource
## Live input tuning. Arcade assists will be added in Phase 3.

@export_group("Player torques (N m)")
## Use the PR's tap-to-lean torque; disable for the previous bank-angle controller.
@export var direct_lean: bool = true
@export_range(0.0, 100.0, 0.1) var acceleration_torque: float = 18.0
@export_range(0.0, 100.0, 0.1) var braking_torque: float = 24.0
## Acts about the ring's in-plane up axis; lean rate is roughly torque / (I_axle * spin).
@export_range(0.0, 100.0, 0.1) var lean_torque: float = 24.0

@export_group("Motorcycle bank control")
@export_range(5.0, 45.0, 0.5) var lean_angle_limit: float = 25.0
@export_range(5.0, 120.0, 1.0) var lean_rate_limit: float = 40.0
@export_range(0.1, 10.0, 0.1) var lean_response: float = 3.0
@export_range(0.0, 60.0, 0.1) var lean_damping: float = 20.0
@export_range(0.0, 20.0, 0.1) var lean_low_spin_torque: float = 4.0

@export_group("Grounded bank pivot (manual assist)")
@export_range(0.0, 1.0, 0.05) var lean_pivot_strength: float = 1.0
@export_range(0.0, 0.5, 0.01) var lean_pivot_height: float = 0.05
@export_range(1.0, 120.0, 1.0) var lean_pivot_response: float = 40.0
@export_range(0.0, 50.0, 0.5) var lean_pivot_max_acceleration: float = 20.0

@export_group("Analog response")
@export_range(0.0, 0.9, 0.01) var stick_deadzone: float = 0.15
@export_range(0.2, 4.0, 0.05) var response_exponent: float = 1.5

@export_group("Ground contact and hop")
@export_range(0.0, 40.0, 0.1) var hop_impulse: float = 10.5
@export_range(0.0, 1.0, 0.01) var ground_normal_min_dot: float = 0.55
@export_range(0.02, 0.3, 0.01) var hop_rearm_airtime: float = 0.08

@export_group("Gamepad rumble")
@export var rumble_enabled: bool = true
@export_range(0.0, 10.0, 0.1) var landing_rumble_speed: float = 1.5
@export_range(0.1, 50.0, 0.1) var collision_rumble_impulse: float = 5.0
@export_range(0.05, 1.0, 0.01) var rumble_cooldown: float = 0.2

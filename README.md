# Torus Racer — Coastline Run

A Godot **4.7.x** GDScript physics experiment using **built-in Jolt**.
Godot **4.7.2** and the **.NET 10.0.303 SDK** (installer tooling only) are pinned
in `mise.toml`:

```sh
mise install
mise run play
# Or open the editor:
mise exec -- godot --editor --path .
```

Press **F5** to play the coastal circuit, or open `track.tscn` and press **F6**.
Phases 1, 2 and 4 are implemented. The track and game loop were brought forward
at the user's request; Phase 3 general arcade assists remain paused.

## Windows build

The checked-in `export_presets.cfg` contains the **Windows Desktop** preset for
x86_64. Install matching **Godot 4.7.2 export templates** once via
**Editor > Manage Export Templates**, selecting Windows x86_64. Installing the
editor with `mise install` does not install these separate templates.

```sh
mise run build-windows
```

This imports the project, creates `build/windows`, then exports a release build:
`TorusRacer.exe` and `TorusRacer.pck`. Keep both files together; players do not
need the Godot editor. Tests and previous build outputs are excluded from the
pack, while the inherited lab scenes remain as required track dependencies.
Build outputs are ignored by Git. To invoke the exporter directly after import:

```sh
mise exec -- godot --headless --path . --script tools/prepare_windows_export.gd
mise exec -- godot --headless --path . --export-release "Windows Desktop" build/windows/TorusRacer.exe
```

This produces a playable build, **not an installer**. Players do not need .NET;
it is used only to build the MSI below.
See [Godot export documentation](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html).

### WiX MSI installer (Windows host)

`installer/TorusRacer.wixproj` pins **WiX Toolset 7.0.0**, restored automatically
through NuGet. `global.json` requires the same .NET SDK version as mise. WiX uses
native Windows tools and `msi.dll`: exporting the game on Linux works, but building
the MSI requires Windows. Copy the repository and `build/windows` to a Windows
machine, or export the game there first. Run commands from the repository root.

WiX 7 requires explicit acceptance of its [OSMF terms](https://docs.firegiant.com/wix/osmf/).
The project owner has accepted these terms for this build. The mise task supplies
`-p:AcceptEula=wix7` explicitly; it does not change global WiX license settings.
Build on Windows with:

```powershell
mise install
mise run build-installer
```

This packages an existing export and deliberately does not re-export the game.
For a custom version, use the direct command:

```powershell
mise exec -- dotnet build installer/TorusRacer.wixproj --configuration Release -p:AcceptEula=wix7 -p:ProductVersion=0.4.1
```

The output is `build/installer/TorusRacer.msi`, an x64, per-user installer with
the EXE and PCK embedded in a single MSI. It installs in
`%LOCALAPPDATA%\TorusRacer` and creates a Start Menu shortcut. Neither .NET nor
Godot needs to be installed on the player's computer. Saved lap times live in
Godot's separate user-data directory and are not deleted by uninstalling.

The default installer version is `0.4.0`. Pass `-p:ProductVersion=0.4.1` for a
subsequent build; increase the three-part version for upgrades and keep the
`UpgradeCode` in `Package.wxs` unchanged. Rebuilds with the same version replace
one another instead of registering duplicate installations, so use distinct
three-part versions for published releases (not a fourth build-number field).
The EXE and MSI are currently unsigned.

Test on Windows: install the MSI, launch **Torus Racer** from Start Menu, then
build/install the same and a higher version and verify that only one installation
remains registered. Finally uninstall and
check that the shortcut and game files are removed while saved lap times remain.

### GitHub Actions

CI runs in the public sibling repository
[`scx1332/torus-racer-build`](https://github.com/scx1332/torus-racer-build), so this
project can live in a private repository without spending Actions minutes there. That
repository holds no game code: both workflows check out `scx1332/torus-racer` over SSH
using `SOURCE_REPO_SSH_KEY`, an Actions secret holding the private half of a read-only
deploy key of this repository. Revoke it from **Settings > Deploy keys** here if the
build repository is ever compromised. The workflows are also gated on
`github.repository == 'scx1332/torus-racer-build'`, so a copy of this tree never runs
them anywhere else.

Ask for a run of both workflows on the current commit with:

```sh
gh api repos/scx1332/torus-racer-build/dispatches \
  -f event_type=source-push -F client_payload[ref]="$(git rev-parse HEAD)"
```

Each workflow also has **Actions > … > Run workflow**, whose `ref` input takes any
branch, tag or commit of this repository and defaults to `main`. Pushes to the build
repository itself only change the workflow files, so they run against `main` here.

`.github/workflows/tests.yml` runs the whole `mise run validate` suite on
`ubuntu-24.04`. It installs the pinned Godot with mise, plus the X11, GL and ALSA
libraries the stock Godot Linux build links against even when it runs headless. A full
run takes about four minutes.

`.github/workflows/windows-installer.yml` builds on `windows-2025`. Its manual form
optionally overrides the MSI version (`X.Y.Z`); leave it empty to use the project
default. It does not publish a GitHub Release.

The workflow installs Godot and an isolated .NET SDK with mise, verifies their
versions, downloads official matching Godot templates, checks the archive's pinned
SHA256 and caches only the Windows x64 templates. When updating Godot, update
`GODOT_VERSION` and `GODOT_TEMPLATES_SHA256` in the workflow together with `mise.toml`.
The first uncached run downloads the full export-template archive (about 1.2 GB).

After exporting and building the MSI, the runner installs it, starts the installed
game headlessly, and uninstalls it while checking files and the Start Menu shortcut.
`tools/test_windows_installer.ps1` refuses non-GitHub-hosted environments and existing
installations; it is only for disposable CI runners, not a local uninstall helper.
Graphics, controller input and audible playback still need a manual Windows test.

Successful runs expose two downloadable artifacts: `TorusRacer-MSI-<run>` containing
`TorusRacer.msi`, and `TorusRacer-Windows-<run>` containing the portable EXE + PCK.
Build artifacts expire after 14 days; installer test logs are retained for 7 days
even when the test fails. No signing certificate is required, and `SOURCE_REPO_SSH_KEY`
is the only secret. Actions are pinned to immutable commits, the workflow's own token
stays read-only, and neither credential is persisted into the checkout.

## Coastline circuit

The new starting scene is a roughly **1.03 km island circuit**, with 24 m of
asphalt, striped shoulders, low collision barriers, two broad banked bends,
and one 3 m launch crest. The landing is continuous road, not a compulsory gap.
Ease off the accelerator before corners; the body still uses the lean
steering and real ground contact. **R** returns to the last passed checkpoint
(the start gantry approach before the race begins).
Falling into the sea produces a splash and automatically returns you to the
last checkpoint after 0.75 s.

Warm coastal lighting, turquoise water, shoreline foam, sandstone cliffs,
palms, a lighthouse and harbor frame the road. Start/finish graphics, banners
and chevrons identify the route. The road, guardrails, grass, cliffs and beach
carry static collision. Terrain collision matches its visible mesh, so leaving
the asphalt no longer makes the torus fall through the grass into hidden water.
Palms, rocks and harbor furniture are cosmetic and batched where useful.
Concave mesh colliders belong only to static road/terrain bodies—the torus
remains a dynamic 64-capsule compound.

`track_layout.gd` defines the shared centerline, bank transitions and jump.
`track_builder.gd` extrudes the road, including cross-width subdivisions to
avoid height dips through bank transitions. `track_scenery.gd` and
`track_props.gd` keep decorations separate from the simulation. Ocean animation
is shader-only and never drives physics.

`WaterHazard` tests the torus's lowest point against the ocean's nominal level
inside its 3 km square bounds. The vertical extent accounts for the ring's
current bank, including lying flat. A 0.30 m immersion margin avoids triggering
on the cosmetic waves (maximum amplitude 0.26 m); a half-space test also catches
fast falls without tunneling through a thin trigger volume. Detection and the
reset countdown run inside `_integrate_forces`. There is no buoyancy simulation.
During rescue the camera stays at the splash and driving input is suspended;
R can skip the delay. The `WaterHazard` node exposes the margin, delay and enable
switch. Removing `WaterEffects` or `GameAudio` never disables rescue.

Use `mise run controls-lab` for the original flat playable scene, or
`mise run physics-lab` for the automatic physics experiment. Both remain
independent of the new track.

The torus starts with a spin impulse and rolls through ground friction. The
camera follows travel from directly behind the ring. The
playable scene has no automatic nudge, uses a 64-capsule rim and zero linear
damping so the ring coasts with only contact losses. Tap lean inputs while
moving: a held key leans the ring past its balance point, and at low speed the
unassisted ring can fall over. Reset to recover at the last checkpoint.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Accelerate | Up | RT, proportional |
| Brake | Down | LT, proportional |
| Lean | Left / Right | Left stick X, proportional |
| Hop | Space | A / Cross |
| Reset | R | Y / Triangle |
| Physics debug | D | Back / Select |

Keyboard and gamepad work simultaneously. HUD hints follow the last meaningful
input device, ignoring stick noise. Input Map actions are installed at startup
by `torus_input.gd`; their deadzones are zero so the configurable stick deadzone
is applied once. Default stick response is `sign(x) * ((abs(x)-0.15)/0.85)^1.5`
outside the deadzone. Keyboard keys retain full strength.

Driving and braking use torque inside `_integrate_forces`; RT and LT contribute
independently to the net axle torque. Steering in the default direct-lean mode
is deliberately back-to-basics and **kinematic**: while the ring is grounded,
holding left/right rotates the whole body about its averaged ground support
point, around the travel axis, at `Lean Rate Limit` degrees per second
(default 40). The bottom stays planted while the top swings over — held long
enough, all the way to lying flat. Right input always tips the top toward
camera-right relative to the direction of travel. No steering torque or helper
impulse is applied; the spin angular velocity is rotated along with the body so
the gyroscope does not fight the imposed lean. In flight or at a standstill with
no support contacts, direct-lean input does nothing. Releasing the input keeps
the lean angle; gravity on the leaned rolling ring then turns it, as with a
rolling coin, and opposite input straightens it again. Braking opposes current
spin and caps its one-step effect at zero; LT alone does not drive in reverse.
Contacts can still rotate a stopped ring, as expected in a free rigid-body
simulation.

For comparison, disable `Direct Lean` in `TorusTuning` to use the previous
bank-angle controller (its original torque cap was 30 N·m). In this optional mode,
left/right requests a **bank angle**, not a yaw rate. Full input requests
25 degrees; the shaped analog value scales that target. A gyro-aware torque
changes bank about the travel direction, using the perpendicular torque axis
(`up` projected into the ring plane). At very low spin, ordinary roll torque
provides control instead. Turning then emerges from bank, spin and ground
contact. A brief initial countersteer is possible; no heading or velocity is
assigned. Releasing input applies no bank torque and does not automatically
return the body upright. Bank-rate feedback damps rocking without damping axle
spin. At high speed, changing sides takes longer because the bank actuator has
a finite torque cap and must redirect greater angular momentum.

Only in that optional bank-angle mode, the **manual lower pivot** is a separate, explicit contact assist.
While banking on support it applies bounded impulses **at the support point**,
5 cm above the averaged ground contacts by default. It reduces lateral/vertical
velocity at that point using the full angular velocity and contact effective
mass, including the impulse's angular reaction. It adds no forward impulse,
does not relocate the center of mass, and disables on hop or loss of support.
Applying this correction at the center of mass instead would suppress the
contact torque needed for a natural turn. This is a soft contact constraint,
not a fixed joint or a kinematic transform rotation.
Set `Lean Pivot Strength` to zero to compare against unassisted contacts.

Hop applies one vertical impulse only on an upward-facing support contact.
Wall contacts do not qualify. Holding the button or pressing it again in flight
does not add jumps or queue a jump on landing. Another hop requires landing and
a fresh press. Rumble is optional on landings and hard collisions.

Reset cancels linear and angular momentum with impulses, then relocates to the
checkpoint inside the integration callback. It applies the launch spin again
on the following tick. The spawn point is the initial checkpoint;
`TorusBody.set_checkpoint(Transform3D)` supplies later checkpoints. Camera
placement resets with the body.

## Live tuning and debug

While running in the editor, select **Remote > Track > Torus > Tuning**
(or **ControlsLab > Torus > Tuning** in the flat lab).
The `TorusTuning` resource exposes acceleration/braking/bank torque, the
direct-lean `Lean Rate Limit`, hop impulse, stick deadzone/curve,
support-contact threshold, hop rearm time, and rumble.
Resource defaults are 18 / 24 / 24 N·m, a 40°/s lean rate, a 10.5 N·s hop,
deadzone 0.15, and exponent 1.5. The playable scenes currently override a
slower hand-testing tune (acceleration 9 N·m, lean torque 12 N·m, initial spin
12 rad/s, pivot assist strength 0); the regression tests pin the reference
defaults so hand-tuning the scenes does not move the test baselines.
Edit geometry and base damping on the Torus node itself.
`ChaseCamera > Side Offset` can restore an angled view (4.5 m in the original
physics lab); zero in the playable scene avoids perspective-induced bank asymmetry.

Press **D / Back** for the separate, removable `TorusDebug` node. It makes the
torus 25% opaque with thin outlines, draws labeled vectors each physics tick,
and shows speed, spin, lean, grounded state, and slip beside the HUD. Its
`debug_vector_scale` controls the shared vector length scale (default 0.08).

- White: contact point; green: support normal; orange: estimated traction.
- Cyan: linear velocity at center of mass; purple: angular velocity.
- Yellow: net player torque; pink: assist torque, including the lower pivot's
  angular impulse divided by the timestep. General Phase 3 assists are still zero.
- Mint: lower-pivot impulse divided by the timestep, drawn at its application point.
- Red: instantaneous gyroscopic term `-ω × (I_world ω)`. The actual applied
  midpoint-integrated torque is also retained in the telemetry snapshot.

Traction is the tangential part of `get_contact_impulse() / state.step`. Jolt
returns world-space **estimated** impulses, including through getters named
`get_contact_local_*`. Slip is the largest tangential relative contact speed
divided by `max(abs(spin) * outer_radius, 0.1 m/s)`. Near rest this denominator
prevents division by zero; it is not a tire-model slip percentage.

Debug reads snapshots and changes visuals only. Removing it restores the torus
material. It adds no forces, damping, contacts, or velocity changes.

## Presentation

The donut has procedural baked-dough pores, glossy dripping strawberry icing,
and colored sprinkles. Asphalt uses fine aggregate, uneven patches and subtle
distance-faded survey markings. The playable lab adds an afternoon sky, warm
sun, light distance fog and 4× MSAA. No external texture downloads are needed.

The separate `TorusEffects` node reads physics snapshots to show slip dust,
short landing puffs and fading contact skid marks. Pure rolling and stationary
spin without ground contact emit no dust. Effects automatically hide in physics
debug and clear on reset. In **Remote > ControlsLab > TorusEffects**, adjust
`Intensity`, `Slip Threshold`, `Skid Lifetime`, or turn `Enabled` off. Removing
the node has no effect on physics; its regression compares 720 simulation ticks
with effects present versus absent, alongside particle/reset/debug probes.

The coastal scene adds procedural rolling, hop, landing, collision and splash
sounds. Rolling pitch and volume follow speed and slip; contact transitions
trigger one-shot effects. Under **Remote > Track > GameAudio**, adjust
`Sfx Volume Db` or disable effects entirely. Audio is synthesized once and
cached (well under 1 MB of PCM); no downloads or third-party recordings are used.

`WaterEffects` draws pooled spray droplets, mist and expanding foam rings at
the impact location, independent of the body's reset. It hides in physics debug;
its `Enabled` and `Intensity` exports can be changed live. Both water visuals
and audio only observe signals and snapshots, never apply forces or change
rigid-body state. The original labs remain silent and have no water hazard.

## Race loop

Cross the start line forward to begin the clock. Pass **six numbered checkpoints
in order**, then cross the finish line to complete the lap and begin the next.
The next gate is highlighted in mint; the finish is gold. The HUD shows the
current lap/time, best and last lap, checkpoint progress and reset status.

`RaceManager` observes physics snapshots and sweeps the center-of-mass segment
through each gate's banked plane. Direction, width and height checks reject
backwards crossings, out-of-order gates and passing underneath the track.
Sweeps catch fast crossings; interpolated crossing times use the physics step,
not the rendering frame rate. This is a small local racing loop, not a complete
anti-cheat or off-track penalty system.

Each passed gate stores a correctly oriented checkpoint 2 m behind it. Both
**R** and automatic water rescue retain gate progress and the running lap time,
but mark that lap **invalid for a best time**. Finishing it starts a fresh valid
lap. Reset teleports cannot count as gate crossings, and reset still cancels
momentum with impulses before relaunching spin on the following tick.

Best eligible lap is stored locally at `user://coastline_best.cfg` and restored
on the next launch. File writes are deferred outside physics integration;
`RaceManager > Persistence Enabled` can disable saving. The record is local to
this circuit and is not separated by tuning preset.

Press **D** to show the steering mode alongside the physics readout.
Direct lean reports the bank-pivot assist as off; the optional bank controller
shows its live pivot strength. Race state and
checkpoint markers remain separate from the original standalone labs.

## Original physics experiment

Run `mise run physics-lab`, or open `physics_validation.tscn` and press **F6**.
This scene has controls disabled and applies one automatic lean impulse at
**2 seconds**. Stop with **F8**, edit the Torus node, and restart to compare runs.

- `Major Radius` R = 1 m; `Minor Radius` r = 0.25 m; 100 capsule colliders.
  The outside diameter remains 2.5 m; collider count changes smoothness, not size.
- The axle is local +X. Capsule centerlines form chords of the YZ major circle,
  with rounded overlapping ends. Maximum centerline error is
  `R * (1 - cos(PI / capsule_count))`, about 0.49 mm at the defaults
  (previously 12.31 mm with 20 capsules). The inspector supports 12–128 capsules.
- The matching `TorusMesh` uses `inner_radius = R-r`, `outer_radius = R+r`.
- Mass = 3 kg; initial spin = 24 rad/s; nudge = 8 N·m·s about the forward axis;
  angular damping = 0; linear damping =
  0.01/s. Damping modes replace the project defaults. Spin comes from an angular
  impulse; friction supplies translation. There are no axis locks or assists.
- Geometry and launch settings take effect on restart. When changing radii,
  place the body at `R+r+0.03` above the floor. Physics damping, friction, and the
  manual gyro switch can be edited in the Remote inspector while running.
- Disable `Automatic Nudge` for a straight-line baseline. Use zero `Initial
  Spin` with the nudge enabled as a falling-body control experiment.
- Enable **Debug > Visible Collision Shapes** before running to inspect the
  runtime-generated capsule ring. This is the editor overlay, not Phase 2's
  custom physics debug view.

## Headless validation

Run the passing regression suite with `mise run validate`. Individual comparisons:

```sh
mise run import
mise exec -- godot --headless --path . --script res://tests/physics_validation.gd
mise exec -- godot --headless --path . --script res://tests/physics_validation.gd -- --manual
mise exec -- godot --headless --path . --script res://tests/physics_validation.gd -- --manual --no-nudge
mise exec -- godot --headless --path . --script res://tests/physics_validation.gd -- --manual --no-spin
mise exec -- godot --headless --path . --script res://tests/gyro_conservation.gd
mise exec -- godot --headless --path . --script res://tests/gyro_conservation.gd -- --manual
```

Each rolling experiment runs for 12 simulated seconds at 240 physics ticks/s and prints
one sample per simulated second. A spinning, nudged pass requires less than 5°
lean before the nudge, less than 45° lean throughout, more than 3° change in both
axle heading and travel direction after the nudge, and contact on more than half
the ticks. The no-spin control is
expected to fail the upright criterion. These are bounded validation criteria,
not a guarantee of indefinite stability or a proof of gyro integration by
themselves. Native/manual comparison and a free-flight momentum test distinguish
gyroscopic integration from contact-driven turning.

The full `mise run validate` suite also exercises real keyboard/gamepad events,
analog torque response, simultaneous inputs, braking near zero and in either
spin direction, the kinematic direct lean about the ground support point,
grounded hopping, reset, and debug on/off physics equivalence. A separate rolling-steering regression uses the playable
scene with gravity, friction, spin and gyro enabled: it checks camera-relative
left/right turns after a 0.3 s lean tap under keyboard and analog input, with and
without acceleration. Separate bank-controller, pivot and lifecycle regressions
keep covering the optional previous mode.
Free-flight conservation runs for six simulated seconds.
Controller input is tested with synthetic events; physical rumble needs a
controller check on your machine.
The track regression additionally checks the closed layout, bank continuity,
front-facing road collisions, supported spawn and a real accelerated jump/landing.
Water regressions cover upright/leaned/flat falls, fast crossings, reset timing,
manual cancellation, safe jumps, and identical trajectories with/without splash
effects. Audio tests check bounded PCM, click-free stream endpoints, one-shot
events, live volume and independence from physics.
Phase 4 adds solid-terrain rays and real grass landing/rolling, ordered/directional
lap crossings, timer interpolation, reset exclusion, persistent best-lap loading,
HUD formatting, and an integrated drive through the start, jump, checkpoint and
physical R reset.

## Gyro choice and measured validation

**Manual gyro is enabled by default.** Native Godot/Jolt can keep the rolling
ring upright and make it turn through contact dynamics, but does not enable
Jolt's gyroscopic-force option. The free-flight negative control exposes the
missing term: angular momentum direction drifts **6.903°** over six seconds.
That test intentionally exits with status 1 when `--manual` is omitted.

Applying raw `-ω × (I_world ω)` using a forward Euler step also proved inadequate:
at 24 rad/s and 240 Hz it gained **144.5% rotational energy** during the six-second
test. The final implementation evaluates that same torque with an **implicit
midpoint** step (six fixed-point iterations), keeping all physics additive via
`state.apply_torque()`. It never overwrites velocity or applies an upright assist.
The full local inertia is recovered from the body's world inverse tensor, then
rotated back with `B * I_local * B.transposed()` each tick.

The midpoint predictor includes the known player and assist torques as well as
the gyroscopic term. Omitting the external torques previously passed the
torque-free test but violated angular-momentum balance during steering.
`tests/gyro_forced.gd` covers this independently of the banking controller;
its `--uncoupled-gyro` option intentionally reproduces the old failing predictor.
It checks both angular momentum and rotational energy against external work.
There is no automatic energy normalization: friction, damping, impacts and
the explicit pivot correction must not be mistaken for torque-free motion.

Historical baseline on Godot **4.7.2.stable.official.ed1daf0bf**, using the
original **20-capsule** collider and stabilized manual implementation:

- Stayed upright for the 12-second straight-line baseline (lean below 0.01°).
- Reached **19.37° maximum lean**, **33.43° peak axle heading deflection**, and
  **9.73° peak travel-direction deflection** after the nudge, without falling
  over during the 12-second run.
- Conserved free-flight momentum direction within **0.348°**; momentum magnitude
  and rotational-energy error both printed **0.000%** (below 0.001%). Tolerances
  are 3°, 2%, and 2% respectively over six simulated seconds.
- Fell flat to **90° lean** with zero initial spin, as expected.

The denser 100-capsule default reduces the geometric unevenness of the original
collider. A fresh 12-second automatic-nudge run reached 17.32 degrees peak bank
and 30.25 degrees axle deflection, with contacts on 99% of samples. The ring
still loses speed to contact losses and drag. Finite-rate integration is
approximate; historical values above describe the original collider. Keep
240 Hz when reproducing them. Changing dimensions, mass, spin, or timestep calls
for rerunning the conservation and rolling tests.

## Physics references

- [Godot 4.7 built-in Jolt](https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html)
- [Direct body state / inertia and torque](https://docs.godotengine.org/en/4.7/classes/class_physicsdirectbodystate3d.html)
- [TorusMesh](https://docs.godotengine.org/en/4.7/classes/class_torusmesh.html)
- [CapsuleShape3D](https://docs.godotengine.org/en/4.7/classes/class_capsuleshape3d.html)
- [Godot/Jolt body setup](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/jolt_physics/objects/jolt_body_3d.cpp)
- [Jolt gyro default](https://github.com/godotengine/godot/blob/4.7-stable/thirdparty/jolt_physics/Jolt/Physics/Body/BodyCreationSettings.h)
- [Jolt contact impulse limitations](https://docs.godotengine.org/en/4.7/tutorials/physics/using_jolt_physics.html#contact-impulses)
- [Controller input](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html)

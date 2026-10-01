extends Control

## ============================================================================
## SCREEN FX - the edge vignette and the red "you were hit" wash.
## ============================================================================
##
## Moved here from hud.gd so the Survival HUD and the TDM HUD share one copy.
## It covers the whole screen but ignores the mouse, so it can never swallow a
## click meant for the game.

var _flash: ColorRect
var _vignette_material: ShaderMaterial
## Health as a fraction of max; under LOW_HEALTH the screen edges pulse red.
var _health_fraction: float = 1.0
var _time: float = 0.0
const LOW_HEALTH := 0.3
const CALM_TINT := Vector3(0.17, 0.18, 0.26)
const DANGER_TINT := Vector3(0.75, 0.08, 0.2)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PRESET_FULL_RECT stretches this to cover the screen and keeps it covering
	# the screen when the window is resized.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# The vignette is a SHADER - a tiny program run once per pixel on the
	# graphics card. It darkens the corners slightly, pulling the eye toward the
	# middle where the crosshair and the action are.
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform vec3 tint = vec3(0.17, 0.18, 0.26);
uniform float strength = 0.5;

void fragment() {
	// SCREEN_UV runs 0..1 across the screen; shifting by 0.5 puts the origin in
	// the middle, so length() is the distance from the centre.
	vec2 offset = SCREEN_UV - vec2(0.5);
	float dist = length(offset) * 1.414;
	// smoothstep fades the darkening in gently instead of as a hard ring.
	float amount = smoothstep(0.42, 1.0, dist) * strength;
	COLOR = vec4(tint, amount);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_vignette_material = mat
	var vignette := ColorRect.new()
	vignette.material = mat
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)

	_flash = ColorRect.new()
	_flash.color = Color(0.84, 0.13, 0.27, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)


## Told the player's health by the HUD each time it changes.
func set_health_fraction(fraction: float) -> void:
	_health_fraction = fraction
	if fraction >= LOW_HEALTH or fraction <= 0.0:
		_vignette_material.set_shader_parameter("tint", CALM_TINT)
		_vignette_material.set_shader_parameter("strength", 0.5)


## Low health: the corners slowly pulse red, stronger the lower you are. A cue
## you notice without looking at the health bar. Purely visual.
func _process(delta: float) -> void:
	if _health_fraction >= LOW_HEALTH or _health_fraction <= 0.0:
		return
	_time += delta
	var danger := 1.0 - _health_fraction / LOW_HEALTH
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	_vignette_material.set_shader_parameter("tint", CALM_TINT.lerp(DANGER_TINT, 0.6 + 0.4 * danger))
	_vignette_material.set_shader_parameter("strength", 0.55 + (0.25 + 0.2 * danger) * pulse)


## Snap the red wash on, then fade it out. A new tween per hit means rapid hits
## keep the screen lit rather than each one cancelling the last.
func flash_hurt() -> void:
	_flash.color.a = 0.32
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.35)

extends CharacterBody3D

## Barco de vela. Propulsión por viento; el jugador lleva el timón (A/D) y gestiona
## las velas y el ancla:
##   · Tecla 1 → abrir/cerrar vela DELANTERA
##   · Tecla 2 → abrir/cerrar vela TRASERA
##   · ESPACIO → soltar/levar ANCLA (detiene el barco)
## Las velas afectan a la propulsión (superficie abierta) y al giro (balance de velas).
## Cada acción emite una SEÑAL para engancharle animación más adelante.

signal vela_delantera_cambiada(abierta: bool)
signal vela_trasera_cambiada(abierta: bool)
signal ancla_cambiada(anclada: bool)

@export var velocidad_max := 12.0
@export var aceleracion := 4.0
@export var velocidad_giro := 1.0
@export_range(0.0, 1.0) var giro_minimo := 0.2
@export var angulo_muerto := 45.0
@export var angulo_optimo := 100.0
@export_range(0.0, 1.0) var empuje_delantera := 0.4   # propulsión que aporta la vela delantera
@export_range(0.0, 1.0) var empuje_trasera := 0.6     # propulsión que aporta la vela trasera
@export var sesgo_giro_velas := 0.5                    # giro por balance de velas (rad/s a plena vela)
@export var nombre := "Barco"                          # nombre para el HUD/selector
@export var altura_flotacion := 1.74                   # Y a la que flota (línea de cubierta sobre el agua)
@export var recorte_radio := Vector2(1.0, 2.0)         # semiejes del recorte del casco (manga, eslora)
@export var recorte_proa_exp := 0.8                    # forma de la proa en el recorte del agua
@export var recorte_popa_exp := 0.4                    # forma de la popa en el recorte del agua

const BOB_AMPLITUDE := 0.15
const BOB_SPEED := 1.2

# Estado de las acciones (empieza navegando: ambas velas abiertas, sin anclar).
var vela_delantera := true
var vela_trasera := true
var anclado := false

var velocidad := 0.0
var time := 0.0
var base_y := 0.0

@onready var helm_position: Marker3D = $HelmPosition


func _ready() -> void:
	# Cada barco flota a SU altura (una balandra grande no flota igual que la lancha).
	position.y = altura_flotacion
	base_y = altura_flotacion
	# El barco se anuncia por grupo → el mar, las flechas y el HUD lo encuentran solos
	# (sin rutas fijas), y sigue funcionando al cambiar de embarcación en runtime.
	add_to_group("barco_activo")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_W:
				_set_vela_delantera(not vela_delantera)
			KEY_S:
				_set_vela_trasera(not vela_trasera)
			KEY_SPACE:
				_set_ancla(not anclado)


func _physics_process(delta: float) -> void:
	time += delta

	if anclado:
		# Anclado: frena y se queda quieto (solo el balanceo del oleaje). No gira ni avanza.
		velocidad = move_toward(velocidad, 0.0, aceleracion * 3.0 * delta)
		velocity = -transform.basis.z * velocidad
		move_and_slide()
		position.y = base_y + sin(time * BOB_SPEED) * BOB_AMPLITUDE
		return

	# Timón: eficacia según la velocidad (más rápido = gira mejor).
	var giro := float(Input.is_key_pressed(KEY_A)) - float(Input.is_key_pressed(KEY_D))
	var vel_norm := clampf(absf(velocidad) / maxf(0.01, velocidad_max), 0.0, 1.0)
	var giro_efectivo := velocidad_giro * (giro_minimo + (1.0 - giro_minimo) * vel_norm)
	rotate_y(giro * giro_efectivo * delta)

	# Sesgo de giro por balance de velas (trasera → orza; delantera → arriba).
	_aplicar_sesgo_velas(vel_norm, delta)

	# Propulsión: viento × ángulo × superficie de vela abierta.
	var objetivo := velocidad_max * _factor_viento() * Viento.fuerza * _factor_velas()
	velocidad = move_toward(velocidad, objetivo, aceleracion * delta)

	velocity = -transform.basis.z * velocidad
	move_and_slide()
	position.y = base_y + sin(time * BOB_SPEED) * BOB_AMPLITUDE


# ── Acciones (con señal para animar más adelante) ────────────────────────────
func _set_vela_delantera(v: bool) -> void:
	if vela_delantera == v:
		return
	vela_delantera = v
	vela_delantera_cambiada.emit(v)
	print("Vela delantera: ", "abierta" if v else "cerrada")


func _set_vela_trasera(v: bool) -> void:
	if vela_trasera == v:
		return
	vela_trasera = v
	vela_trasera_cambiada.emit(v)
	print("Vela trasera: ", "abierta" if v else "cerrada")


func _set_ancla(v: bool) -> void:
	if anclado == v:
		return
	anclado = v
	ancla_cambiada.emit(v)
	print("Ancla: ", "soltada (detenido)" if v else "levada")


# ── Física de vela ───────────────────────────────────────────────────────────
# Superficie de vela abierta → cuánto propulsa (0 = todo cerrado; ~1 = todo abierto).
func _factor_velas() -> float:
	var f := 0.0
	if vela_delantera:
		f += empuje_delantera
	if vela_trasera:
		f += empuje_trasera
	return f


# La trasera abierta tiende a ORZAR (girar hacia el viento); la delantera a ARRIBAR
# (girar en contra). Con ambas se equilibra. Escala con la velocidad (el giro es
# consecuencia del movimiento).
func _aplicar_sesgo_velas(vel_norm: float, delta: float) -> void:
	var s := 0.0
	if vela_trasera:
		s -= 1.0   # popa → ORZA (gira hacia el viento)
	if vela_delantera:
		s += 1.0   # proa → ARRIBA (aleja del viento; ayuda a salir de la zona muerta)
	if absf(s) < 0.001 or vel_norm < 0.001:
		return
	var wind := Viento.direccion
	wind.y = 0.0
	if wind.length() < 0.001:
		return
	var src := (-wind).normalized()   # de dónde viene el viento
	var bow := -transform.basis.z
	bow.y = 0.0
	if bow.length() < 0.001:
		return
	bow = bow.normalized()
	# Ángulo con signo de la proa hacia el origen del viento.
	var ang := atan2(bow.x * src.z - bow.z * src.x, bow.dot(src))
	rotate_y(clampf(ang, -1.0, 1.0) * s * sesgo_giro_velas * vel_norm * delta)


# Factor de propulsión [0..1] según el ángulo entre la proa y el viento.
func _factor_viento() -> float:
	var wind := Viento.direccion
	wind.y = 0.0
	if wind.length() < 0.001:
		return 0.0
	wind = wind.normalized()
	var fwd := -transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return 0.0
	fwd = fwd.normalized()
	var cos_ang := fwd.dot(-wind)
	var cos_muerto := cos(deg_to_rad(angulo_muerto))
	var cos_optimo := cos(deg_to_rad(angulo_optimo))
	var t := clampf((cos_muerto - cos_ang) / (cos_muerto - cos_optimo), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func on_interact(_player: Node3D) -> void:
	# Punto de enganche para cuando el jugador suba al timón.
	print("El jugador subió al timón del barco.")

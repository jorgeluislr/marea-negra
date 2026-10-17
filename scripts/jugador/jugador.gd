class_name Jugador
extends CharacterBody3D

## Controlador básico de personaje a pie.
## Movimiento con WASD, cámara con el mouse, correr con Shift, saltar con
## Espacio, interactuar (ej. subir a un barco) con E.

const WALK_SPEED := 4.0
const RUN_SPEED := 7.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.003
const GRAVITY := 9.8
## Lo que se sube por la jarcia, en m/s. Un hombre trepa despacio: a 7,5 como corriendo, los
## 4,78 m de esta escala se hacen en medio segundo y no se ve nada.
const VELOCIDAD_TREPAR := 1.8
## Y lo que se corre uno de lado por los peldanos, que es más lento todavía.
const VELOCIDAD_LATERAL := 0.9
## Hacia dónde hay que estar mirando para engancharse, en coseno: 0,3 son unos 72° a cada lado.
const MIRAR_A_LA_ESCALA := 0.3

# ── En el agua ───────────────────────────────────────────────────────────────
## Se nada bastante más despacio que se anda, y mucho más despacio que corre un barco: a 1,6 m/s
## no se alcanza a una balandra que navega a 9, y eso es correcto — quien se cae, se queda.
const VELOCIDAD_NADO := 1.6
## Dónde queda la línea de flotación del personaje respecto a su centro. La cápsula mide 1,8 m
## con el origen en medio, así que con −0,15 el agua le llega por el pecho y la cabeza queda
## fuera, que es lo que hay que ver desde dentro de su propia cámara.
const FLOTACION := -0.15
## Lo hondo que puede estar el centro del personaje antes de que se le considere en el agua. Es
## medio cuerpo: con menos, una salpicadura de ola lo pondría a nadar andando por cubierta.
const CALADO := 0.6
## Cómo de rápido lo devuelve el agua a su línea de flotación. Alto salta como un corcho; bajo
## se hunde y tarda en salir.
const EMPUJE_AGUA := 2.5

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var interact_ray: RayCast3D = $CameraPivot/Camera3D/InteractRay

var camera_pitch := 0.0

# ── Trepar por la jarcia ─────────────────────────────────────────────────────
## Las escalas que me tienen dentro de su área. Puede haber dos a la vez (las dos bandas no, pero
## sí una escala y lo que venga después: flechastes de mayor y de mesán en un barco con dos palos).
var _escalas: Array[Node] = []
## En cuál estoy trepando, o null si voy a pie.
var _escala: Node = null
## Dónde estoy en ella: `_s` a lo largo de la subida, `_l` corrido de lado por el peldano.
var _s := 0.0
var _l := 0.0

## Si está en el mar. Lo decide la ola bajo sus pies, no una zona dibujada a mano.
var _nadando := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pitch = clamp(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.2, 1.2)
		camera_pivot.rotation.x = camera_pitch

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_E:
			_try_interact()

	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Avisos de `EscalaJarcia`, por duck-typing: la escala no sabe qué es un `Jugador`.
func escala_cerca(e: Node) -> void:
	if not _escalas.has(e):
		_escalas.append(e)


func escala_lejos(e: Node) -> void:
	_escalas.erase(e)
	if _escala == e:
		soltar_escala()


func trepando() -> bool:
	return _escala != null


## Suelta la jarcia y devuelve al personaje a sus piernas.
func soltar_escala() -> void:
	_escala = null
	velocity = Vector3.ZERO


## Se agarra a la escala que tenga delante, si mira hacia ella.
##
## Mirar importa: al pie del palo se pasa por dentro del área andando por cubierta, y engancharse
## solo por estar ahí dejaría al personaje pegado al aparejo cada vez que cruza la maestra.
func _intentar_agarrar() -> bool:
	for e in _escalas:
		var donde: Vector2 = e.donde(global_position)
		var sitio: Vector3 = e.sitio(clampf(donde.x, 0.0, e.alto), clampf(donde.y, -e.ancho, e.ancho))
		var hacia := sitio - global_position
		hacia.y = 0.0
		if hacia.length() < 0.05:
			hacia = -e.fuera()
		if (-global_transform.basis.z).dot(hacia.normalized()) < MIRAR_A_LA_ESCALA:
			continue
		_escala = e
		_s = clampf(donde.x, 0.0, e.alto)
		_l = clampf(donde.y, -e.ancho, e.ancho)
		velocity = Vector3.ZERO
		return true
	return false


## Un paso trepando. No se usa `move_and_slide`: el personaje va PEGADO a la escala, que es lo que
## hace que suba de verdad — con la física de la cápsula, un peldano de 3,4 cm no lo sostiene y
## resbala (medido: posado encima de uno cae 43,9 m, hasta el agua).
##
## La posición se recalcula del `EscalaJarcia` cada paso en vez de sumarse a la anterior, así que
## el barco puede navegar, escorar y cabecear y el que trepa se va con él sin hacer nada.
func _trepar(delta: float) -> void:
	var sube := float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	var lado := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	_s += sube * VELOCIDAD_TREPAR * delta
	_l = clampf(_l + lado * VELOCIDAD_LATERAL * delta, -_escala.ancho, _escala.ancho)
	# Por abajo se suelta solo y sigue andando; por arriba se queda agarrado al tope.
	if _s <= 0.0:
		soltar_escala()
		return
	_s = minf(_s, _escala.alto)
	global_position = _escala.sitio(_s, _l)
	velocity = Vector3.ZERO


func nadando() -> bool:
	return _nadando


## La altura del mar donde esté el personaje. Es la MISMA función con la que flota el barco y con
## la que se dibuja el agua (`Oleaje`), así que no puede haber dos mares distintos.
##
## La caída del horizonte no entra: va con el cuadrado de la distancia a la cámara y la cámara es
## la suya propia, a metro y medio — son micras.
func _mar() -> float:
	return Oleaje.altura_en(Vector2(global_position.x, global_position.z))


## Un paso nadando: se mueve en horizontal y el agua lo devuelve a su línea de flotación.
##
## Espacio sube y Mayúscula baja, para poder bucear y para salir si una ola lo tapa.
func _nadar(delta: float, mar: float) -> void:
	var entrada := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()
	var dir := (global_transform.basis * Vector3(entrada.x, 0.0, entrada.y)).normalized()
	velocity.x = dir.x * VELOCIDAD_NADO
	velocity.z = dir.z * VELOCIDAD_NADO
	var objetivo := mar + FLOTACION
	velocity.y = (objetivo - global_position.y) * EMPUJE_AGUA
	if Input.is_key_pressed(KEY_SPACE):
		velocity.y += VELOCIDAD_NADO
	elif Input.is_key_pressed(KEY_SHIFT):
		velocity.y -= VELOCIDAD_NADO
	move_and_slide()


## Al caer al agua hay que DEJAR DE COLGAR DEL BARCO, o el casco se lleva al náufrago consigo:
## el personaje es hijo suyo para que la cubierta lo arrastre al navegar, y eso mismo es lo que
## sobra en cuanto está en el mar. Se le pide al barco, que es quien lo subió a bordo.
func _caer_al_agua() -> void:
	_nadando = true
	soltar_escala()
	var p := get_parent()
	if p != null and p.has_method("hombre_al_agua"):
		p.hombre_al_agua(self)


func _physics_process(delta: float) -> void:
	# El agua manda sobre todo lo demás: si la ola lo tapa mientras trepa, se suelta y nada.
	var mar := _mar()
	if global_position.y - CALADO < mar:
		if not _nadando:
			_caer_al_agua()
		_nadar(delta, mar)
		return
	elif _nadando:
		_nadando = false

	if _escala != null:
		# Con el salto se suelta, y sale despedido hacia fuera para no volver a engancharse.
		if Input.is_key_pressed(KEY_SPACE):
			var fuera: Vector3 = _escala.fuera()
			soltar_escala()
			velocity = fuera * 2.0 + Vector3.UP * JUMP_VELOCITY * 0.5
			move_and_slide()
			return
		_trepar(delta)
		return
	# Agarrarse: hay escala delante, se pide adelante y no se está saltando.
	if not _escalas.is_empty() and Input.is_key_pressed(KEY_W) and _intentar_agarrar():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()

	# GLOBAL basis, no local: el jugador es hijo del barco, así que transform.basis es relativa
	# al barco. move_and_slide usa la velocidad en espacio global, de modo que con la basis local
	# la W apuntaba mal en cuanto el barco giraba. Con la global, la W siempre va hacia donde
	# mira el personaje de verdad, gire el barco lo que gire.
	var direction := (global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()


func _try_interact() -> void:
	if interact_ray.is_colliding():
		var target := interact_ray.get_collider()
		if target and target.has_method("on_interact"):
			target.on_interact(self)

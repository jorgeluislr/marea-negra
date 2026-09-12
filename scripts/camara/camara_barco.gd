extends Camera3D
## Cámara de seguimiento del barco (chase cam): se coloca por DETRÁS y en ALTO,
## mirando a la lancha, y la sigue cuando gira o navega. Va como hija del barco.

@export var distancia := 12.0   # cuánto por detrás del barco
@export var altura := 6.0       # cuánto por encima
@export var mira_altura := 1.5  # a qué altura del barco apunta la mirada
@export var suavizado := 8.0    # mayor = sigue más rígido; 0 = instantáneo


## Hasta dónde se ve, en metros. El valor de fábrica de Godot son 4.000 y el agua llega a
## 20.000: con 4.000 el mar se acaba en un canto a cuatro kilómetros, que es justo lo que se
## quería quitar. 25.000 cubre el horizonte de un ojo a 49 m sobre el agua. No cuesta precisión
## de profundidad porque Godot invierte el buffer de Z (Forward+).
const ALCANCE := 25000.0


func _ready() -> void:
	far = ALCANCE
	_reclamar_visor.call_deferred()


## Solo se queda el visor si SU barco es el del jugador.
##
## Antes hacía `current = true` a secas, y con un segundo barco en el agua eso se veía como que
## la cámara aparecía encima del barco que no gobiernas: el enemigo se instancia después, su
## cámara entra al árbol la última y gana. No se notaba mientras hubo un solo barco.
##
## **Diferido a propósito.** Quién lleva al jugador lo decide `Barco.tomar_mando_jugador()`, y
## el `GestorBarcos` lo llama DESPUÉS de meter el barco en el árbol — o sea después de este
## `_ready`, porque los hijos se preparan antes que el padre. Preguntando aquí mismo, ninguna
## cámara se quedaría el visor y la pantalla saldría en negro.
##
## Si no hay ningún barco marcado (una herramienta de medida, una escena suelta), se queda el
## visor igualmente: es la misma regla que sigue el audio del barco, y evita que una escena de
## prueba se quede sin cámara.
func _reclamar_visor() -> void:
	var barco := get_parent_node_3d()
	var hay_jugador := not get_tree().get_nodes_in_group("barco_activo").is_empty()
	if hay_jugador and barco != null and not barco.is_in_group("barco_activo"):
		current = false
		return
	current = true


func _physics_process(delta: float) -> void:
	var barco := get_parent_node_3d()
	if barco == null:
		return
	# "Detrás" = sentido contrario a la proa (el barco avanza hacia -Z local).
	var fwd := -barco.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	var objetivo := barco.global_position - fwd * distancia + Vector3.UP * altura
	if suavizado > 0.0:
		global_position = global_position.lerp(objetivo, clampf(delta * suavizado, 0.0, 1.0))
	else:
		global_position = objetivo

	look_at(barco.global_position + Vector3.UP * mira_altura, Vector3.UP)

class_name Bala
extends Node3D

## Una bala de cañón en vuelo.
##
## Vuela por la fórmula ANALÍTICA de la parábola, no integrando paso a paso, y eso es
## deliberado: la guía de tiro que ve el jugador se dibuja con esa misma fórmula, así que no
## pueden discrepar. Integrando por Euler la línea y la bala se separarían metros al final del
## vuelo, y el jugador vería que la mira miente sin que ninguna prueba lo cazara.
##
## El impacto se busca por rayo entre la posición de un paso y la del siguiente, no con un
## cuerpo físico: a 90 m/s la bala recorre 1,5 m por paso de física y un `RigidBody3D`
## atravesaría un casco de 10 cm sin enterarse.

signal impacto(donde: Vector3, contra: Node)

const G := 9.8

@export var altura_mar := 0.0
@export var vida_max := 20.0      ## Segundos antes de rendirse, por si no toca nada.
@export var radio := 0.06         ## Solo para el rastro; el choque va por rayo.
## Masa de la bala, en kg. Una de a 3 libras pesa 1,36. Sirve para dar al blanco la ENERGÍA del
## impacto y no solo el punto: un casco no se daña igual con un tiro a bocajarro que con uno al
## límite del alcance, y esa diferencia sale sola de la velocidad que lleve al llegar.
@export var masa := 1.36
## Capas contra las que choca: la 2 es el casco y la 3 los colisionadores de cubierta.
@export_flags_3d_physics var mascara := 2

var _p0 := Vector3.ZERO
var _v0 := Vector3.ZERO
var _t := 0.0
var _anterior := Vector3.ZERO
var _viva := true


func _ready() -> void:
	var o := get_node_or_null("/root/Origen")
	if o != null:
		o.recentrado.connect(_al_recentrar)


## El mundo se ha corrido `-d` (origen flotante). La bala vuela por su fórmula desde `_p0`, no
## desde donde está su nodo, así que hay que correr también eso o volvería a donde estaba.
func _al_recentrar(d: Vector3) -> void:
	_p0 -= d
	_anterior -= d


## Lanza la bala. Se llama antes de meterla en el árbol o justo después; el vuelo empieza a
## contar desde aquí.
func lanzar(desde: Vector3, velocidad: Vector3, mar := 0.0) -> void:
	_p0 = desde
	_v0 = velocidad
	altura_mar = mar
	_t = 0.0
	_anterior = desde
	global_position = desde


## Dónde está la bala a los `t` segundos de salir. Es LA fórmula: la usan el vuelo y la guía.
static func punto(p0: Vector3, v0: Vector3, t: float) -> Vector3:
	return p0 + v0 * t + Vector3.DOWN * (0.5 * G * t * t)


## Cuánto tarda en bajar de `p0` hasta la altura `y_final`. Negativo si nunca llega.
static func tiempo_hasta(p0: Vector3, v0: Vector3, y_final: float) -> float:
	var h := p0.y - y_final
	var disc := v0.y * v0.y + 2.0 * G * h
	if disc < 0.0:
		return -1.0
	return (v0.y + sqrt(disc)) / G


func _physics_process(delta: float) -> void:
	if not _viva:
		return
	_t += delta
	var ahora := punto(_p0, _v0, _t)
	# ¿Ha chocado con algo por el camino?
	var espacio := get_world_3d().direct_space_state
	var par := PhysicsRayQueryParameters3D.create(_anterior, ahora)
	par.collision_mask = mascara
	var g := espacio.intersect_ray(par)
	if not g.is_empty():
		_impactar(g["position"], g.get("collider"))
		return
	# ¿Ha caído al agua?
	if ahora.y <= altura_mar:
		var t_agua := tiempo_hasta(_p0, _v0, altura_mar)
		_impactar(punto(_p0, _v0, t_agua), null)
		return
	_anterior = ahora
	global_position = ahora
	if _t > vida_max:
		_impactar(ahora, null)


## Energía cinética en el instante actual, en julios. Se calcula con la velocidad REAL de vuelo
## y no con la de boca: la bala llega más despacio cuanto más lejos cae, y eso es justo lo que
## debe notar el blanco.
func energia() -> float:
	var v := _v0 + Vector3.DOWN * (G * _t)
	return 0.5 * masa * v.length_squared()


func _impactar(donde: Vector3, contra: Node) -> void:
	_viva = false
	global_position = donde
	# Quien reciba el tiro se entera por el método que responde, no por su tipo: la misma
	# convención que `on_interact` en el resto del juego. Así la bala no tiene que conocer las
	# boyas, ni mañana los barcos enemigos.
	var n: Node = contra
	while n != null:
		if n.has_method("recibir_impacto"):
			n.call("recibir_impacto", donde, energia(), self)
			break
		n = n.get_parent()
	impacto.emit(donde, contra)
	queue_free()

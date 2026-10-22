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
##
## Desde el 19-10-2026 es munición REAL: se ve (una bola de hierro que va en la misma parábola,
## frame a frame), cae en la ola que se dibuja y salpica, y pega en la MADERA de verdad —las dianas
## del casco, los palos, la jarcia y las velas— en vez de en la caja del barco. Quién decide qué
## zona rompe y cuánto es el blanco (`Barco.recibir_impacto` → `Averias`), con la `Municion` que
## lleve la bala y la normal que deja en `golpe`.

signal impacto(donde: Vector3, contra: Node)

const G := 9.8

@export var altura_mar := 0.0
@export var vida_max := 20.0      ## Segundos antes de rendirse, por si no toca nada.
@export var radio := 0.06         ## Solo para el rastro; el choque va por rayo.
## Masa de la bala, en kg. Una de a 3 libras pesa 1,36. Sirve para dar al blanco la ENERGÍA del
## impacto y no solo el punto: un casco no se daña igual con un tiro a bocajarro que con uno al
## límite del alcance, y esa diferencia sale sola de la velocidad que lleve al llegar.
@export var masa := 1.36
## Capas contra las que choca, y qué es cada una, medido con `tools/mapa_de_dianas.tscn`:
##   · 2   la caja del `CharacterBody3D` de cada barco, y las boyas.
##   · 5   palos y perchas (`PerchasSolidas`, capa 16) y 6 la jarcia (32): el aparejo.
##   · 8   las DIANAS del casco (`Barco.CAPA_DIANAS`, 128): la madera de verdad.
##   · 25-32 los bits de viento de las telas: es lo único que distingue una vela, y un rayo SÍ
##     ve los `SoftBody3D` (no así `intersect_shape`, que no los devuelve nunca).
## La caja de un barco que tiene dianas se SALTA (`Barco.tiene_dianas`): es un prisma de 3,8 ×
## 2,9 × 12 m que incluye el aire de las esquinas de proa y popa, y una bala que pasa por ahí no
## ha tocado nada.
@export_flags_3d_physics var mascara := 2 | 16 | 32 | 128 | (0xFF << 24)

## Lo que va en el ánima. Sin ella, una rasa.
var municion: Municion
## El barco que la disparó: sus propios cuerpos no cuentan como blanco. La boca está fuera de la
## borda, pero un espeque a tope y la jarcia de la misma banda pueden quedar en el camino.
var origen: Node
## El último choque, tal como lo devolvió el rayo: `position`, `normal` y `collider`. Lo lee quien
## recibe el impacto, que necesita la normal para orientar el agujero y las astillas.
var golpe := {}

var _p0 := Vector3.ZERO
var _v0 := Vector3.ZERO
var _t := 0.0
var _anterior := Vector3.ZERO
var _viva := true
var _malla: Node3D
var _giro := Vector3.ZERO

static var _mat_hierro: StandardMaterial3D


func _ready() -> void:
	var o := get_node_or_null("/root/Origen")
	if o != null:
		o.recentrado.connect(_al_recentrar)
	_montar_malla()


## El mundo se ha corrido `-d` (origen flotante). La bala vuela por su fórmula desde `_p0`, no
## desde donde está su nodo, así que hay que correr también eso o volvería a donde estaba.
func _al_recentrar(d: Vector3) -> void:
	_p0 -= d
	_anterior -= d


## Lanza la bala. Se llama antes de meterla en el árbol o justo después; el vuelo empieza a
## contar desde aquí.
func lanzar(desde: Vector3, velocidad: Vector3, mar := 0.0, que: Municion = null,
		quien: Node = null) -> void:
	_p0 = desde
	_v0 = velocidad
	altura_mar = mar
	_t = 0.0
	_anterior = desde
	if que != null and que != municion:
		municion = que
		# Si ya estaba en el árbol, la malla se hizo con la rasa por defecto.
		if _malla != null:
			_malla.queue_free()
			_malla = null
			_montar_malla()
	origen = quien
	global_position = desde
	_colocar_malla(0.0)


## La rasa, si nadie dijo otra cosa.
func tipo() -> Municion:
	if municion == null:
		municion = Municion.de("rasa")
	return municion


## Dónde está la lámina de agua bajo un punto del mundo: **la ola que se dibuja** encima del plano
## que usa la guía. `Oleaje.altura_en` da la altura absoluta con su `nivel` dentro, y en una escena
## sin mar ese nivel es 0 mientras el plano del tiro está en otro sitio (−0,882 en las herramientas
## de artillería); por eso se suma la ola SOBRE `altura_mar` y no se usa tal cual.
static func superficie(x: float, z: float, plano: float, reloj := -1.0) -> float:
	return Oleaje.altura_en(Vector2(x, z), reloj) - Oleaje.nivel + plano


## Cuánto tarda en llegar a la OLA, la que habrá cuando llegue: el reloj de la mar se adelanta el
## propio tiempo de vuelo. Es lo que usa la guía para acabar donde de verdad salpicará la bala; con
## el plano, un tiro rasante (6° de caída) erraba dos metros por cada veinte centímetros de ola.
static func tiempo_hasta_la_ola(p0: Vector3, v0: Vector3, plano: float) -> float:
	var t_plano := tiempo_hasta(p0, v0, plano)
	if t_plano <= 0.0:
		return t_plano
	var cae := func(t: float) -> float:
		var p := punto(p0, v0, t)
		return p.y - superficie(p.x, p.z, plano, Oleaje.t + t)
	var t0 := maxf(t_plano - 1.5, 0.0)
	if float(cae.call(t0)) <= 0.0:
		t0 = 0.0
	var t1 := t_plano + 1.5
	if float(cae.call(t1)) > 0.0:
		return t_plano
	for _i in 16:
		var tm := (t0 + t1) * 0.5
		if float(cae.call(tm)) <= 0.0:
			t1 = tm
		else:
			t0 = tm
	return t1


## La bola que se ve. Va en `top_level` para colocarla en el reloj del RENDER: la bala avanza en
## pasos de física y a 120 fps un paso son dos frames, así que pegada al nodo saltaría a trompicones.
## Se coloca en la MISMA fórmula, adelantada la fracción de paso que lleva el frame, y así está
## sobre la parábola en cada frame que se ve (la prueba lo mide: menos de 1 cm).
func _montar_malla() -> void:
	if _malla != null:
		return
	if _mat_hierro == null:
		_mat_hierro = StandardMaterial3D.new()
		_mat_hierro.albedo_color = Color(0.09, 0.09, 0.10)
		_mat_hierro.metallic = 0.6
		_mat_hierro.roughness = 0.55
	var m := tipo()
	var raiz := Node3D.new()
	raiz.name = "Proyectil"
	raiz.top_level = true
	var bola := MeshInstance3D.new()
	var esfera := SphereMesh.new()
	esfera.radius = m.radio
	esfera.height = m.radio * 2.0
	esfera.radial_segments = 12
	esfera.rings = 6
	esfera.material = _mat_hierro
	bola.mesh = esfera
	bola.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if m.tipo == "palanqueta":
		# Dos medias balas unidas por una barra, girando sobre sí mismas: es lo que segaba jarcia.
		var barra := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = m.radio * 0.3
		cil.bottom_radius = m.radio * 0.3
		cil.height = 0.30
		cil.material = _mat_hierro
		barra.mesh = cil
		barra.rotation.z = PI * 0.5
		raiz.add_child(barra)
		bola.position = Vector3(-0.15, 0, 0)
		var otra := bola.duplicate() as MeshInstance3D
		otra.position = Vector3(0.15, 0, 0)
		raiz.add_child(otra)
		_giro = Vector3(0.0, 0.0, 25.0)
	raiz.add_child(bola)
	add_child(raiz)
	_malla = raiz


func _colocar_malla(adelanto: float) -> void:
	if _malla == null:
		return
	_malla.global_position = punto(_p0, _v0, _t + adelanto)
	if _giro != Vector3.ZERO:
		_malla.rotation = _giro * (_t + adelanto)
	_malla.scale = Vector3.ONE * _escala_visible(_malla.global_position)


## Píxeles por debajo de los cuales no se dibuja la bala, por lejos que esté.
##
## Con su tamaño real no se ve: una rasa de 7,6 cm a 100 m ocupa medio píxel en 1080p y un perdigón
## de metralla dos décimas (medido en la prueba `municion/tamano`). La palanqueta sí se distinguía
## porque mide 30 cm y gira. Así que la bola crece con la distancia lo justo para no bajar de esto
## (2 px: con 3 el usuario la veía demasiado grande, 20-10-2026),
## y de cerca, donde ya pasa de esos píxeles, se dibuja con su tamaño de verdad. Solo cambia lo que
## se DIBUJA: el vuelo y el choque siguen siendo los del proyectil real.
const PIXELES_MIN := 2.0


func _escala_visible(donde: Vector3) -> float:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return 1.0
	var m := tipo()
	# Lo que mide de punta a punta: la bola, o la barra entera de la palanqueta.
	var tam := m.radio * 2.0 + (0.30 if m.tipo == "palanqueta" else 0.0)
	var alto := float(vp.get_visible_rect().size.y)
	var metro_px := 2.0 * cam.global_position.distance_to(donde) * tan(deg_to_rad(cam.fov) * 0.5) \
		/ maxf(alto, 1.0)
	return maxf(1.0, PIXELES_MIN * metro_px / tam)


func _process(_delta: float) -> void:
	if not _viva:
		return
	var paso := 1.0 / float(maxi(Engine.physics_ticks_per_second, 1))
	_colocar_malla(Engine.get_physics_interpolation_fraction() * paso)


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
	var t_antes := _t
	_t += delta
	var ahora := punto(_p0, _v0, _t)
	# ¿Ha chocado con algo por el camino?
	var g := _rayo(_anterior, ahora)
	if not g.is_empty():
		golpe = g
		_impactar(g["position"], g.get("collider"))
		return
	# ¿Ha caído al agua? En la OLA, no en el plano: cruzar la lámina entre dos pasos se busca por
	# bisección sobre la misma parábola, así que el punto de caída queda en la superficie que se
	# ve y no medio paso (1,8 m) más allá.
	if ahora.y <= superficie(ahora.x, ahora.z, altura_mar):
		var t_agua := _cruce_con_el_agua(t_antes, _t)
		var p := punto(_p0, _v0, t_agua)
		_salpicar(p)
		_impactar(p, null)
		return
	_anterior = ahora
	global_position = ahora
	if _t > vida_max:
		_impactar(ahora, null)


## El primer cuerpo que corta el segmento, saltando lo que no es blanco: los cuerpos del barco que
## disparó y la caja de un barco que tiene dianas (ver `mascara`). Se repite el rayo excluyendo lo
## saltado; cuatro vueltas bastan porque en un paso de 1,8 m no caben más cosas.
func _rayo(desde: Vector3, hasta: Vector3) -> Dictionary:
	var espacio := get_world_3d().direct_space_state
	var par := PhysicsRayQueryParameters3D.create(desde, hasta)
	par.collision_mask = mascara
	var fuera: Array[RID] = []
	for _i in 6:
		par.exclude = fuera
		var g := espacio.intersect_ray(par)
		if g.is_empty():
			return g
		var c: Object = g.get("collider")
		var barco := _barco_de(c as Node)
		var saltar := barco != null and barco == origen
		if not saltar and barco != null and c == barco and barco.has_method("tiene_dianas"):
			saltar = bool(barco.call("tiene_dianas"))
		if not saltar:
			return g
		fuera.append(g["rid"])
	return {}


static func _barco_de(n: Node) -> Node:
	while n != null:
		if n.has_method("canones_de"):
			return n
		n = n.get_parent()
	return null


func _cruce_con_el_agua(t0: float, t1: float) -> float:
	for _i in 14:
		var tm := (t0 + t1) * 0.5
		var p := punto(_p0, _v0, tm)
		if p.y <= superficie(p.x, p.z, altura_mar):
			t1 = tm
		else:
			t0 = tm
	return t1


func _salpicar(donde: Vector3) -> void:
	var s := Salpicadura.new()
	s.name = "Salpicadura"
	# Un perdigón levanta una pluma; una rasa, una columna. Con el radio y no a ojo por tipo.
	s.alto = clampf(tipo().radio / 0.038, 0.25, 1.2) * 2.2
	var raiz := get_tree().current_scene
	if raiz == null:
		raiz = get_tree().root
	raiz.add_child(s)
	s.global_position = donde


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

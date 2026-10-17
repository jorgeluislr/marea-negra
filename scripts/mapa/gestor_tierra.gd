class_name GestorTierra
extends Node3D

## Pone y quita el relieve del mundo según dónde está el barco, por celdas de 1 km (`Relieve`).
##
## Dos formas de estar una celda en el mundo:
##
## - **El detalle**, a menos de `distancia_carga`: la malla de 251 × 251 alturas con el LOD que
##   genera Godot, y su colisión. Se construye entera en un HILO de `WorkerThreadPool` —leer el
##   fichero, la malla, el LOD, la forma de colisión— y el principal solo la mete en el árbol.
##   Medido con `tools/coste_relieve.tscn`: ~0,45 s por celda en el hilo y <1 ms en el principal.
## - **La silueta**, hasta `distancia_silueta`: la versión basta (26 × 26, 40 m), sin colisión.
##   Más allá la esconde la curvatura (`Horizonte`): con el planeta de este mundo un cerro de 250 m
##   se ve hasta unos 18 km. Mientras una celda tiene detalle, su silueta no se dibuja.
##
## Entre carga y descarga hay histéresis: un barco en el límite no pide y suelta la celda cada frame.
##
## **Nada pesado en un solo frame.** Las telas `SoftBody3D` se rompen si nacen o se asientan durante
## un tirón (ver `mar.gd`, `MARGEN_ASENTADO`): el gestor no pide nada hasta que las telas están
## asentadas, mete UNA pieza por frame y el índice del relieve se lee también en un hilo.
##
## Origen flotante: el gestor está ANCLADO AL MAPA (grupo `anclado_al_mapa`), así que en un salto
## (`Origen.llevar_a`) se mueve él con todas sus celdas, que van en coordenadas absolutas dentro.

@export var relieve: Relieve
## Las islas del mundo. El gestor no las dibuja (eso es el relieve), pero es quien las tiene a mano:
## `Origen` las busca aquí para resolver `--en "<isla>"`.
@export var archipielago: Archipielago
## Material compartido por todo el relieve. El gestor le pone cada frame la curvatura y el nivel del
## agua: uno solo, así que una sola escritura vale para todas las celdas.
@export var material: ShaderMaterial
## A qué distancia del borde de una celda se pide su detalle, en metros.
@export var distancia_carga := 1500.0
## A qué distancia se suelta.
@export var distancia_descarga := 2000.0
## Hasta dónde se ponen siluetas, y desde dónde se quitan.
@export var distancia_silueta := 15000.0
@export var distancia_silueta_quitar := 17000.0
## Cada cuánto se revisa qué celdas tocan, en segundos. El barco va a 4,5 m/s.
@export var intervalo := 0.25
## Cuántas construcciones a la vez en los hilos: si se piden de golpe todas las siluetas de 15 km a
## la redonda, los hilos se llenan y el detalle cercano llega tarde.
@export var hilos_detalle := 3
@export var hilos_silueta := 6

## Sobre qué punto se decide. Sin poner, el barco activo; las pruebas y las herramientas ponen aquí
## un marcador para mover el "barco" sin navegar.
var foco: Node3D = null

var _detalle := {}        # Vector2i -> Node3D
var _pedidas := {}        # Vector2i -> bool (sigue haciendo falta)
var _siluetas := {}       # Vector2i -> MeshInstance3D
var _sil_pedidas := {}    # Vector2i -> bool
var _hechas: Array[Dictionary] = []
var _mutex := Mutex.new()
var _tareas: Array[int] = []     # las de WorkerThreadPool aún sin esperar
var _listo := false
var _reloj := 0.0


func _ready() -> void:
	add_to_group("tierra")
	add_to_group("anclado_al_mapa")
	var o := get_node_or_null("/root/Origen")
	if o != null:
		position -= Vector3(o.x, 0.0, o.z)
	if relieve == null:
		push_warning("GestorTierra: sin relieve.")
		return
	_tareas.append(WorkerThreadPool.add_task(relieve.cargar))
	_a_su_tiempo()


## Antes de irse espera a sus hilos: uno que siga construyendo una celda escribiría en un gestor
## liberado. Pasó al cerrar la batería (`'lado' on a null instance` y un fallo de segmentación).
func _exit_tree() -> void:
	for id in _tareas:
		WorkerThreadPool.wait_for_task_completion(id)
	_tareas.clear()


## Qué se decide desde dónde: el foco puesto o el barco activo.
func foco_actual() -> Node3D:
	if foco != null and is_instance_valid(foco):
		return foco
	return get_tree().get_first_node_in_group("barco_activo") as Node3D


## "fuera", "pidiendo" o "cargada".
func estado_celda(c: Vector2i) -> String:
	if _detalle.has(c):
		return "cargada"
	if _pedidas.has(c):
		return "pidiendo"
	return "fuera"


func nodo_celda(c: Vector2i) -> Node3D:
	return _detalle.get(c)


func silueta_celda(c: Vector2i) -> MeshInstance3D:
	return _siluetas.get(c)


func siluetas() -> int:
	return _siluetas.size()


func _process(delta: float) -> void:
	if material != null:
		material.set_shader_parameter("radio_tierra",
			Horizonte.radio_tierra if Horizonte.activa else 1e12)
		material.set_shader_parameter("nivel_agua", Oleaje.nivel)
	if relieve == null or not _listo or not relieve.listo():
		return
	_recoger()
	_reloj -= delta
	if _reloj > 0.0:
		return
	_reloj = intervalo
	var f := foco_actual()
	if f == null:
		return
	# En ABSOLUTO: las celdas lo están, y el barco se recentra cada 2 km.
	var o := get_node_or_null("/root/Origen")
	var g: Vector3 = o.a_global(f.global_position) if o != null else f.global_position
	_revisar(Vector2(g.x, g.z))


func _revisar(p: Vector2) -> void:
	var c0 := relieve.celda_de(p)
	# Detalle: lo cercano primero, y como mucho `hilos_detalle` a la vez.
	var r := int(ceil(distancia_carga / relieve.celda))
	var cerca: Array[Vector2i] = []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := c0 + Vector2i(dx, dz)
			if relieve.tiene(c) and not _detalle.has(c) and not _pedidas.has(c) \
					and _distancia(c, p) <= distancia_carga:
				cerca.append(c)
	cerca.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _distancia(a, p) < _distancia(b, p))
	for c in cerca:
		if _pedidas.size() >= hilos_detalle:
			break
		_pedidas[c] = true
		_tareas.append(WorkerThreadPool.add_task(_construir_detalle.bind(c)))
	for c in _detalle.keys():
		if _distancia(c, p) > distancia_descarga:
			_soltar(c)
	for c in _pedidas.keys():
		_pedidas[c] = _distancia(c, p) <= distancia_descarga

	# Siluetas.
	var rs := int(ceil(distancia_silueta / relieve.celda))
	var lejos: Array[Vector2i] = []
	for dz in range(-rs, rs + 1):
		for dx in range(-rs, rs + 1):
			var c := c0 + Vector2i(dx, dz)
			if relieve.tiene(c) and not _siluetas.has(c) and not _sil_pedidas.has(c) \
					and _distancia(c, p) <= distancia_silueta:
				lejos.append(c)
	lejos.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return _distancia(a, p) < _distancia(b, p))
	for c in lejos:
		if _sil_pedidas.size() >= hilos_silueta:
			break
		_sil_pedidas[c] = true
		_tareas.append(WorkerThreadPool.add_task(_construir_silueta.bind(c)))
	for c in _siluetas.keys():
		if _distancia(c, p) > distancia_silueta_quitar:
			var s: Node = _siluetas[c]
			_siluetas.erase(c)
			s.queue_free()


## Distancia en planta de `p` al rectángulo de la celda `c`; 0 dentro.
func _distancia(c: Vector2i, p: Vector2) -> float:
	var x0 := c.x * relieve.celda
	var z0 := c.y * relieve.celda
	var dx := maxf(maxf(x0 - p.x, 0.0), p.x - (x0 + relieve.celda))
	var dz := maxf(maxf(z0 - p.y, 0.0), p.y - (z0 + relieve.celda))
	return Vector2(dx, dz).length()


## Mete en el árbol UNA pieza terminada por frame, el detalle antes que las siluetas.
func _recoger() -> void:
	# Las terminadas se ESPERAN (vuelve en el acto) y se olvidan: Godot pide esperar cada tarea.
	var vivas: Array[int] = []
	for id in _tareas:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			vivas.append(id)
	_tareas = vivas
	_mutex.lock()
	if _hechas.is_empty():
		_mutex.unlock()
		return
	var k := 0
	for i in _hechas.size():
		if _hechas[i]["tipo"] == "detalle":
			k = i
			break
	var h: Dictionary = _hechas.pop_at(k)
	_mutex.unlock()
	var c: Vector2i = h["c"]
	var esquina := Vector3(c.x * relieve.celda, Oleaje.nivel, c.y * relieve.celda)
	if h["tipo"] == "detalle":
		var sigue: bool = _pedidas.get(c, false)
		_pedidas.erase(c)
		if not sigue:
			return
		var n := Node3D.new()
		n.name = "Celda_%d_%d" % [c.x, c.y]
		n.position = esquina
		var mi := MeshInstance3D.new()
		mi.mesh = h["malla"]
		mi.material_override = material
		n.add_child(mi)
		# La colisión es la rejilla de alturas tal cual, escalada UNIFORME por el paso (la única
		# escala que admite una forma sin quejarse) y centrada en la celda.
		var cuerpo := StaticBody3D.new()
		cuerpo.collision_layer = 1
		cuerpo.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = h["forma"]
		cs.scale = Vector3.ONE * relieve.paso
		cs.position = Vector3(relieve.celda * 0.5, 0.0, relieve.celda * 0.5)
		cuerpo.add_child(cs)
		n.add_child(cuerpo)
		add_child(n)
		_detalle[c] = n
		var s: Node3D = _siluetas.get(c)
		if s != null:
			s.visible = false
	else:
		_sil_pedidas.erase(c)
		var s := MeshInstance3D.new()
		s.name = "Silueta_%d_%d" % [c.x, c.y]
		s.mesh = h["malla"]
		s.material_override = material
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.position = esquina
		s.visible = not _detalle.has(c)
		add_child(s)
		_siluetas[c] = s


func _soltar(c: Vector2i) -> void:
	var n: Node3D = _detalle[c]
	_detalle.erase(c)
	# La silueta vuelve ANTES de quitar el detalle: si no, habría un frame sin tierra.
	var s: Node3D = _siluetas.get(c)
	if s != null:
		s.visible = true
	remove_child(n)
	n.queue_free()


# ── En los hilos ─────────────────────────────────────────────────────────────────────────────────

func _construir_detalle(c: Vector2i) -> void:
	var h := relieve.leer(c)
	var malla := _malla(h, relieve.lado, relieve.paso, true)
	var forma := HeightMapShape3D.new()
	forma.map_width = relieve.lado
	forma.map_depth = relieve.lado
	var datos := PackedFloat32Array()
	datos.resize(h.size())
	for k in h.size():
		datos[k] = h[k] / relieve.paso
	forma.map_data = datos
	_mutex.lock()
	_hechas.append({"tipo": "detalle", "c": c, "malla": malla, "forma": forma})
	_mutex.unlock()


func _construir_silueta(c: Vector2i) -> void:
	var h := relieve.leer_basto(c)
	var malla := _malla(h, relieve.lado_basto, relieve.paso * relieve.basto, false)
	_mutex.lock()
	_hechas.append({"tipo": "silueta", "c": c, "malla": malla})
	_mutex.unlock()


## Malla de una rejilla de alturas cuadrada de `lado` × `lado` con `paso` metros entre ellas.
static func _malla(h: PackedFloat32Array, lado: int, paso: float, con_lod: bool) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normales := PackedVector3Array()
	verts.resize(lado * lado)
	normales.resize(lado * lado)
	for j in lado:
		for i in lado:
			var k := j * lado + i
			verts[k] = Vector3(i * paso, h[k], j * paso)
			var hx := h[j * lado + mini(i + 1, lado - 1)] - h[j * lado + maxi(i - 1, 0)]
			var hz := h[mini(j + 1, lado - 1) * lado + i] - h[maxi(j - 1, 0) * lado + i]
			normales[k] = Vector3(-hx, 2.0 * paso, -hz).normalized()
	var indices := PackedInt32Array()
	for j in lado - 1:
		for i in lado - 1:
			var a := j * lado + i
			# Godot dibuja la cara cuyo (B−A)×(C−A) apunta EN CONTRA de la cámara: aquí hacia abajo,
			# así que se ve desde arriba. Ver la memoria caras-de-malla-en-godot.
			indices.append_array([a, a + 1, a + lado, a + 1, a + lado + 1, a + lado])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normales
	arr[Mesh.ARRAY_INDEX] = indices
	if not con_lod:
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


## No pide nada hasta que las telas del barco están montadas y asentadas: mismo criterio y mismo
## margen que `mar.gd` (`_a_su_tiempo`, `MARGEN_ASENTADO`), por la misma razón.
func _a_su_tiempo() -> void:
	var t := 0.0
	while t < 1.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		var b := get_tree().get_first_node_in_group("barco_activo")
		if b == null:
			continue
		var faltan := false
		for h in b.get_children():
			if h.has_method("datos_depuracion") and (h.datos_depuracion() as Dictionary).is_empty():
				faltan = true
		if not faltan:
			await get_tree().create_timer(2.5).timeout
			break
	_listo = true

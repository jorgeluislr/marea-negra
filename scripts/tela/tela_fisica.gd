class_name TelaFisica
extends Node3D

## Paño de tela simulado con física de verdad: sustituye una malla con piel del modelo por un
## `SoftBody3D` cuyos vértices de anclaje siguen al esqueleto y cuyo resto cuelga y se infla
## con el viento.
##
## Esta es la clase del MECANISMO, y sabe hacer lo que es común a cualquier paño físico:
## soldar las costuras, sacar los anclajes del canal AZUL de `Col`, montar el cuerpo y su área
## de viento, llevar cada ancla al sitio que le pide la piel, y congelar o soltar el paño
## entero. Lo que cada paño hace con eso va en las hojas:
##
##   · `VelaFisica`  — se arría e iza: decide cuándo congelar el paño y lo recoge contra la percha.
##   · `BanderaFisica` — es una veleta: gira su hueso a sotavento.
##
## Contrato de la capa de color `Col` (una sola capa RGBA; glTF no exporta más):
##   R — peso de movimiento de la vela para el shader de tela (`TelaShader`). Aquí no se usa.
##   G — marca de bandera para ese mismo shader. Aquí tampoco.
##   B — ANCLA: el vértice va cosido al esqueleto y no cae. Es lo único que lee esta clase.
##
## Cuatro cosas que hay que respetar y que no se descubren solas:
##  - `SoftBody3D` hereda de `MeshInstance3D`, así que un `TelaShader` que escanease mallas por
##    color le pondría el shader encima de la física. Por eso el paño físico se construye SIN
##    capa de color, y por eso el shader ya no escanea: se le dice qué malla anima.
##  - `set_point_pinned(k, true, ruta)` LLEVA el punto al nodo de esa ruta. El nodo tiene que
##    estar ya donde quieres el punto.
##  - `get_point_transform()` devuelve posiciones GLOBALES, no locales, y el nodo del cuerpo
##    se queda con transform identidad al empezar a simular.
##  - Godot 4 no expone fuerzas sobre SoftBody: el viento entra como gravedad direccional de
##    un Area3D en SPACE_OVERRIDE_REPLACE, mezclando viento y peso propio.
##
## Medido en tools/medir_softbody_foque3.gd: 0,147 ms de física por vela con 253 vértices (el
## descarte de agosto fue con 8.332 vértices y 18 ms; ver la memoria del proyecto).

@export var nombre_malla := "foque"           ## Malla del paño dentro del modelo.
@export var activo := true

@export_group("Solver")
@export_range(1, 80) var precision := 5
@export var masa := 8.0
@export_range(0.0, 1.0) var rigidez := 0.5
@export_range(0.0, 1.0) var amortiguacion := 0.01
@export_range(0.0, 1.0) var arrastre := 0.3

@export_group("Viento")
@export var empuje_viento := 7.0              ## m/s² por unidad de fuerza del viento.
@export var peso_propio := 3.0                ## m/s² hacia abajo; da caída al paño.
@export var radio_area := 30.0

## FLAMEO: cuánto oscila el viento de lado a lado, en tanto por uno de su propia fuerza.
##
## El viento del juego es un campo UNIFORME (una `Area3D` con gravedad direccional) y sus
## ráfagas van a 0,1-0,5 Hz. Un campo uniforme y lento no hace flamear a nada: la tela se
## coloca en su equilibrio y ahí se queda. El flameo de verdad es una inestabilidad
## aeroelástica —el paño desvía el aire, el aire empuja el paño— y esa realimentación no
## existe aquí, así que se repone como una componente transversal que oscila.
##
## Medido en la bandera: sin esto se mueve 36-44 mm y parece de cartón por muy bien orientada
## que esté. **No es un apaño de la bandera**: le pasa a cualquier paño que reciba el viento
## de canto, solo que una vela portando va tensa y no se le nota. Por eso vive aquí y no en
## `BanderaFisica`, y por eso viene a CERO: la vela que deba flamear lo pedirá, y el día que
## el flameo dependa del ángulo de ataque se calcula aquí mismo.
@export_range(0.0, 2.0) var flameo := 0.0
## Frecuencia del flameo en Hz con el viento a fuerza 1; escala con la fuerza del viento, como
## el número de Strouhal (`f ≈ St·U/L`), que es de dónde sale que una bandera de un metro
## ondee a 1-3 Hz.
@export_range(0.1, 8.0) var flameo_frecuencia := 1.4
## Flameo AÑADIDO cuando la vela está DESVENTADA, proporcional a lo que deja de aprovechar del
## viento (`1 - factor_viento()` del barco, el mismo número con el que el casco se propulsa y
## con el que el audio dispara los golpes de lona: así las tres cosas no pueden contradecirse).
##
## Es lo que arregla el "latido" de la mayor. Medido en fachada (`factor_viento` = 0 toda la
## tirada): el paño se movía 0,27 m/s de mediana con picos de 1,06, o sea **4,0 veces la
## mediana**, y los picos caían cada 6,4 s —medio ciclo del bamboleo de dirección del viento—
## justo donde la percha gira más rápido. Navegando portando el mismo pico es 2,2 veces la
## mediana y no es periódico, que es la señal de que el latido es flameo y no un fallo del
## trimado: sin realimentación aeroelástica el paño no flamea finito, pega un chasquido entero
## cada medio ciclo.
@export_range(0.0, 3.0) var flameo_por_desventa := 0.0

@export_group("Arranque")
## El paño NO se monta hasta que el reloj del juego va fino. Al arrancar la escena hay frames
## de 0,12-0,14 s (carga del modelo, compilación de shaders), y en un frame así el motor da
## ~7 pasos de física seguidos mientras las anclas solo se recolocan UNA vez por frame, en
## `_process`: la tela cae siete pasos con los anclajes congelados, se descuelga de golpe y el
## solver ya no vuelve a cerrar esas aristas. Medido en la balandra: con un frame de 0,122 s la
## mayor pasa de 0 a 63 aristas estiradas por encima del 25 %, y ahí se queda. Por eso un barco
## reinstanciado con TAB, que nace con el juego ya rodando, sale limpio y el del arranque no.
@export var delta_estable := 1.0 / 30.0   ## Frame que se considera "normal", en segundos.
@export_range(1, 30) var frames_estables := 3
@export var espera_max := 5.0             ## Tope: si el juego va lento de verdad, se monta igual.

@export_group("Perchas")
## Capa de los colisionadores de perchas_solidas.gd. Sin esto el paño libre atraviesa la
## botavara y el pico y sale una sierra de picos por debajo de ellos.
@export_flags_3d_physics var capa_perchas := 16
@export_group("")

var _skel: Skeleton3D
var _cuerpo: SoftBody3D
var _malla_original: MeshInstance3D
var _area: Area3D
var _tr := Transform3D()                       ## sitio del paño respecto al esqueleto
var _anclas: Array[Node3D] = []                ## uno por vértice
var _reposo: PackedVector3Array = PackedVector3Array()   ## sitio de reposo, espacio del esqueleto
var _hueso_de: PackedInt32Array = PackedInt32Array()     ## 4 huesos por vértice
var _peso_de: PackedFloat32Array = PackedFloat32Array()  ## y sus 4 pesos
var _fijo: PackedByteArray = PackedByteArray()           ## 1 = anclado siempre (azul en Col)
var _agarre: PackedVector3Array = PackedVector3Array()   ## dónde se agarró al empezar a recoger
var _recogiendo := false
var _aristas: PackedInt32Array = PackedInt32Array()      ## pares de índices; para depurar
var _largo0: PackedFloat32Array = PackedFloat32Array()   ## largo de cada arista en reposo
var _rid := RID()                              ## cuerpo físico, para mover puntos sueltos
var _estables := 0                             ## frames seguidos con el reloj fino
var _t_espera := 0.0
var _fase_flameo := 0.0                       ## fase del flameo transversal
var _barco_tela: Node3D                       ## de quién cuelga; para preguntarle la desventa

## Bits reservados para que cada paño tenga su propia área de viento (capas 25 a 32). Ocho
## bastan: un barco lleva tres telas y solo hay dos barcos vivos a la vez como mucho.
const _CAPAS_VIENTO := 8
const _PRIMERA_CAPA_VIENTO := 24
const _MASCARA_VIENTO := ((1 << _CAPAS_VIENTO) - 1) << _PRIMERA_CAPA_VIENTO
static var _reparto_viento := 0
var _delta_montaje := 0.0                      ## tamaño del frame en el que se montó el paño


func _ready() -> void:
	if not activo:
		set_process(false)
		return
	# El montaje lo dispara `_process` cuando el reloj se estabiliza; ver `delta_estable`.


func _buscar_barco() -> Node3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n as Node3D
		n = n.get_parent()
	return get_parent() as Node3D


## Transform de un nodo respecto a un ancestro, sin depender de global_transform.
func _relativo(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != raiz:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


func _montar() -> void:
	var barco := _buscar_barco()
	_barco_tela = barco
	if barco == null:
		return
	var es := barco.find_children("*", "Skeleton3D", true, false)
	if es.is_empty():
		push_warning("%s: sin Skeleton3D bajo %s" % [name, barco.name])
		return
	_skel = es[0] as Skeleton3D
	var l := barco.find_children(nombre_malla, "MeshInstance3D", true, false)
	if l.is_empty():
		push_warning("%s: no encuentro la malla '%s'" % [name, nombre_malla])
		return
	_malla_original = l[0] as MeshInstance3D
	var arr := _malla_original.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var hu: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var pe: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	if cols.is_empty():
		push_warning("%s: la malla no lleva color de vértice; sin él no sé qué anclar." % name)
		return

	# SOLDAR los vértices coincidentes. glTF parte cada vértice en las costuras del UV (una malla
	# de 1.217 sale con 1.347 en el .glb), y el SoftBody trata cada duplicado como un punto SUELTO
	# unido solo a un lado de la costura: bajo la carga del viento la costura se ABRE y ese borde
	# se estira hasta 1,3 m (medido). Soldando por posición, cada costura vuelve a ser un punto
	# único cosido a los dos lados, y la tela deja de descoserse. La media de estiramiento cae de
	# ~9 % a ~0,2 %. El precio es que el UV se junta en la costura (mínimo en una lona uniforme).
	var normales: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx_orig: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var canon := PackedInt32Array()   # índice original -> índice soldado
	canon.resize(vs.size())
	var pos_a_canon := {}
	var vs_s := PackedVector3Array()
	var nor_s := PackedVector3Array()
	var uv_s := PackedVector2Array()
	var orig_de := PackedInt32Array()   # índice soldado -> un original representativo
	for k in vs.size():
		var v := vs[k]
		var clave := "%d_%d_%d" % [roundi(v.x * 2000.0), roundi(v.y * 2000.0), roundi(v.z * 2000.0)]
		if pos_a_canon.has(clave):
			canon[k] = pos_a_canon[clave]
		else:
			var ci := vs_s.size()
			pos_a_canon[clave] = ci
			canon[k] = ci
			vs_s.append(v)
			if normales.size() > k: nor_s.append(normales[k])
			if uvs.size() > k: uv_s.append(uvs[k])
			orig_de.append(k)
	var idx_s := PackedInt32Array()
	idx_s.resize(idx_orig.size())
	for i in idx_orig.size():
		idx_s[i] = canon[idx_orig[i]]

	# Aristas únicas de la malla soldada. Son las restricciones de distancia que resuelve el
	# solver, así que medir su largo contra el de reposo es medir el estiramiento de verdad.
	var vistas := {}
	for i in range(0, idx_s.size(), 3):
		for j in 3:
			var ia: int = idx_s[i + j]
			var ib: int = idx_s[i + (j + 1) % 3]
			var lo: int = mini(ia, ib)
			var hi: int = maxi(ia, ib)
			var clave_a: int = lo * 1000000 + hi
			if vistas.has(clave_a):
				continue
			vistas[clave_a] = true
			_aristas.append(lo)
			_aristas.append(hi)

	# Paño físico soldado, SIN color: el color es de la malla de autor, no de la simulada.
	var na := []
	na.resize(Mesh.ARRAY_MAX)
	na[Mesh.ARRAY_VERTEX] = vs_s
	if nor_s.size() == vs_s.size(): na[Mesh.ARRAY_NORMAL] = nor_s
	if uv_s.size() == vs_s.size(): na[Mesh.ARRAY_TEX_UV] = uv_s
	na[Mesh.ARRAY_INDEX] = idx_s
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
	am.surface_set_material(0, _malla_original.mesh.surface_get_material(0))

	_tr = _relativo(_malla_original, _skel)
	_malla_original.visible = false

	# Un nodo de anclaje por vértice SOLDADO. Un vértice se ancla si CUALQUIER duplicado suyo era
	# azul; sus pesos/huesos salen de un original representativo.
	var fijo_c := PackedByteArray()
	fijo_c.resize(vs_s.size())
	for k in vs.size():
		if cols[k].b > 0.5: fijo_c[canon[k]] = 1
	var fijos := 0
	var con_piel := hu.size() >= vs.size() * 4
	for ci in vs_s.size():
		var ko := orig_de[ci]
		var p := _tr * vs_s[ci]
		for j in 4:
			_hueso_de.append(hu[ko * 4 + j] if con_piel else -1)
			_peso_de.append(pe[ko * 4 + j] if con_piel else 0.0)
		var m := Node3D.new()
		m.name = "Ancla_%s_%d" % [nombre_malla, ci]
		_skel.add_child(m)
		m.position = p
		_anclas.append(m)
		_reposo.append(p)
		_agarre.append(p)
		_fijo.append(fijo_c[ci])
		if fijo_c[ci] == 1:
			fijos += 1

	_largo0.resize(_aristas.size() / 2)
	for e in _largo0.size():
		_largo0[e] = _reposo[_aristas[e * 2]].distance_to(_reposo[_aristas[e * 2 + 1]])

	_cuerpo = SoftBody3D.new()
	_cuerpo.name = "PanoFisico_" + nombre_malla     # nunca igual que este nodo de control
	_cuerpo.mesh = am
	_cuerpo.transform = _tr
	_cuerpo.simulation_precision = precision
	_cuerpo.total_mass = masa
	_cuerpo.linear_stiffness = rigidez
	_cuerpo.damping_coefficient = amortiguacion
	_cuerpo.drag_coefficient = arrastre
	_cuerpo.ray_pickable = false
	_cuerpo.collision_mask = capa_perchas
	_skel.add_child(_cuerpo)
	for k in _anclas.size():
		if _fijo[k] == 1:
			_cuerpo.set_point_pinned(k, true, _anclas[k].get_path())
	_rid = _cuerpo.get_physics_rid()

	# Viento: gravedad direccional que reemplaza la del mundo dentro del área.
	_area = Area3D.new()
	_area.name = "AreaViento_" + nombre_malla
	var cs := CollisionShape3D.new()
	var sf := SphereShape3D.new()
	sf.radius = radio_area
	cs.shape = sf
	_area.add_child(cs)
	_area.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	_area.priority = 10
	# El area SOLO debe gobernar a SU pano. Con la mascara por defecto las tres areas del barco
	# —una por tela, 30 m de radio, todas REPLACE y la misma prioridad— se solapan sobre los tres
	# panos, y REPLACE deja mandar a UNA sola: la que el motor procese la ultima. Medido dando
	# gravedad 30 hacia +X a un area cada vez, la bandera se iba 0,56 m con la area del FOQUE y
	# 0,22 con la suya. O sea que su empuje, su peso propio y su flameo no llegaban nunca.
	#
	# Se le da a cada pano un bit propio ADEMAS del que ya tenia (no se le quita el 1, para no
	# cambiar quien puede chocar con la tela) y el area apunta solo a ese bit.
	_cuerpo.collision_layer |= _bit_viento()
	_area.collision_mask = _cuerpo.collision_layer & _MASCARA_VIENTO
	_area.collision_layer = 0
	barco.add_child(_area)
	_area.position = Vector3.ZERO

	_montado(barco)

	print("%s %s: %d vertices en el .glb -> %d soldados, %d anclados siempre, %d libres"
		% [_etiqueta(), nombre_malla, vs.size(), vs_s.size(), fijos, vs_s.size() - fijos])


## Nombre con el que la hoja se presenta en los mensajes.
func _etiqueta() -> String:
	return "tela_fisica"


## Gancho para que la hoja prepare lo suyo cuando el paño ya está montado (huesos propios,
## calibraciones que necesiten la malla o el esqueleto). No hace nada en la base.
func _montado(_barco: Node3D) -> void:
	pass


## Todo lo que necesita depurar_tela.gd para pintar el paño. Se expone tal cual (sin copiar)
## porque el visor solo lee.
func datos_depuracion() -> Dictionary:
	if _cuerpo == null:
		return {}
	return {
		"nombre": nombre_malla,
		"cuerpo": _cuerpo,
		"skel": _skel,
		"fijo": _fijo,
		"anclas": _anclas,
		"reposo": _reposo,
		"aristas": _aristas,
		"largo0": _largo0,
		"huesos": _hueso_de,
		"pesos": _peso_de,
		"recogiendo": _recogiendo,
		# El frame en el que nació el paño: si fue largo, la tela sale estirada y ya no se
		# recupera. Lo expone para que las pruebas verifiquen la garantía y no la casualidad.
		"delta_montaje": _delta_montaje,
		"espera_montaje": _t_espera,
	}


## Manos a la obra: cada vértice suelto recibe su anclaje justo donde está ahora, y se fija.
## Capturado en espacio del esqueleto, así que el lío queda pegado al barco.
func _agarrar() -> void:
	var inv := _skel.global_transform.affine_inverse()
	for k in _anclas.size():
		if _fijo[k] == 1:
			continue
		var p := inv * _cuerpo.get_point_transform(k)   # get_point_transform va en GLOBAL
		_agarre[k] = p
		_anclas[k].position = p
		_cuerpo.set_point_pinned(k, true, _anclas[k].get_path())
	_recogiendo = true


## Se suelta el paño en la forma que tenía al agarrarlo, así que la física sigue sin salto.
func _soltar() -> void:
	for k in _anclas.size():
		if _fijo[k] == 0:
			_cuerpo.set_point_pinned(k, false)
	_recogiendo = false


func _process(delta: float) -> void:
	if _cuerpo == null:
		_esperar_reloj(delta)
		return
	# El orden importa y es el mismo que tenían los nodos sueltos en la escena: primero se
	# mueven los huesos propios del paño (la bandera rola), después se lee la pose resultante,
	# y solo entonces se llevan las anclas. Al revés, las anclas irían un frame por detrás.
	_antes_de_pose(delta)
	# Una matriz por hueso, no una por vértice: pose global por reposo global inverso.
	var n := _skel.get_bone_count()
	var mats: Array[Transform3D] = []
	mats.resize(n)
	for i in n:
		mats[i] = _skel.get_bone_global_pose(i) * _skel.get_bone_global_rest(i).affine_inverse()
	_tras_pose(delta, mats)
	_colocar_anclas(mats)
	_actualizar_viento()


## Cuenta frames normales seguidos y monta el paño cuando hay bastantes. Se mide el frame de
## verdad, no un temporizador: lo que estropea la tela no es "arrancar" sino el tamaño del paso.
func _esperar_reloj(delta: float) -> void:
	_t_espera += delta
	_estables = _estables + 1 if delta <= delta_estable else 0
	if _estables >= frames_estables or _t_espera >= espera_max:
		_delta_montaje = delta
		_montar()


## Gancho previo a leer la pose del esqueleto: para el paño que MUEVE huesos (la bandera).
func _antes_de_pose(_delta: float) -> void:
	pass


## Gancho posterior a la pose: para el paño que reacciona a ella (la vela, que mira su driza).
func _tras_pose(_delta: float, _mats: Array[Transform3D]) -> void:
	pass


## Cuánto se ha llevado ya cada vértice agarrado hacia su sitio del lío, de 0 a 1. En la base
## no hay recogida, así que es 0; `VelaFisica` la deriva del recorrido de su driza.
func _fraccion_recogida() -> float:
	return 0.0


func _colocar_anclas(mats: Array[Transform3D]) -> void:
	var n := mats.size()
	var s := _fraccion_recogida()
	for k in _anclas.size():
		# Los sueltos, mientras nadie los ha agarrado, no hay que tocarlos.
		if _fijo[k] == 0 and not _recogiendo:
			continue
		var destino := Vector3.ZERO
		var total := 0.0
		for j in 4:
			var w: float = _peso_de[k * 4 + j]
			if w <= 0.0:
				continue
			var b: int = _hueso_de[k * 4 + j]
			if b < 0 or b >= n:
				continue
			destino += (mats[b] * _reposo[k]) * w
			total += w
		if total <= 0.0:
			destino = _reposo[k]
		_anclas[k].position = destino if _fijo[k] == 1 else _agarre[k].lerp(destino, s)


## Un bit de capa para este paño, para que su área de viento no gobierne a los demás.
static func _bit_viento() -> int:
	var bit := 1 << (_PRIMERA_CAPA_VIENTO + (_reparto_viento % _CAPAS_VIENTO))
	_reparto_viento += 1
	return bit


func _actualizar_viento() -> void:
	if _area == null:
		return
	# El campo del área va con el viento REAL, no con el aparente: el paño encuentra el aparente
	# él solo, porque vive en espacio de mundo y el barco lo arrastra por él. Ponerle el aparente
	# sería contarlo dos veces.
	var v: Vector3 = Viento.direccion.normalized() * (Viento.fuerza * empuje_viento)
	# La desventa se pide al barco por NOMBRE de método, como el resto del proyecto: una tela
	# puede colgar de algo que no sea un `Barco` y no debe romperse por ello.
	var fla := flameo
	if flameo_por_desventa > 0.0 and _barco_tela != null and _barco_tela.has_method("factor_viento"):
		var desventa: float = 1.0 - clampf(_barco_tela.factor_viento(), 0.0, 1.0)
		fla += flameo_por_desventa * desventa
	if fla > 0.0:
		# Componente transversal que oscila. Dos armónicos inconmensurables (1 y 2,3) para que
		# no se lea como un péndulo: con uno solo el paño va y viene siempre igual.
		var eje := v.normalized().cross(Vector3.UP)
		if eje.length() < 0.01:
			eje = Vector3.RIGHT
		_fase_flameo += get_process_delta_time() * TAU * flameo_frecuencia * maxf(Viento.fuerza, 0.1)
		var onda := sin(_fase_flameo) + 0.4 * sin(_fase_flameo * 2.3 + 1.0)
		v += eje.normalized() * (v.length() * fla * onda)
	var g := v + Vector3.DOWN * peso_propio
	_area.gravity_direction = g.normalized()
	_area.gravity = g.length()

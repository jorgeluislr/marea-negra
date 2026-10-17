extends Node
## Origen flotante (autoload "Origen"): dónde cae el cero del mundo LOCAL en el mapa absoluto.
##
## El mundo es el Caribe a escala 1/25, 122 × 80 km, y las posiciones del motor van en precisión
## simple. A 50 km un `float` solo distingue pasos de 3,9 mm (2⁻⁸ m), y el casco y cada punto del
## paño caen cada paso de física en esa rejilla. Medido con `tools/temblor_lejos.tscn`, segunda
## diferencia de la posición por paso:
##
##                       casco      tela anclada   tela libre   estiramiento medio
##     en el origen      0,19 mm    0,005 mm       2,6 mm       0,007
##     a 50 km           1,55       2,52           7,4          0,032
##
## Así que el barco no se aleja nunca del cero: cuando pasa de `umbral`, se RECENTRA — todo lo
## que vive en el mundo se corre `-d` y el desplazamiento total se acumula aquí, en doble
## precisión (los `float` de GDScript son de 64 bits; los de `Vector3`, de 32). Lo absoluto se
## pregunta con `a_global()` y `a_local()`.
##
## **Qué se mueve y quién se ocupa de qué:**
##
## - Los hijos `Node3D` de las raíces del mundo —el padre del barco activo y la escena actual—
##   los corre este autoload, uno a uno. No se mueve la raíz entera: con la raíz a −50 km y los
##   hijos a +50 km, la posición de mundo de cada hijo saldría de restar dos números grandes en
##   precisión simple, que es exactamente lo que se quiere evitar.
## - Lo `top_level` de dentro (la guía de tiro) no sigue a su padre, así que también lo corre él.
## - Lo que guarda posiciones de mundo en sus propias variables se suscribe a `recentrado`: las
##   telas `SoftBody3D` (sus puntos viven en el servidor de física), la estela del mar, las balas.
## - Lo que depende de la posición ABSOLUTA la lee de aquí: el oleaje (la fase de cada tren), el
##   relieve fino del agua y la textura de la tierra (`origen_mundo`, parámetro global de shader),
##   y el gestor de tierra, que decide qué islas cargar por la posición absoluta del barco.
##
## `Horizonte` no necesita nada: su caída va con la distancia a la CÁMARA, que es relativa.

## El barco se recentra cuando se aleja más de esto del cero, en metros. A 2 km un `float` aún
## distingue 0,12 mm, treinta veces menos que a 50 km; y recentrar cuesta un recorrido del árbol,
## así que no conviene hacerlo a cada rato: a 4,5 m/s es una vez cada siete minutos.
@export var umbral := 2000.0
## Con `false` no se recentra solo. Para medir con y sin (`tools/temblor_lejos.tscn`).
var activo := true

## Desplazamiento acumulado: la posición ABSOLUTA del cero local, en metros (doble precisión).
var x := 0.0
var z := 0.0

## El mundo local se acaba de correr `-d`: quien guarde posiciones de mundo en sus variables
## tiene que restarles `d`. Se emite DESPUÉS de mover los nodos, en el reloj de la física y antes
## que ningún otro `_physics_process` de ese paso.
signal recentrado(d: Vector3)
## El cero local ha pasado a estar `d` más allá en el mapa absoluto, sea por un recentrado o por un
## salto de `llevar_a()`. Para lo que lee lo absoluto pero no guarda nada propio.
signal desplazado(d: Vector3)

## Grupo de lo que está ANCLADO AL MAPA (la tierra): en un salto con `llevar_a()` es lo único que
## se mueve, porque el barco, la cámara y lo que lo rodea viajan con él.
const GRUPO_MAPA := "anclado_al_mapa"


func _ready() -> void:
	# Antes que ningún otro `_physics_process`: que en un mismo paso nadie lea una posición de antes
	# del recentrado y otra de después.
	process_physics_priority = -1000
	_publicar()
	_arranque.call_deferred()


func _physics_process(_delta: float) -> void:
	if not activo:
		return
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		return
	var p := b.global_position
	if Vector2(p.x, p.z).length() > umbral:
		recentrar(Vector3(p.x, 0.0, p.z))


## Posición absoluta de un punto local.
func a_global(p: Vector3) -> Vector3:
	return Vector3(float(p.x) + x, p.y, float(p.z) + z)


## Posición local de un punto absoluto.
func a_local(p: Vector3) -> Vector3:
	return Vector3(float(p.x) - x, p.y, float(p.z) - z)


## Vuelve al origen sin desplazamiento. Para quien monta un mundo nuevo (las pruebas, las
## herramientas): el autoload sobrevive a las escenas.
func reiniciar() -> void:
	x = 0.0
	z = 0.0
	_publicar()


## Corre el mundo local `-d` y acumula `d`. Solo en planta, y en metros enteros: así el origen es
## exacto también en precisión simple y no arrastra decimales de un recentrado al siguiente.
func recentrar(d: Vector3) -> void:
	d = Vector3(roundf(d.x), 0.0, roundf(d.z))
	if d == Vector3.ZERO:
		return
	x += d.x
	z += d.z
	for n in _a_mover():
		n.global_position -= d
	_publicar()
	recentrado.emit(d)
	desplazado.emit(d)


## Lleva el barco activo al punto ABSOLUTO `destino` (x, z) sin moverlo en local: lo que se mueve
## es el mapa. Es el salto de la posición de arranque, y será el de la navegación rápida.
func llevar_a(destino: Vector2) -> void:
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var aqui := Vector2(b.global_position.x, b.global_position.z) if b != null else Vector2.ZERO
	var dx := roundf(float(destino.x) - x - aqui.x)
	var dz := roundf(float(destino.y) - z - aqui.y)
	if dx == 0.0 and dz == 0.0:
		return
	var d := Vector3(dx, 0.0, dz)
	x += dx
	z += dz
	for n in get_tree().get_nodes_in_group(GRUPO_MAPA):
		if n is Node3D:
			(n as Node3D).global_position -= d
	_publicar()
	desplazado.emit(d)


## Lo que hay que correr en un recentrado: los `Node3D` hijos de las raíces del mundo y lo
## `top_level` que cuelgue de ellos (salvo los `SoftBody3D`, que se ocupan de sí mismos: ver
## `TelaFisica`).
func _a_mover() -> Array[Node3D]:
	var raices: Array[Node] = []
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b != null and b.get_parent() != null:
		raices.append(b.get_parent())
	var esc := get_tree().current_scene
	if esc != null and not raices.has(esc):
		raices.append(esc)
	var r: Array[Node3D] = []
	for raiz in raices:
		for h in raiz.get_children():
			if not h is Node3D:
				continue
			# Otra raíz (el mundo dentro de la escena de pruebas) no se mueve: se mueven sus hijos.
			if raices.has(h):
				continue
			r.append(h as Node3D)
	var sueltos: Array[Node3D] = []
	for n in r:
		_sueltos_en(n, sueltos)
	r.append_array(sueltos)
	return r


func _sueltos_en(n: Node, lista: Array[Node3D]) -> void:
	for h in n.get_children():
		if h is Node3D and (h as Node3D).top_level and not h is SoftBody3D:
			lista.append(h as Node3D)
		_sueltos_en(h, lista)


## El origen para los shaders: un parámetro global, para que el agua y la tierra lo lean sin que
## nadie tenga que ir pasándoselo material a material.
func _publicar() -> void:
	RenderingServer.global_shader_parameter_set("origen_mundo", Vector2(x, z))


# ── Posición de arranque ─────────────────────────────────────────────────────

## Distancia al rectángulo de una isla a la que se deja el barco cuando se arranca por su nombre.
## Fuera del bajo que rodea la costa —el rectángulo es el de su batimetría— y lo bastante cerca
## para verla desde cubierta.
const MARGEN_ISLA := 300.0


## Lee `--en` de los argumentos de usuario (`godot ... -- --en 18.32,-64.62` o
## `-- --en "Norman Island"`) y lleva allí el barco en cuanto haya uno.
func _arranque() -> void:
	var args := OS.get_cmdline_user_args()
	if not _pide_en(args):
		return
	var t := 0.0
	while t < 30.0:
		var gestor := get_tree().get_first_node_in_group("tierra")
		var b := get_tree().get_first_node_in_group("barco_activo")
		if gestor != null and b != null:
			var destino = destino_de(args, gestor.get("archipielago"))
			if destino == null:
				push_warning("Origen: no sé dónde está '%s'" % _valor_en(args))
				return
			llevar_a(destino)
			print("Origen: arranque en %s (%.0f, %.0f)" % [_valor_en(args), destino.x, destino.y])
			return
		await get_tree().process_frame
		t += get_process_delta_time()
	push_warning("Origen: se pidió --en y no apareció ni barco ni gestor de tierra")


static func _pide_en(args: PackedStringArray) -> bool:
	return _valor_en(args) != ""


static func _valor_en(args: PackedStringArray) -> String:
	for i in args.size():
		var a := String(args[i])
		if a.begins_with("--en="):
			return a.substr(5).strip_edges()
		if a == "--en" and i + 1 < args.size():
			return String(args[i + 1]).strip_edges()
	return ""


## El punto ABSOLUTO (x, z) que pide `--en`, o `null` si no lo pide o no se encuentra.
##
## Si son dos números, latitud y longitud en grados (oeste negativo), convertidos con
## `Archipielago.de_lat_lon()`. Si no, el nombre de una isla, sin distinguir mayúsculas: el barco
## queda `MARGEN_ISLA` al sur de su rectángulo, en el agua y mirándola.
static func destino_de(args: PackedStringArray, arch: Archipielago) -> Variant:
	var v := _valor_en(args)
	if v == "" or arch == null:
		return null
	var partes := v.split(",")
	if partes.size() == 2 and partes[0].strip_edges().is_valid_float() \
			and partes[1].strip_edges().is_valid_float():
		return arch.de_lat_lon(partes[0].strip_edges().to_float(), partes[1].strip_edges().to_float())
	var buscado := v.to_lower()
	for isla in arch.islas:
		if isla.nombre.to_lower() == buscado:
			var r := isla.limites()
			return Vector2(r.get_center().x, r.end.y + MARGEN_ISLA)
	return null

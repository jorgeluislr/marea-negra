class_name OrigenTest
extends RefCounted

## Paquete `origen`: el origen flotante y la posición de arranque por parámetro.
##
## El Caribe de este mundo mide 122 × 80 km y las posiciones van en precisión simple: a 50 km un
## `float` solo distingue pasos de 3,9 mm, y el casco y la tela tiemblan en esa rejilla. Medido
## con `tools/temblor_lejos.tscn` antes de tener origen flotante: en el origen el casco da 0,19 mm
## de segunda diferencia por paso y los puntos anclados de la tela 0,005; a 50 km, **1,55 y 2,52**,
## con el estiramiento medio de 0,007 a 0,032.
##
## Monta SU PROPIO mundo, con el barco naciendo a 50 km, y para eso suelta el de la batería: por
## eso va el último y solo se puede pedir entero. Al `Origen` se le llama por nombre de nodo y de
## método, no por su clase, para que sin él lo que salga en rojo sea la comprobación y no la
## batería entera caída por un error de parseo (ver `MarcoPruebas.menor_que`).

const MUNDO := "res://scenes/world/main_world.tscn"
const ARCHIPIELAGO := "res://assets/islas/archipielago.res"
const LEJOS := 50000.0


static func correr(m: MarcoPruebas, arbol: SceneTree) -> void:
	m.paquete("origen")
	var o := arbol.root.get_node_or_null("Origen")
	if not m.comprobar(o != null, "existe el autoload Origen"):
		return
	var arch := load(ARCHIPIELAGO) as Archipielago if ResourceLoader.exists(ARCHIPIELAGO) else null
	_arranque(m, o, arch)
	var mundo := await _mundo_lejos(m, arbol, o)
	if mundo == null:
		return
	await _temblor(m, arbol, o)
	await _nodo_suelto(m, arbol, o, mundo)
	await _recentrar_navegando(m, arbol, o)
	await _espejo_lejos(m, arbol, o)
	await _bala(m, arbol, o)
	if arch != null:
		await _tierra(m, arbol, o, arch)
	mundo.queue_free()
	await arbol.process_frame


## `--en 18.32,-64.62` o `--en "Norman Island"`: de dónde sale el punto de arranque.
static func _arranque(m: MarcoPruebas, o: Node, arch: Archipielago) -> void:
	if not m.comprobar(arch != null, "hay archipiélago para resolver el arranque"):
		return
	var esperado := arch.de_lat_lon(18.32, -64.62)
	for args in [["--en", "18.32,-64.62"], ["--en=18.32,-64.62"], ["algo", "--en", " 18.32 , -64.62 "]]:
		var p = o.destino_de(PackedStringArray(args), arch)
		m.comprobar(p is Vector2 and (p as Vector2).distance_to(esperado) < 0.01,
			"`%s` arranca en esa latitud y longitud" % " ".join(args), str(p))
	var nor: Isla = null
	for isla in arch.islas:
		if isla.nombre == "Norman Island":
			nor = isla
	var p = o.destino_de(PackedStringArray(["--en", "norman island"]), arch)
	if m.comprobar(p is Vector2 and nor != null, "`--en \"Norman Island\"` encuentra la isla", str(p)):
		# Al lado de la isla y en el AGUA: arrancar encima de ella dejaría el barco en tierra.
		var d: float = nor.distancia_a(p)
		m.comprobar(d > 50.0 and d < 1000.0, "y deja el barco junto a ella, fuera de su bajo",
			"%.0f m de su rectángulo" % d)
		# El fondo lo sabe el relieve, no el archipiélago (que solo guarda costas).
		var rel := (load("res://assets/islas/relieve_caribe.tres") as Relieve).duplicate() as Relieve
		rel.cargar()
		m.menor_que(rel.altura_en(p), -2.0, "en agua con fondo")
	m.comprobar(o.destino_de(PackedStringArray(["--en", "Isla que no existe"]), arch) == null,
		"un nombre que no existe no da destino")
	m.comprobar(o.destino_de(PackedStringArray(["tela"]), arch) == null, "sin `--en` no hay destino")


## Suelta el mundo de la batería y monta uno con el barco naciendo a 50 km del origen.
static func _mundo_lejos(m: MarcoPruebas, arbol: SceneTree, o: Node) -> Node3D:
	var raiz := arbol.current_scene
	var viejo := raiz.get_node_or_null("Mundo")
	if viejo != null:
		viejo.queue_free()
		await arbol.process_frame
		await arbol.process_frame
	o.reiniciar()
	var mundo := (load(MUNDO) as PackedScene).instantiate() as Node3D
	(mundo.get_node("GestorBarcos") as Node3D).position.x += LEJOS
	raiz.add_child(mundo)
	var b: Node3D = null
	var t := 0.0
	while t < 20.0:
		await arbol.process_frame
		t += arbol.root.get_process_delta_time()
		b = UtilesPruebas.barco(arbol)
		if b != null and _montadas(arbol) >= 3:
			break
	if not m.comprobar(b != null and _montadas(arbol) >= 3, "el barco nace a 50 km con sus telas"):
		return null
	await UtilesPruebas.estabilizar(arbol, 4.0)
	var local := Vector2(b.global_position.x, b.global_position.z)
	m.menor_que(local.length(), float(o.umbral), "el origen lo ha traído cerca (m del origen local)")
	var g: Vector3 = o.a_global(b.global_position)
	m.casi(g.x, LEJOS, 20.0, "y sigue a 50 km en absoluto (m)")
	return mundo


static func _montadas(arbol: SceneTree) -> int:
	var n := 0
	for t in UtilesPruebas.telas(arbol):
		if not (t.datos_depuracion() as Dictionary).is_empty():
			n += 1
	return n


## Fondeado a 50 km absolutos el casco y la tela tiemblan lo mismo que en el origen.
static func _temblor(m: MarcoPruebas, arbol: SceneTree, o: Node) -> void:
	await UtilesPruebas.estabilizar(arbol, 1.0)
	var b := UtilesPruebas.barco(arbol)
	var r: Dictionary = await UtilesPruebas.temblor(arbol, b, 240)
	# Topes entre lo medido en el origen y lo de 50 km sin recentrar (`tools/temblor_lejos.tscn`):
	# casco 0,20 / 0,20-1,55 mm, tela anclada 0,004 / 2,5-2,8, libre 2,6 / 7,2-7,4, estiramiento
	# medio del peor paño 0,007-0,018 / 0,032-0,037. La anclada es la que más separa: un punto
	# clavado al casco solo tiembla si tiembla la rejilla de coordenadas.
	m.menor_que(r["casco"] * 1000.0, 0.5, "a 50 km el casco no tiembla (mm por paso)")
	m.menor_que(r["anclada"] * 1000.0, 0.5, "ni los puntos anclados de la tela (mm por paso)")
	m.menor_que(r["libre"] * 1000.0, 4.0, "ni los libres (mm por paso)")
	m.menor_que(r["estir"], 0.025, "y el paño no se estira (medio del peor paño)")


## Un nodo cualquiera del mundo conserva su posición ABSOLUTA al recentrar.
static func _nodo_suelto(m: MarcoPruebas, arbol: SceneTree, o: Node, mundo: Node3D) -> void:
	var marca := Marker3D.new()
	mundo.add_child(marca)
	marca.global_position = Vector3(137.0, 2.0, -45.0)
	await arbol.physics_frame
	var antes: Vector3 = o.a_global(marca.global_position)
	o.recentrar(Vector3(-1000.0, 0.0, 500.0))
	await arbol.physics_frame
	var despues: Vector3 = o.a_global(marca.global_position)
	m.menor_que(antes.distance_to(despues), 0.01, "un nodo del mundo no se mueve en absoluto al recentrar (m)")
	marca.queue_free()


## Navegando, recentrar no da tirón ni en el casco ni en la tela, la ola no salta, la malla del mar
## sigue en su rejilla absoluta y la estela sigue a la popa.
static func _recentrar_navegando(m: MarcoPruebas, arbol: SceneTree, o: Node) -> void:
	var b := UtilesPruebas.barco(arbol)
	await UtilesPruebas.navegar(arbol, 8.0)
	var mar := arbol.get_first_node_in_group("mar") as Node3D
	var e := {}
	var accion := func():
		var p := b.global_position - b.global_transform.basis.z * 30.0
		e["abs"] = o.a_global(p)
		e["reloj"] = Oleaje.t
		e["h0"] = Oleaje.altura_en(Vector2(p.x, p.z), Oleaje.t)
		e["barco0"] = o.a_global(b.global_position)
		e["v"] = (b as CharacterBody3D).velocity.length()
		o.recentrar(Vector3(2000.0, 0.0, -1500.0))
		var q: Vector3 = o.a_local(e["abs"])
		e["h1"] = Oleaje.altura_en(Vector2(q.x, q.z), e["reloj"])
		e["barco1"] = o.a_global(b.global_position)
	var r: Dictionary = await UtilesPruebas.temblor(arbol, b, 120, 60, accion)
	m.menor_que(absf(e["h1"] - e["h0"]) * 1000.0, 1.0, "la ola no salta en el mismo punto absoluto (mm)")
	m.menor_que((e["barco1"] as Vector3).distance_to(e["barco0"]), 0.01,
		"el barco sigue en el mismo sitio absoluto (m)")
	m.menor_que(r["casco_pico"] * 1000.0, r["casco_resto"] * 1500.0 + 0.5,
		"el casco no da tirón al recentrar (mm)", "resto de la serie %.3f mm" % (r["casco_resto"] * 1000.0))
	m.menor_que(r["tela_pico"] * 1000.0, r["tela_resto"] * 1500.0 + 2.0,
		"la tela no da tirón al recentrar (mm)", "resto de la serie %.3f mm" % (r["tela_resto"] * 1000.0))
	m.comprobar(int(r["malas"]) <= 1, "ni se rompe", "%d aristas > 25 %%" % r["malas"])
	m.menor_que(r["estir"], 0.025, "ni se estira (medio del peor paño)")
	await arbol.process_frame
	# La malla del agua salta de celda en celda para que sus vértices caigan siempre donde caían
	# los anteriores; tras recentrar tiene que seguir en la MISMA rejilla, contada en absoluto.
	var paso: float = mar.get("_paso_fino")
	var ax: float = (mar.global_position.x + o.x) / paso
	var az: float = (mar.global_position.z + o.z) / paso
	m.menor_que(maxf(absf(ax - roundf(ax)), absf(az - roundf(az))), 0.01,
		"la malla del mar sigue en su rejilla absoluta (celdas)")
	var rastro: Estela = mar.get("_rastro")
	var popa := rastro.popa()
	var vivo := Vector2(rastro.traza[0].x, rastro.traza[0].y)
	# Una muestra de hace 2,4 s, de antes del recentrado (que fue hace 1 s): tiene que estar a lo
	# que el barco navega en ese tiempo, no a los 2,5 km del recentrado.
	var viejo := Vector2(rastro.traza[12].x, rastro.traza[12].y)
	m.menor_que(vivo.distance_to(popa), 1.0, "la estela sigue a la popa (m)")
	m.menor_que(viejo.distance_to(vivo), float(e["v"]) * 2.4 + 5.0,
		"y su rastro se ha movido con el mundo (m)")


## El espejo del oleaje lejos del origen: el shader y GDScript siguen dando la misma ola.
static func _espejo_lejos(m: MarcoPruebas, arbol: SceneTree, o: Node) -> void:
	m.mayor_que(Vector2(o.x, o.z).length(), 40000.0, "el origen está lejos (m)")
	var b := UtilesPruebas.barco(arbol)
	# Alrededor del barco, que tras el recentrado de arriba está a 1,4 km del cero local: ahí es
	# donde se nota cualquier discrepancia de dirección entre los dos, multiplicada por la distancia.
	# Fue lo que cazó que `Oleaje.aplicar()` pasaba las direcciones por REFERENCIA (12-20 cm).
	var puntos := PackedVector2Array()
	var r := RandomNumberGenerator.new()
	r.seed = 20261017
	for i in 48:
		puntos.append(Vector2(b.global_position.x + r.randf_range(-60.0, 60.0),
			b.global_position.z + r.randf_range(-60.0, 60.0)))
	# GDScript en el MISMO instante en que se le aplica el oleaje al shader, no al volver: lejos del
	# cero local la fase corre (el mar rola alrededor del barco) y dos frames ya se notan.
	var reloj: float = Oleaje.t
	var gd := PackedFloat32Array()
	for p in puntos:
		gd.append(Oleaje.desplazamiento(p, reloj).y)
	var shader: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(arbol, puntos, 0)
	var peor := 0.0
	for i in puntos.size():
		peor = maxf(peor, absf(gd[i] - shader[i]))
	m.menor_que(peor, 0.010, "lejos del origen el shader y GDScript dan la misma ola (m)",
		"barco a %.0f m del cero local" % Vector2(b.global_position.x, b.global_position.z).length())


## Una bala en vuelo atraviesa el recentrado sin desviarse.
static func _bala(m: MarcoPruebas, arbol: SceneTree, o: Node) -> void:
	var b := UtilesPruebas.barco(arbol)
	var bala := Bala.new()
	bala.mascara = 0
	bala.vida_max = 60.0
	arbol.current_scene.add_child(bala)
	var desde := b.global_position + Vector3(0, 30, 0)
	var v0 := Vector3(40, 60, 10)
	var desde_abs: Vector3 = o.a_global(desde)
	bala.lanzar(desde, v0, -1000.0)
	for i in 20:
		await arbol.physics_frame
	o.recentrar(Vector3(-2000.0, 0.0, 0.0))
	for i in 20:
		await arbol.physics_frame
	var t: float = bala.get("_t")
	var esperado := Bala.punto(desde_abs, v0, t)
	m.menor_que((o.a_global(bala.global_position) as Vector3).distance_to(esperado), 0.05,
		"una bala en vuelo sigue su parábola al recentrar (m)")
	bala.queue_free()


## La tierra va en absoluto: el gestor decide por la posición absoluta del barco y coloca cada celda
## del relieve restando el origen, también cuando el barco salta con `llevar_a`.
static func _tierra(m: MarcoPruebas, arbol: SceneTree, o: Node, arch: Archipielago) -> void:
	var gestor := arbol.get_first_node_in_group("tierra")
	if not m.comprobar(gestor != null, "hay gestor de tierra"):
		return
	var rel: Relieve = gestor.get("relieve")
	if not m.comprobar(rel != null and rel.listo(), "con su relieve cargado"):
		return
	var nor: Isla = null
	for isla in arch.islas:
		if isla.nombre == "Norman Island":
			nor = isla
	if nor == null:
		return
	var c := rel.celda_de(nor.limites().get_center())
	# A 50 km de la boca del Drake Channel la celda de Norman Island no tiene que estar ni pedida.
	# Con el foco leído en coordenadas LOCALES el gestor la vería junto al barco, porque el origen
	# local cae a su lado.
	await arbol.create_timer(1.0).timeout
	m.comprobar(gestor.estado_celda(c) == "fuera", "lejos de Norman Island su detalle no se pide",
		gestor.estado_celda(c))
	var destino: Vector2 = o.destino_de(PackedStringArray(["--en", "Norman Island"]), arch)
	var b := UtilesPruebas.barco(arbol)
	var local_antes := b.global_position
	o.llevar_a(destino)
	await arbol.physics_frame
	var g: Vector3 = o.a_global(b.global_position)
	m.menor_que(Vector2(g.x, g.z).distance_to(destino), 1.0, "`llevar_a` deja el barco en el destino (m)")
	m.menor_que(b.global_position.distance_to(local_antes), 1.0,
		"sin moverlo en local: lo que se mueve es el mapa (m)")
	var t := 0.0
	while t < 8.0 and gestor.estado_celda(c) != "cargada":
		await arbol.process_frame
		t += arbol.root.get_process_delta_time()
	m.comprobar(gestor.estado_celda(c) == "cargada", "junto a Norman Island su relieve se carga",
		"%s a los %.1f s" % [gestor.estado_celda(c), t])
	# Cada celda y cada silueta, en su sitio ABSOLUTO: su esquina es la de su celda.
	var peor := 0.0
	var n := 0
	for nodo in gestor.get_children():
		var partes := String(nodo.name).split("_")
		if partes.size() != 3:
			continue
		var cc := Vector2i(int(partes[1]), int(partes[2]))
		var ga: Vector3 = o.a_global(nodo.global_position)
		peor = maxf(peor, Vector2(ga.x, ga.z).distance_to(Vector2(cc) * rel.celda))
		n += 1
	m.mayor_que(float(n), 0.0, "hay celdas y siluetas puestas junto a Norman")
	m.menor_que(peor, 0.05, "y todas están en su sitio absoluto (m)", "%d piezas" % n)

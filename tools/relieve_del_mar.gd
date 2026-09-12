extends Node

## Que mar se VE: resolucion de la malla del agua donde esta el barco, y cuanta ola
## puede representar.
##
## Las tres cifras van juntas a proposito. Una funcion de oleaje con 1 m de amplitud no se
## ve si la malla tiene la celda a 500 m, y una malla finisima no se ve si la amplitud es de
## 3 cm: el sintoma "el mar es un plano liso" puede venir de cualquiera de las dos y hay que
## saber de cual.
##
## `puntos_por_ola` = longitud de onda / arista de la malla. Es lo que decide si la ola sale
## redonda o sale un serrucho: por debajo de 4 el mallado no la puede dibujar por mucha
## amplitud que tenga, y por debajo de 2 lo que se ve es aliasing — olas fantasma que viajan
## al reves.
##
## Se mide por anillos y contra la ola que TOCA en cada uno, no contra la mas corta en todas
## partes. La ola corta de este mar tiene 7 cm de amplitud: en primer plano se ve y hay que
## dibujarla, a 200 m no la distingue nadie y exigirla alli seria pedir una malla veinte veces
## mas densa para nada. En el horizonte la que manda es la dominante.
##
##     godot --path . tools/relieve_del_mar.tscn        # el viento a fuerza 1
##     godot --path . tools/relieve_del_mar.tscn -- 1.8  # con el viento que se quiera
##
## Con ventana: `--headless` no compila shaders espaciales y el agua ni se monta.

## Anillos donde se mide, en metros, y contra que ola se juzga cada uno.
const ANILLOS := [
	{"hasta": 25.0, "ola": "corta", "min": 8.0},    # primer plano: se ve hasta el rizo
	{"hasta": 60.0, "ola": "corta", "min": 4.0},    # media distancia
	{"hasta": 200.0, "ola": "larga", "min": 8.0},   # horizonte: solo la dominante
]
const RADIO := 50.0        # disco donde se cuentan los vertices
const SEGUNDOS := 12.0     # ventana para el pico a pico de la altura bajo el barco


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit(1))
	var esc := load("res://scenes/world/main_world.tscn") as PackedScene
	add_child(esc.instantiate())
	# 6 s y no 4: el mar monta un disco basto al arrancar y pone el fino después (ver `mar.gd`),
	# y midiendo pronto se mide el provisional.
	await get_tree().create_timer(6.0).timeout

	# Estado de la mar con el que medir: por defecto el viento a fuerza 1.
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	for a in OS.get_cmdline_user_args():
		Viento.fuerza_base = String(a).to_float()
	# Dos vueltas: `Viento` recalcula su fuerza en su propio _process, y asentar antes de que lo
	# haya hecho asienta la mar sobre el viento anterior.
	await get_tree().process_frame
	await get_tree().process_frame
	Oleaje.asentar()

	var barco := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var agua := _agua()
	if agua == null:
		print("NO HAY AGUA en la escena")
		get_tree().quit(1)
		return
	var centro := Vector2.ZERO
	if barco != null:
		centro = Vector2(barco.global_position.x, barco.global_position.z)

	# --- Mallado: cuantos vertices caen donde se mira, y de que tamano es la celda.
	var arr: Array = agua.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var g := agua.global_transform
	var dentro := 0
	for v in vs:
		if Vector2((g * v).x, (g * v).z).distance_to(centro) <= RADIO:
			dentro += 1
	# Arista tipica por anillo: solo las de los triangulos cuyo centro cae dentro. Recorrer
	# pares de vertices seria O(n^2) y con una malla de verdad no termina.
	var por_anillo: Array[Array] = []
	for _a in ANILLOS:
		por_anillo.append([] as Array[float])
	var tris := idx.size() / 3
	for t in tris:
		var a := g * vs[idx[t * 3]]
		var b := g * vs[idx[t * 3 + 1]]
		var c := g * vs[idx[t * 3 + 2]]
		var m := (a + b + c) / 3.0
		var dist := Vector2(m.x, m.z).distance_to(centro)
		for k in ANILLOS.size():
			if dist <= float(ANILLOS[k]["hasta"]):
				por_anillo[k].append(a.distance_to(b))
				por_anillo[k].append(b.distance_to(c))
				por_anillo[k].append(c.distance_to(a))
				break

	# --- Amplitud: lo que la funcion de oleaje mueve la lamina bajo el barco.
	var l_corta: float = Oleaje.longitud_mas_corta()
	var l_larga := 0.0
	for x in Oleaje.LARGOS:
		l_larga = maxf(l_larga, x)
	# Pico a pico sobre una REJILLA, no en un punto a lo largo del tiempo: con los grupos de olas
	# un punto suelto puede pasarse los doce segundos en el hueco entre dos grupos y decir que la
	# mar está en calma. 300 m cubren varias longitudes de la ola larga y varios grupos.
	var alto_e := -INF
	var bajo_e := INF
	for i in 60:
		for j in 60:
			var q := centro + Vector2(float(i) * 5.0 - 150.0, float(j) * 5.0 - 150.0)
			var y: float = Oleaje.desplazamiento(q).y
			alto_e = maxf(alto_e, y)
			bajo_e = minf(bajo_e, y)

	var alto := 0.0
	var bajo := 0.0
	# Vaiven HORIZONTAL: en Gerstner el agua no solo sube y baja, se corre hacia la cresta. Es
	# lo que le da la cresta afilada, pero pasado de rosca se ve como el mar deslizandose de un
	# lado a otro y, con el barco quieto encima, como si el barco corriera adelante y atras.
	var der := 0.0
	var izq := 0.0
	var t := 0.0
	var primera := true
	while t < SEGUNDOS:
		await get_tree().process_frame
		t += get_process_delta_time()
		var h: float = Oleaje.altura_en(centro)
		var x: float = Oleaje.desplazamiento(centro).x
		if primera:
			alto = h; bajo = h; der = x; izq = x; primera = false
		alto = maxf(alto, h)
		bajo = minf(bajo, h)
		der = maxf(der, x)
		izq = minf(izq, x)

	print("
─── relieve del mar ───")
	print("barco en            : (%.1f, %.1f)" % [centro.x, centro.y])
	print("malla del agua      : %d vertices, %d triangulos, %d vertices dentro de %.0f m"
		% [vs.size(), tris, dentro, RADIO])
	print("mar                 : %.3f m pico a pico, olas de %.0f a %.0f m"
		% [Oleaje.altura, l_corta, l_larga])
	print("altura de la lamina : %.3f m pico a pico en 300 m de mar" % (alto_e - bajo_e))
	print("                      %.3f m pico a pico bajo el barco en %.0f s"
		% [alto - bajo, SEGUNDOS])
	print("vaiven horizontal   : %.3f m pico a pico  (no deberia pasar de la altura)"
		% (der - izq))
	# --- Que cuesta el mar. Con el tope de fps QUITADO: con vsync la escena se sienta en 120 y
	# el coste no se ve.
	var antes := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var fps := {}
	for visible in [true, false]:
		agua.visible = visible
		for i in 30:
			await get_tree().process_frame
		var n := 0
		var s := 0.0
		while s < 4.0:
			await get_tree().process_frame
			s += get_process_delta_time()
			n += 1
		fps[visible] = n / s
	agua.visible = true
	Engine.max_fps = antes
	print("fps                 : %.0f con el mar, %.0f sin el (cuesta %.2f ms por frame)"
		% [fps[true], fps[false], 1000.0 * (1.0 / fps[true] - 1.0 / fps[false])])

	print("
%-14s %10s %10s %12s %10s" % ["anillo", "celda m", "ola m", "puntos/ola", "minimo"])
	for k in ANILLOS.size():
		var l: Array[float] = por_anillo[k]
		l.sort()
		var celda: float = l[l.size() / 2] if not l.is_empty() else INF
		var ola: float = l_corta if ANILLOS[k]["ola"] == "corta" else l_larga
		var por_ola: float = ola / maxf(celda, 0.0001)
		print("%-14s %10.2f %10.1f %12.2f %10.1f  %s"
			% ["hasta %.0f m" % ANILLOS[k]["hasta"], celda, ola, por_ola,
				ANILLOS[k]["min"], "ok" if por_ola >= float(ANILLOS[k]["min"]) else "CORTO"])
	get_tree().quit(0)


func _agua() -> MeshInstance3D:
	var a := get_tree().get_first_node_in_group("mar") as MeshInstance3D
	if a == null:
		a = find_child("Water", true, false) as MeshInstance3D
	return a

extends Node
## Hornea el archipiélago a disco. No mide nada; es el paso de construcción de los datos que lee el
## juego.
##
##     godot --path . tools/hornear_islas.tscn
##
## Entrada: `fuentes/derivados/costas_caribe.json`, las costas del Caribe a escala de juego que saca
## `blender_src/costas_caribe.py` de OpenStreetMap (© OpenStreetMap contributors, ODbL).
## Salidas:
##
## - `assets/islas/archipielago.res`: una `Isla` por polígono, con su contorno, su posición y su
##   nombre. Binario, porque en texto son dos megas que habría que interpretar al arrancar.
## - `assets/mapa/costas_carta.res`: toda la tierra de la carta en UNA malla —rellenos triangulados
##   aquí y costas como líneas de un píxel—, para que abrir la carta no tenga que triangular dos mil
##   polígonos en un frame.
##
## El relieve no sale de aquí: va por celdas, `blender_src/relieve_caribe.py` → `Relieve`.

const COSTAS := "res://fuentes/derivados/costas_caribe.json"
const CARPETA := "res://assets/islas"
const CARTA := "res://assets/mapa/costas_carta.res"
const COLOR_TIERRA := Color(0.62, 0.5, 0.32, 0.55)
const COLOR_TINTA := Color(0.24, 0.16, 0.09)


func _ready() -> void:
	# Tope: si algo falla a medias, la ventana no se queda abierta esperando a nadie.
	get_tree().create_timer(300.0).timeout.connect(get_tree().quit.bind(1))
	await get_tree().process_frame
	# `fuentes/` lleva .gdignore: Godot no lo importa, pero se puede leer por su ruta de disco.
	var texto := FileAccess.get_file_as_string(ProjectSettings.globalize_path(COSTAS))
	var datos: Dictionary = JSON.parse_string(texto)
	var arch := Archipielago.new()
	arch.origen_real = Vector2(datos["origen"][0], datos["origen"][1])
	arch.escala = float(datos["escala"])
	arch.mundo = Rect2(datos["mundo"][0], datos["mundo"][1], datos["mundo"][2], datos["mundo"][3])
	arch.fuente = datos["fuente"]
	_material()

	var t0 := Time.get_ticks_msec()
	for d in datos["islas"]:
		var pts := PackedVector2Array()
		for q in d["puntos"]:
			pts.append(Vector2(q[0], q[1]))
		var r := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			r = r.expand(q)
		var centro := r.get_center()
		var local := PackedVector2Array()
		for q in pts:
			local.append(q - centro)
		var isla := Isla.new()
		isla.nombre = d["nombre"]
		isla.posicion = centro
		isla.contorno = local
		arch.islas.append(isla)
	print("%d islas en %d ms" % [arch.islas.size(), Time.get_ticks_msec() - t0])
	ResourceSaver.save(arch, CARPETA + "/archipielago.res")
	_costas_carta(arch)
	get_tree().quit()


## Toda la tierra en una malla 2D, en metros de mundo: la carta la escala con su vista.
func _costas_carta(arch: Archipielago) -> void:
	var tv := PackedVector2Array()
	var tc := PackedColorArray()
	var lv := PackedVector2Array()
	var lc := PackedColorArray()
	var fallos := []
	for isla in arch.islas:
		var mundo := PackedVector2Array()
		for c in isla.contorno:
			mundo.append(c + isla.posicion)
		# Simplificar y recortar deja a veces un anillo que se cruza consigo mismo, y entonces no se
		# triangula: pasó en 16 de 2.076, la tierra firme entre ellos. Clipper (`offset_polygon`) lo
		# deshace en piezas limpias, y se triangula cada una.
		var piezas: Array = [mundo]
		if Geometry2D.triangulate_polygon(mundo).is_empty():
			piezas = Geometry2D.offset_polygon(mundo, 0.01)
		var rellena := false
		for pieza: PackedVector2Array in piezas:
			if Geometry2D.is_polygon_clockwise(pieza) and piezas.size() > 1:
				continue    # un hueco que devuelve Clipper
			var tri := Geometry2D.triangulate_polygon(pieza)
			for k in tri:
				tv.append(pieza[k])
				tc.append(COLOR_TIERRA)
			rellena = rellena or not tri.is_empty()
		if not rellena:
			fallos.append("%s (%d pts)" % [isla.nombre if isla.nombre != "" else "?", mundo.size()])
		for i in mundo.size():
			lv.append(mundo[i])
			lv.append(mundo[(i + 1) % mundo.size()])
			lc.append(COLOR_TINTA)
			lc.append(COLOR_TINTA)
	var m := ArrayMesh.new()
	for par in [[tv, tc, Mesh.PRIMITIVE_TRIANGLES], [lv, lc, Mesh.PRIMITIVE_LINES]]:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = par[0]
		arr[Mesh.ARRAY_COLOR] = par[1]
		m.add_surface_from_arrays(par[2], arr)
	ResourceSaver.save(m, CARTA)
	print("carta: %d triángulos de tierra, %d tramos de costa; %d sin rellenar %s"
		% [tv.size() / 3, lv.size() / 2, fallos.size(), str(fallos.slice(0, 5))])


## El material de tierra, compartido por todas las islas, con sus tres baldosas.
##
## Las baldosas son ruido SIN COSTURAS generado por Godot (`NoiseTexture2D.seamless`) mientras no
## haya texturas de verdad: mismo papel de marcador que las primitivas del resto del proyecto, y
## cambiarlas por fotos tileables es sustituir tres recursos sin tocar el shader.
func _material() -> ShaderMaterial:
	var ruta := CARPETA + "/tierra.tres"
	if ResourceLoader.exists(ruta):
		return load(ruta) as ShaderMaterial
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARPETA + "/texturas"))
	var t := {
		"arena": _baldosa(FastNoiseLite.TYPE_VALUE, 0.09, 3,
			[Color(0.80, 0.73, 0.56), Color(0.90, 0.84, 0.68)]),
		"hierba": _baldosa(FastNoiseLite.TYPE_SIMPLEX, 0.035, 5,
			[Color(0.16, 0.26, 0.09), Color(0.30, 0.42, 0.14), Color(0.42, 0.45, 0.20)]),
		"roca": _baldosa(FastNoiseLite.TYPE_CELLULAR, 0.03, 4,
			[Color(0.30, 0.28, 0.25), Color(0.47, 0.44, 0.39), Color(0.58, 0.55, 0.50)]),
	}
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/tierra.gdshader")
	for k in t:
		var r := "%s/texturas/%s.tres" % [CARPETA, k]
		ResourceSaver.save(t[k], r)
		m.set_shader_parameter(k, load(r))
	ResourceSaver.save(m, ruta)
	return load(ruta) as ShaderMaterial


func _baldosa(tipo: int, frecuencia: float, octavas: int, colores: Array) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = tipo
	n.frequency = frecuencia
	n.fractal_octaves = octavas
	var g := Gradient.new()
	g.colors = PackedColorArray(colores)
	var off := PackedFloat32Array()
	for i in colores.size():
		off.append(float(i) / float(colores.size() - 1))
	g.offsets = off
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = n
	tex.color_ramp = g
	return tex

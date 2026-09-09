extends Node

## Cuenta cuantos puntos de la vela quedan DENTRO de las capsulas de las perchas, separando
## los ANCLADOS de los libres.
##
## Un punto anclado dentro de la capsula es un conflicto irresoluble: el solver lo empuja
## fuera y el ancla lo devuelve a su sitio cada paso. Eso da un golpe repetido, y aparece y
## desaparece segun trima la percha, que es justo lo que se ve.

const SEGUNDOS := 30.0

var _barco: Node3D
var _telas: Array = []
var _perchas: Array = []
var _t := 0.0
var _hist: Array = []
var _culpables: Dictionary = {}   ## "tela -> capsula" : penetracion maxima de un ANCLA


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	Viento.direccion_base = Vector3(0, 0, 1)
	_barco.set("anclado", false)
	await get_tree().create_timer(2.5).timeout
	for h in _barco.get_children():
		if h.has_method("datos_depuracion"):
			var d: Dictionary = h.datos_depuracion()
			if d.has("cuerpo"):
				# La mascara del pano decide si el solape es un CONFLICTO o solo geometria: una
				# vela con `capa_perchas = 0` no choca con las capsulas y puede atravesarlas sin
				# que el solver pelee con nadie. Sin esta distincion la herramienta acusa a la
				# mayor, que lleva 0 desde que sus bordes van cosidos a los palos.
				var cu: SoftBody3D = d["cuerpo"]
				_telas.append({"nombre": str(h.get("nombre_malla")), "cuerpo": cu,
							   "choca": cu.collision_mask != 0,
							   "fijo": d["fijo"] as PackedByteArray})
	# TODAS las capsulas de cada percha, no solo la primera: desde que los palos se describen
	# por tramos, `get_child(0)` es el tramo del PIE y con el la bandera —que va en la perilla—
	# salia siempre limpia. Es el error que hizo descartar los colisionadores como causa.
	for c in _barco.find_children("Percha_*", "StaticBody3D", true, false):
		for hijo in c.get_children():
			var cs := hijo as CollisionShape3D
			if cs == null:
				continue
			var cap := cs.shape as CapsuleShape3D
			if cap == null:
				continue
			_perchas.append({"nodo": c, "forma": cs, "r": cap.radius, "h": cap.height,
							 "nombre": "%s/%s" % [c.name, cs.name]})
	print("velas: %s   perchas: %s" % [
		_telas.map(func(t): return "%s%s" % [t["nombre"], "" if t["choca"] else "(sin colision)"]),
		_perchas.map(func(p): return p["nombre"])])


func _dentro(p: Vector3, per: Dictionary) -> float:
	## Profundidad de penetracion de `p` en la capsula (0 si esta fuera).
	var t: Transform3D = (per["nodo"] as Node3D).global_transform * (per["forma"] as Node3D).transform
	var q := t.affine_inverse() * p
	var media := maxf(per["h"] * 0.5 - per["r"], 0.0)
	var y: float = clampf(q.y, -media, media)
	var d := q.distance_to(Vector3(0.0, y, 0.0))
	return maxf(per["r"] - d, 0.0)


func _physics_process(delta: float) -> void:
	if _telas.is_empty():
		return
	_t += delta
	var fila := {"t": _t}
	for tela in _telas:
		var cuerpo: SoftBody3D = tela["cuerpo"]
		var fijo: PackedByteArray = tela["fijo"]
		var n_anc := 0
		var n_lib := 0
		var peor := 0.0
		for i in fijo.size():
			var p: Vector3 = cuerpo.get_point_transform(i)
			var prof := 0.0
			for per in _perchas:
				var d := _dentro(p, per)
				if d > prof:
					prof = d
				if d > 0.0005 and fijo[i] == 1 and tela["choca"]:
					var clave: String = "%s -> %s" % [tela["nombre"], per["nombre"]]
					_culpables[clave] = maxf(float(_culpables.get(clave, 0.0)), d)
			if prof > 0.0005:
				if fijo[i] == 1:
					n_anc += 1
				else:
					n_lib += 1
				peor = maxf(peor, prof)
		fila[tela["nombre"]] = [n_anc, n_lib, peor]
	_hist.append(fila)
	if _t >= SEGUNDOS:
		_informe()
		get_tree().quit()


func _informe() -> void:
	var n := _hist.size()
	var nombres: Array = _telas.map(func(t): return t["nombre"])
	print("\nt(s)  " + "  ".join(nombres.map(func(x): return "%s: anc/libres/prof_mm" % x)))
	for k in range(0, n, maxi(1, n / 40)):
		var f: Dictionary = _hist[k]
		var s := "%5.2f " % f["t"]
		for nom in nombres:
			var v: Array = f[nom]
			s += "  %3d/%3d/%6.2f" % [v[0], v[1], v[2] * 1000.0]
		print(s)
	print("\nresumen por vela:")
	for nom in nombres:
		var max_anc := 0
		var frames_con_anc := 0
		var max_prof := 0.0
		for f in _hist:
			var v: Array = f[nom]
			max_anc = maxi(max_anc, v[0])
			if v[0] > 0:
				frames_con_anc += 1
			max_prof = maxf(max_prof, v[2])
		print("  %-12s hasta %d ANCLADOS dentro de una percha, en el %.0f %% de los frames; "
			% [nom, max_anc, 100.0 * frames_con_anc / n]
			+ "penetracion maxima %.2f mm" % (max_prof * 1000.0))
	print("
que capsula atrapa a que anclas:")
	if _culpables.is_empty():
		print("  ninguna")
	for clave in _culpables:
		print("  %-40s %6.2f mm" % [clave, float(_culpables[clave]) * 1000.0])

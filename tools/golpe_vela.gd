extends Node

## El "latido" de la mayor visto como SERIE TEMPORAL, no como espectro, y barriendo el flameo
## por desventa.
##
## Un espectro dice a que ritmo pasa algo; no dice si es un vaiven suave o un golpe. Un golpe
## repetido es una serie con picos AISLADOS sobre un fondo tranquilo, asi que la cifra que
## importa es el pico partido por la mediana: 1 seria un movimiento uniforme y 4 es un latido.
##
## OJO CON EL SIGNO DEL VIENTO: `Viento.direccion` es HACIA DONDE sopla y la proa mira a -Z, asi
## que (0,0,1) deja el barco EN FACHADA. Es a proposito: en fachada `factor_viento()` da 0 y el
## latido sale con toda su fuerza, que es donde hay que medir el remedio. Con (0,0,-1) el barco
## corre de popa y el pico baja solo a 2,2.

const SEGUNDOS := 40.0
const VIENTO := Vector3(0, 0, 1)   ## en fachada: la vela desventada del todo

var _casos: Array = [0.0, 0.3, 0.5, 0.8]


func _ready() -> void:
	print("%-10s %9s %9s %9s %9s   %s"
		% ["desventa", "mediana", "p99", "maximo", "pico/med", "intervalos entre picos (s)"])
	for caso in _casos:
		await _probar(caso)
	get_tree().quit()


func _probar(fpd: float) -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var barco := esc.instantiate() as Node3D
	var mayor: Node = null
	for h in barco.get_children():
		if h.has_method("datos_depuracion") and str(h.get("nombre_malla")) == "vela_mayor":
			mayor = h
	mayor.set("flameo_por_desventa", fpd)
	add_child(barco)
	Viento.direccion_base = VIENTO
	barco.set("anclado", false)
	await get_tree().create_timer(4.0).timeout
	var dd: Dictionary = mayor.datos_depuracion()
	var cuerpo: SoftBody3D = dd["cuerpo"]
	var _n_puntos: int = (dd["fijo"] as PackedByteArray).size()
	var aristas: PackedInt32Array = dd["aristas"]
	var largo0: PackedFloat32Array = dd["largo0"]
	var est_suma := 0.0
	var est_malas := 0
	var est_n := 0

	var serie: Array = []
	var prev := PackedVector3Array()
	var t := 0.0
	while t < SEGUNDOS:
		await get_tree().physics_frame
		var delta := 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		t += delta
		var inv := barco.global_transform.affine_inverse()
		# Muestreo derivado del tamaño REAL del paño, nunca con paso fijo: un `i * 5` sobre 200
		# muestras llegaba al índice 995, que valía con los 1.217 puntos de la mayor y se salió
		# al bajarla a 613. `get_point_transform` fuera de rango no aborta: devuelve cero y
		# escribe un error por muestra y por frame, y la prueba pasó de 75 s a más de 280.
		var n_pts := _n_puntos
		var muestras: int = mini(200, n_pts)
		var paso: int = maxi(1, n_pts / maxi(muestras, 1))
		var ps := PackedVector3Array()
		ps.resize(muestras)
		for i in muestras:
			ps[i] = inv * cuerpo.get_point_transform(mini(i * paso, n_pts - 1))
		var mov := 0.0
		if prev.size() == ps.size():
			for i in ps.size():
				mov = maxf(mov, ps[i].distance_to(prev[i]))
		prev = ps
		serie.append([t, mov / delta])
		# El estiramiento tambien, cada medio segundo: un remedio que rompe la lona no vale.
		if int(t * 2.0) > est_n:
			est_n = int(t * 2.0)
			for e in largo0.size():
				var l0: float = largo0[e]
				if l0 < 1e-6:
					continue
				var l := cuerpo.get_point_transform(aristas[e * 2]).distance_to(
					cuerpo.get_point_transform(aristas[e * 2 + 1]))
				var r := (l - l0) / l0
				est_suma += absf(r)
				if r > 0.25:
					est_malas += 1

	var movs := []
	for f in serie:
		movs.append(f[1])
	var orden: Array = movs.duplicate()
	orden.sort()
	var mediana: float = orden[orden.size() / 2]
	var p99: float = orden[int(orden.size() * 0.99)]
	var maxi_: float = orden[orden.size() - 1]
	# Intervalos entre picos aislados: si son regulares, es un latido.
	var idx := []
	for i in serie.size():
		idx.append(i)
	idx.sort_custom(func(a, b): return serie[a][1] > serie[b][1])
	var picos: Array[float] = []
	for i in idx:
		var repe := false
		for v in picos:
			if absf(serie[i][0] - v) < 1.5:
				repe = true
		if not repe:
			picos.append(serie[i][0])
		if picos.size() >= 7:
			break
	picos.sort()
	var huecos: Array[String] = []
	for k in range(1, picos.size()):
		huecos.append("%.1f" % (picos[k] - picos[k - 1]))
	print("%-10.2f %9.4f %9.4f %9.4f %9.2f  estira %.3f/%d picos %s"
		% [fpd, mediana, p99, maxi_, maxi_ / maxf(mediana, 1e-6),
		   est_suma / maxf(float(largo0.size() * maxi(est_n, 1)), 1.0),
		   est_malas / maxi(est_n, 1), ", ".join(huecos)])
	barco.queue_free()
	await get_tree().create_timer(0.5).timeout

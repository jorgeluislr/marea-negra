extends Node
## Sigue el estiramiento de las telas DESDE EL PRIMER FRAME, con el viento fijo y el barco
## anclado, para ver en que instante aparecen los vertices estirados de la primera balandra.
## Vuelca tambien el delta del frame y el angulo de trimado, que son los dos sospechosos.
@export var carpeta := ""

func _ready() -> void: _correr()

func _fila(t: float, dt: float) -> void:
	var bs := get_tree().get_nodes_in_group("barco_activo")
	if bs.is_empty():
		return
	var linea := "t=%5.2f dt=%.3f " % [t, dt]
	for v in bs[0].get_children():
		if not v.has_method("datos_depuracion"):
			continue
		var d: Dictionary = v.datos_depuracion()
		if d.is_empty():
			linea += "| %s: sin montar " % v.name.substr(0, 10)
			continue
		var cuerpo: SoftBody3D = d["cuerpo"]
		var ar: PackedInt32Array = d["aristas"]
		var l0: PackedFloat32Array = d["largo0"]
		var suma := 0.0; var peor := 0.0; var malos := 0
		for e in l0.size():
			var f: float = absf(cuerpo.get_point_transform(ar[e * 2]).distance_to(
				cuerpo.get_point_transform(ar[e * 2 + 1])) - l0[e]) / maxf(l0[e], 0.0001)
			suma += f; peor = maxf(peor, f)
			if f > 0.25:
				malos += 1
		var apa: Variant = v.get("aparejo")
		var ang: float = rad_to_deg(apa.get("_ang_trim")) if apa != null else 0.0
		linea += "| %s med %5.2f%% peor %5.0f%% >25%%:%3d trim %5.1f " % [
			v.name.substr(9, 6), 100.0 * suma / maxf(l0.size(), 1), 100.0 * peor, malos, ang]
	print(linea)

func _correr() -> void:
	var t := 0.0
	var prox := 0.0
	while t < 12.0:
		Viento.direccion = Vector3(1, 0, 0)
		Viento.fuerza = 1.0
		var bs := get_tree().get_nodes_in_group("barco_activo")
		if not bs.is_empty():
			bs[0].set("anclado", true)
		var dt: float = get_process_delta_time()
		t += dt
		# Frame a frame durante el primer segundo: es donde nace el SoftBody y donde el reloj
		# del juego aun va a tirones por la carga del modelo.
		if t < 1.2 or t >= prox:
			_fila(t, dt)
			prox = t + 0.4
		await get_tree().process_frame
	get_tree().quit()

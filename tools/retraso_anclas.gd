extends Node

## Cuánto se separa cada punto ANCLADO de su nodo de anclaje —la línea magenta de la vista 1 del
## visor— y con qué reloj escala ese desfase.
##
## Un punto anclado debería estar CLAVADO a su nodo: el nodo es hijo del `Skeleton3D`, así que
## viaja rígido con el barco. Si el punto se queda atrás, la columna de anclajes se ve estirada
## hacia popa con el barco en marcha, que es lo que se aprecia en el visor.
##
## El experimento decisivo no es la cifra, es de QUÉ depende: si el desfase dividido por la
## velocidad del barco da un paso de FÍSICA, el problema está en cómo el solver persigue el
## pin; si da un frame de RENDER, está en que las anclas se recolocan en `_process`. Por eso se
## barren las dos frecuencias por separado.
##
## Con ventana, no `--headless`: sin ella `SoftBody3D` no se simula y todo mide cero.

const FISICA := [60, 120, 240]
const FPS := [30, 60, 0]          ## 0 = sin tope

var _barco: Node3D


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	_barco.set("anclado", true)
	await get_tree().create_timer(6.0).timeout

	var telas := []
	for h in _barco.get_children():
		if h.has_method("datos_depuracion") and not h.datos_depuracion().is_empty():
			telas.append(h)
	if telas.is_empty():
		print("no hay telas físicas montadas")
		get_tree().quit(1)
		return

	print("\n=== FONDEADO (el desfase tiene que ser ~0: el barco no se mueve) ===")
	await _medir(telas, "fondeado")

	_barco.set("anclado", false)
	await get_tree().create_timer(6.0).timeout

	print("\n=== NAVEGANDO, barriendo la frecuencia de FÍSICA (fps sin tope) ===")
	Engine.max_fps = 0
	for hz in FISICA:
		Engine.physics_ticks_per_second = hz
		await get_tree().create_timer(2.0).timeout
		await _medir(telas, "fisica %d Hz" % hz)

	print("\n=== NAVEGANDO, barriendo los FPS (física a 120 Hz) ===")
	Engine.physics_ticks_per_second = 120
	for f in FPS:
		Engine.max_fps = f
		await get_tree().create_timer(2.0).timeout
		await _medir(telas, "fps %s" % ("sin tope" if f == 0 else str(f)))

	Engine.max_fps = 0
	get_tree().quit()


## Desfase medio y peor de los puntos anclados respecto a su nodo, en el reloj de la FÍSICA.
##
## Leído desde `_process` los dos vienen de instantes distintos —las anclas se mueven ahí mismo
## y los puntos en el paso de física— y la cifra alterna entre dos valores.
func _medir(telas: Array, etiqueta: String) -> void:
	var suma := {}
	var peor := {}
	var n := 0
	var v := 0.0
	var dt_fis := 0.0
	var dt_ren := 0.0
	for _i in 90:
		await get_tree().physics_frame
		n += 1
		v += (_barco as CharacterBody3D).velocity.length()
		dt_fis += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		dt_ren += get_tree().root.get_process_delta_time()
		for t in telas:
			var d: Dictionary = t.datos_depuracion()
			var cuerpo: SoftBody3D = d["cuerpo"]
			var anclas: Array[Node3D] = d["anclas"]
			var fijo: PackedByteArray = d["fijo"]
			var nom := str(t.get("nombre_malla"))
			var s := 0.0
			var p := 0.0
			var na := 0
			for k in fijo.size():
				if fijo[k] == 0:
					continue
				var e := cuerpo.get_point_transform(k).distance_to(anclas[k].global_position)
				s += e
				p = maxf(p, e)
				na += 1
			if na > 0:
				suma[nom] = suma.get(nom, 0.0) + s / float(na)
				peor[nom] = maxf(peor.get(nom, 0.0), p)
	v /= float(n)
	dt_fis /= float(n)
	dt_ren /= float(n)
	print("-- %s   barco %.2f m/s   paso fisica %.1f ms (%.0f mm de barco)   frame %.1f ms (%.0f mm)"
		% [etiqueta, v, dt_fis * 1000.0, v * dt_fis * 1000.0, dt_ren * 1000.0, v * dt_ren * 1000.0])
	for nom in suma:
		var med: float = suma[nom] / float(n)
		# El desfase dividido por la velocidad es un TIEMPO: comparado con el paso de física y
		# con el frame de render dice cuál de los dos relojes lo produce.
		var ms := (med / v * 1000.0) if v > 0.1 else 0.0
		print("   %-12s medio %6.1f mm   peor %6.1f mm   = %5.1f ms de barco" % [nom, med * 1000.0, peor[nom] * 1000.0, ms])

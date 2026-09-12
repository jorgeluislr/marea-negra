extends Node

## Cuánto se REPITE el mar, en un número.
##
## "Se ve muy regular" es una impresión, y para cambiarla hace falta poder decir si ha mejorado.
## Lo que la produce es que el campo de altura se parece a sí mismo desplazado: si al correr el
## mar 30 m sobre sí mismo vuelve a encajar, el ojo lo caza enseguida aunque no sepa decir por
## qué. Eso es la AUTOCORRELACIÓN, y su pico fuera del origen es la cifra.
##
##     1,00 = idéntico a sí mismo desplazado (un solo tren: crestas rectas infinitas)
##     0,50 = se reconoce el patrón
##     0,20 = cuesta verlo
##
## Se ignoran los desplazamientos pequeños (un campo suave siempre se parece a sí mismo un
## metro más allá, y eso no es un patrón, es que es continuo).
##
##     godot --path . tools/patron_del_mar.tscn
##
## Sirve con ventana o sin ella: solo se pregunta a `Oleaje`, no se dibuja nada.

const LADO := 256          # muestras por lado de la tabla de alturas
const METROS := 400.0      # cuánto mar se mira
const DESPL := 64          # desplazamientos por lado que se prueban
const MINIMO_M := 12.0     # por debajo de esto no es patrón, es continuidad


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(1))
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	Oleaje.asentar()

	# Tabla de alturas en un instante fijo: el patrón es espacial, el tiempo no hace falta.
	var paso := METROS / float(LADO)
	var h := PackedFloat32Array()
	h.resize(LADO * LADO)
	var reloj: float = Oleaje.t
	for j in LADO:
		for i in LADO:
			h[j * LADO + i] = Oleaje.desplazamiento(
				Vector2(float(i) * paso, float(j) * paso), reloj).y
	var media := 0.0
	for v in h:
		media += v
	media /= float(h.size())
	var var0 := 0.0
	for v in h:
		var0 += (v - media) * (v - media)
	var0 /= float(h.size())

	# Autocorrelación por desplazamientos enteros de la tabla, muestreando el solape.
	var peor := 0.0
	var peor_d := Vector2.ZERO
	var suma := 0.0
	var n := 0
	var min_celdas := int(MINIMO_M / paso)
	for dj in range(-DESPL, DESPL + 1):
		for di in range(-DESPL, DESPL + 1):
			if di * di + dj * dj < min_celdas * min_celdas:
				continue
			var c := 0.0
			var m := 0
			# Una de cada tres filas y columnas: con 65.536 puntos por desplazamiento esto
			# tardaría minutos y el resultado no cambia en la tercera cifra.
			var j := maxi(0, -dj)
			while j < LADO - maxi(0, dj):
				var i := maxi(0, -di)
				while i < LADO - maxi(0, di):
					c += (h[j * LADO + i] - media) * (h[(j + dj) * LADO + i + di] - media)
					m += 1
					i += 3
				j += 3
			if m == 0:
				continue
			var r: float = (c / float(m)) / maxf(var0, 1e-9)
			suma += absf(r)
			n += 1
			if absf(r) > peor:
				peor = absf(r)
				peor_d = Vector2(float(di) * paso, float(dj) * paso)

	print("\n─── cuánto se repite el mar ───")
	print("trenes              : %d, de %s m" % [Oleaje.LARGOS.size(), Oleaje.LARGOS])
	print("mar                 : %.2f m pico a pico" % Oleaje.altura)
	print("autocorrelación pico: %.3f  (a %.0f, %.0f m)  ← cuanto más baja, menos patrón"
		% [peor, peor_d.x, peor_d.y])
	print("autocorrelación media: %.3f" % (suma / maxf(n, 1)))
	get_tree().quit(0)

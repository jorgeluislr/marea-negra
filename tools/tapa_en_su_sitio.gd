extends Node

## Si la tapa de sentina se queda donde le toca dentro del casco, o se sale.
##
## La tapa es geometría CON LA FORMA del casco a la altura del agua, así que mientras viaje con
## el barco no puede asomar por ningún lado: encaja por construcción. Lo que la saca es que se
## mueva respecto a él. Eso es exactamente lo que se mide aquí: dónde cae cada punto de su borde
## **en ejes del barco**, y cuánto se aparta del sitio para el que se cortó.
##
## Un solo número, en metros, y su lectura es directa: 0 = la tapa va con el casco; 0,67 = sus
## extremos suben y bajan dos tercios de metro dentro de la bodega, que es asomar por la cubierta
## por un lado y por la regala por el otro.
##
##     godot --path . tools/tapa_en_su_sitio.tscn          # mar de siempre
##     godot --path . tools/tapa_en_su_sitio.tscn -- 1.9   # temporal
##
## Con ventana y navegando: parada y en calma la tapa está quieta y no mide nada.

const SEGUNDOS := 25.0


func _ready() -> void:
	get_tree().create_timer(200.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	for a in OS.get_cmdline_user_args():
		Viento.fuerza_base = maxf(String(a).to_float(), 0.05)
	await get_tree().create_timer(6.0).timeout
	Oleaje.asentar()

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var tapa := b.get_node_or_null(^"TapaSentina") as MeshInstance3D if b != null else null
	if tapa == null:
		print("no hay tapa")
		get_tree().quit(1)
		return
	b.set("anclado", false)
	# El borde de la tapa: el vértice 0 es el centro y el faldón va detrás, así que el contorno
	# son los que van del 1 al primero del faldón. Se leen de la malla para no repetir aquí cómo
	# se construye.
	var vs: PackedVector3Array = tapa.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n: int = (vs.size() - 1) / 2
	print("\n─── la tapa en su sitio ───")
	print("viento %.2f -> mar de %.2f m pico a pico" % [Viento.fuerza, Oleaje.altura])
	print("tapa de %d puntos de contorno" % n)

	# Dos cosas distintas, y las dos sacan la tapa del casco:
	#  - INCLINACIÓN relativa: cuánto se separan los puntos del borde del plano del centro, medido
	#    en ejes del barco. Con la tapa solidaria vale 0 por construcción.
	#  - DERIVA vertical: cuánto sube o baja la tapa entera dentro de la bodega respecto a donde
	#    empezó. Hacia arriba llega a la cubierta; hacia abajo la pasa la ola.
	var peor := 0.0
	var suma := 0.0
	var cuenta := 0
	var peor_cab := 0.0
	var deriva := 0.0
	var y0 := INF
	var t := 0.0
	while t < SEGUNDOS:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var inv := b.global_transform.affine_inverse()
		var tg := tapa.global_transform
		var centro: Vector3 = inv * tg.origin
		if y0 == INF:
			y0 = centro.y
			print("centro de la tapa a %.3f m sobre el origen del casco" % y0)
		var d_max := 0.0
		for k in n:
			var aqui: Vector3 = inv * (tg * vs[1 + k])
			d_max = maxf(d_max, absf(aqui.y - centro.y))
		suma += d_max
		peor = maxf(peor, d_max)
		deriva = maxf(deriva, absf(centro.y - y0))
		peor_cab = maxf(peor_cab, absf(rad_to_deg(b.global_transform.basis.get_euler().x)))
		cuenta += 1

	print("deriva vertical de la tapa entera: %.3f m" % deriva)
	print("el borde se sale del plano del casco: %.3f m de media, %.3f m el peor"
		% [suma / float(maxi(cuenta, 1)), peor])
	print("(cabeceo máximo en la tirada: %.2f°)" % peor_cab)
	get_tree().quit(0)

extends Node

## Qué hace el casco cuando queda a caballo entre dos olas y parte de él se queda en el aire.
##
## La física es la de Arquímedes: los puntos que salen del agua dejan de empujar, así que **los que
## siguen mojados tienen que hundirse más** para sostener el mismo peso. Si la mitad del casco está
## al aire, la otra mitad debe calar el doble. Lo que se ve si eso no pasa es un barco volando
## sobre el seno de la ola.
##
## Cinco cifras, y la tercera es la que decide:
##
## - **puntos al aire**: cuántos de los puntos de flotación están por encima de la lámina.
## - **hueco bajo el casco**: cuánto se separa del agua el punto más alto. Es lo que se ve.
## - **calado de los mojados contra el que PEDIRÍA Arquímedes**: la media de inmersión de los
##   puntos que siguen en el agua, frente a `calado · f/(1−f)` con f la fracción al aire, que es lo
##   que tendrían que calar para reponer el empuje perdido. Si el primero se queda corto, el barco
##   flota más alto de lo que debe y por eso vuela.
## - **error de empuje**: cuánto se aparta de cero la media de inmersiones, que es la condición de
##   equilibrio del modelo.
##
##     godot --path . tools/entre_dos_olas.tscn            # mar de siempre
##     godot --path . tools/entre_dos_olas.tscn -- 1.9     # temporal, que es cuando pasa
##
## Con ventana y navegando: parado y en calma no se queda nunca entre dos olas.

const SEGUNDOS := 30.0


func _ready() -> void:
	get_tree().create_timer(200.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	# Segundo argumento: CALADO a probar, en metros. Cambia a la vez lo que el casco se hunde y el
	# empuje que puede perder, que es lo que hay que mover a la vez para que el barco siga flotando
	# donde le toca. Sirve para ver qué calado haría falta para que el fondo no asome.
	var probar_calado := 0.0
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		Viento.fuerza_base = maxf(String(args[0]).to_float(), 0.05)
	if args.size() > 1:
		probar_calado = String(args[1]).to_float()
	await get_tree().create_timer(6.0).timeout
	Oleaje.asentar()

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		get_tree().quit(1)
		return
	b.set("anclado", false)
	if probar_calado > 0.0:
		b.set("calado", probar_calado)
		b.set("altura_flotacion", Oleaje.nivel - probar_calado)
		b.global_position.y = Oleaje.nivel - probar_calado
		await get_tree().create_timer(3.0).timeout
	var puntos: Array = b.get("_flotacion")
	var calado: float = float(b.get("calado"))
	# Los puntos de flotación viven en el PLANO DE FLOTACIÓN del casco, no en su origen: la
	# balandra tiene el origen en la quilla, 0,47 m por debajo. Midiéndolos a y=0 local, la
	# inmersión sale con ese offset metido y el "error de empuje" da el calado entero.
	var lamina_local: float = Oleaje.nivel - float(b.get("altura_flotacion"))
	print("\n─── entre dos olas ───")
	print("viento %.2f -> mar de %.2f m pico a pico, %d puntos de flotación, calado %.2f m"
		% [Viento.fuerza, Oleaje.altura, puntos.size(), calado])
	print("periodo propio de arfada: %.2f s  (2·pi·raiz(calado/g))" % (TAU * sqrt(calado / 9.81)))

	# Lo que de verdad delata que "vuela": cuánto tiempo pasa con TODO el casco fuera del agua, y
	# a qué aceleración cae mientras tanto. En el aire solo debería actuar la gravedad: 9,81 m/s².
	# Si cae más despacio es que algo lo sostiene, y lo único que puede sostenerlo es la
	# amortiguación del agua aplicada donde no hay agua.
	var volando := 0
	var caida_min := 0.0
	var v_ant := 0.0
	var y_ant := INF
	var peor_aire := 0
	var peor_hueco := 0.0
	var suma_err := 0.0
	# Para la comprobación de Arquímedes se guarda el PEOR instante, el de más puntos al aire.
	var mojados_en_el_peor := 0.0
	var pide_en_el_peor := 0.0
	var n := 0
	var t := 0.0
	while t < SEGUNDOS:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var g := b.global_transform
		var ph := Vector2((-g.basis.z).x, (-g.basis.z).z).normalized()
		var lh := Vector2((g.basis.x).x, (g.basis.x).z).normalized()
		var c := Vector2(g.origin.x, g.origin.z)
		var aire := 0
		var suma_moj := 0.0
		var suma_d := 0.0
		var hueco := 0.0
		for pt in puntos:
			var p: Vector3 = pt
			var mundo: Vector3 = g * Vector3(p.x, lamina_local, p.z)
			var h: float = Oleaje.altura_en(Vector2(mundo.x, mundo.z))
			# Inmersión REAL del punto: positiva si está bajo el agua.
			var d: float = h - mundo.y
			suma_d += maxf(d, -calado)
			if d < 0.0:
				aire += 1
				hueco = maxf(hueco, -d)
			else:
				suma_moj += d
		var moj := puntos.size() - aire
		if aire > peor_aire:
			peor_aire = aire
			mojados_en_el_peor = suma_moj / float(maxi(moj, 1))
			var f := float(aire) / float(puntos.size())
			# Con el casco entero al aire no hay a quién pedirle empuje: Arquímedes no tiene
			# solución y lo que toca es caer.
			pide_en_el_peor = calado * f / (1.0 - f) if f < 0.999 else INF
		peor_hueco = maxf(peor_hueco, hueco)
		var paso := 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var v_ahora := 0.0 if y_ant == INF else (g.origin.y - y_ant) / paso
		if aire == puntos.size():
			volando += 1
			if y_ant != INF:
				# Aceleración vertical de este paso, positiva hacia abajo.
				caida_min = maxf(caida_min, -(v_ahora - v_ant) / paso)
		y_ant = g.origin.y
		v_ant = v_ahora
		suma_err += absf(suma_d / float(puntos.size()))
		n += 1

	var fn := float(maxi(n, 1))
	print("puntos al aire, el peor instante: %d de %d" % [peor_aire, puntos.size()])
	print("la flotación se separa del agua: %.3f m el peor" % peor_hueco)
	# ESTO es lo que se ve: el fondo asoma cuando la línea de flotación se separa MÁS que el calado.
	# Con un casco que cala medio metro basta con que suba medio metro; con uno que cala metro y
	# medio hace falta el triple, y por eso los barcos de verdad no enseñan la quilla con mar
	# normal. Medir el hueco a secas engaña: sale mayor con más calado y parece que empeora.
	print("EL FONDO ASOMA           : %.3f m  (%s)"
		% [maxf(peor_hueco - calado, 0.0),
			"se ve la obra viva" if peor_hueco > calado else "no se ve"])
	if is_inf(pide_en_el_peor):
		print("en ese instante NO queda ningún punto en el agua: el casco entero está volando")
	else:
		print("en ese instante los mojados calan %.3f m; Arquímedes pide %.3f m  (%.0f %%)"
			% [mojados_en_el_peor, pide_en_el_peor,
				100.0 * mojados_en_el_peor / maxf(pide_en_el_peor, 0.001)])
	print("error de empuje medio         : %.4f m" % (suma_err / fn))
	print("tiempo con el casco ENTERO al aire: %.2f s de %.0f  (%.1f %%)"
		% [float(volando) / maxf(Engine.physics_ticks_per_second, 1), SEGUNDOS,
			100.0 * float(volando) / fn])
	print("cayendo, la mayor aceleración vista: %.2f m/s²  (la gravedad son 9,81)" % caida_min)
	get_tree().quit(0)

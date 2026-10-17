extends Node

## Cuánto CABECEA el casco, rumbo a rumbo, y cuánto le tocaría.
##
## La flotación lateral se veía bien y la de proa a popa no, y eso no se puede juzgar con un
## solo rumbo: un barco atravesado a la mar escora mucho y no cabecea nada, y es lo correcto.
## Aquí se le pone la mar por la proa, por la amura, por el través, por la aleta y por la popa
## —anclado, para que la escora de navegación no enturbie nada— y se mide en cada caso:
##
## - **cabeceo real**: lo que el casco hace de verdad.
## - **el que tocaría**: la inclinación de la recta proa-popa apoyada en la ola, o sea lo que el
##   propio `Barco._seguir_al_mar()` lee en sus cuatro puntos.
## - **la pendiente LOCAL**: la misma medida con una base de 1 m en vez de la eslora entera. Es
##   la pendiente de verdad del agua bajo el barco, y la diferencia con la anterior es lo que se
##   pierde por promediar a lo largo de doce metros: una ola de doce metros se cancela del todo
##   entre proa y popa, y las cortas son justo las de más pendiente.
##
## - **el de 7 puntos ponderados**: el mismo momento de asiento pero integrando la ola a lo largo
##   de la eslora con el ancho de la flotación como peso (elipse), en vez de con los dos extremos
##   solos. Es lo que hace el agua de verdad —el par de asiento es la integral de la presión— y
##   rompe la cancelación: con dos puntos, una ola tan larga como el barco se anula entera.
##
##     godot --path . tools/cabeceo_en_la_mar.tscn
##
## Con ventana y sobre el mundo real: lo que se compara es contra el agua de la escena.

const RUMBOS := [0.0, 45.0, 90.0, 135.0, 180.0]
const NOMBRES := ["mar de proa", "por la amura", "por el traves", "por la aleta", "mar de popa"]
const ASENTAR := 3.0
const MEDIR := 12.0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(6.0).timeout
	Oleaje.asentar()

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco")
		get_tree().quit(1)
		return
	b.set("anclado", true)
	var r: Vector2 = b.get("recorte_radio")
	var eslora: float = r.y
	# Hacia dónde CORREN las olas, en planta. Es el rumbo del viento de fondo, que es de donde
	# `Oleaje` saca su eje.
	var d := Vector2(Viento.direccion_base.x, Viento.direccion_base.z).normalized()

	print("\n─── cabeceo en la mar ───")
	print("casco de %.1f m de eslora, mar de %.2f m pico a pico" % [eslora * 2.0, Oleaje.altura])
	print("%-14s %-22s %-22s %-22s %s"
		% ["rumbo", "cabeceo real", "tocaria (2 puntos)", "tocaria (7 ponderados)", "pendiente local"])

	for i in RUMBOS.size():
		# Proa hacia donde vienen las olas cuando el rumbo relativo es 0: mar de proa.
		var dir := -d.rotated(deg_to_rad(RUMBOS[i]))
		b.set("global_rotation", Vector3(0.0, atan2(-dir.x, -dir.y), 0.0))
		await get_tree().create_timer(ASENTAR).timeout

		var real := [INF, -INF]
		var toca := [INF, -INF]
		var pond := [INF, -INF]
		var local := [INF, -INF]
		var s := 0.0
		var ss := 0.0
		var n := 0
		# Correlación entre lo que el casco cabecea y lo que la ola le pide, con el convenio de
		# Godot: girar +X sube la proa (que está en −Z). Si sale NEGATIVA el casco mete la proa
		# justo cuando la ola se la levanta, y eso no es cabecear poco: es cabecear al revés.
		var sa := 0.0
		var sb := 0.0
		var saa := 0.0
		var sbb := 0.0
		var sab := 0.0
		var se := 0.0
		var sf := 0.0
		var see := 0.0
		var sff := 0.0
		var sef := 0.0
		var t := 0.0
		while t < MEDIR:
			await get_tree().physics_frame
			t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
			var g: Transform3D = b.global_transform
			var ph := Vector2((-g.basis.z).x, (-g.basis.z).z).normalized()
			var c := Vector2(g.origin.x, g.origin.z)
			var cab := rad_to_deg(g.basis.get_euler().x)
			real[0] = minf(real[0], cab); real[1] = maxf(real[1], cab)
			var ct := rad_to_deg(-atan2(Oleaje.altura_en(c + ph * eslora)
				- Oleaje.altura_en(c - ph * eslora), eslora * 2.0))
			toca[0] = minf(toca[0], ct); toca[1] = maxf(toca[1], ct)
			var cp := rad_to_deg(_asiento_ponderado(c, ph, eslora))
			pond[0] = minf(pond[0], cp); pond[1] = maxf(pond[1], cp)
			var cl := rad_to_deg(-atan2(Oleaje.altura_en(c + ph * 0.5)
				- Oleaje.altura_en(c - ph * 0.5), 1.0))
			local[0] = minf(local[0], cl); local[1] = maxf(local[1], cl)
			s += cab; ss += cab * cab; n += 1
			var a := cab
			# La referencia es la pendiente PONDERADA a lo largo de la eslora, no la de los dos
			# extremos: comparar contra dos puntos separados una eslora es comparar contra la
			# medida que se acaba de tirar, y esa cancela las olas de la propia eslora.
			var bb := -rad_to_deg(_asiento_ponderado(c, ph, eslora))
			sa += a; sb += bb; saa += a * a; sbb += bb * bb; sab += a * bb
			var lhh := Vector2((g.basis.x).x, (g.basis.x).z).normalized()
			var manga: float = (b.get("recorte_radio") as Vector2).x
			var e2 := rad_to_deg(g.basis.get_euler().z)
			var f2 := -rad_to_deg(_asiento_ponderado(c, lhh, manga))
			se += e2; sf += f2; see += e2 * e2; sff += f2 * f2; sef += e2 * f2

		var fn := float(maxi(n, 1))
		var sigma: float = sqrt(maxf(ss / fn - (s / fn) * (s / fn), 0.0))
		print("%-14s %6.2f a %6.2f (%4.2f)  %6.2f a %6.2f (%4.2f)  %6.2f a %6.2f (%4.2f)  %6.2f a %6.2f (%4.2f)"
			% [NOMBRES[i], real[0], real[1], real[1] - real[0],
				toca[0], toca[1], toca[1] - toca[0],
				pond[0], pond[1], pond[1] - pond[0],
				local[0], local[1], local[1] - local[0]])
		var fq := float(maxi(n, 1))
		var rc: float = (sab / fq - (sa / fq) * (sb / fq)) / maxf(sqrt(
			maxf(saa / fq - (sa / fq) * (sa / fq), 0.0)
			* maxf(sbb / fq - (sb / fq) * (sb / fq), 0.0)), 1e-9)
		var re: float = (sef / fq - (se / fq) * (sf / fq)) / maxf(sqrt(
			maxf(see / fq - (se / fq) * (se / fq), 0.0)
			* maxf(sff / fq - (sf / fq) * (sf / fq), 0.0)), 1e-9)
		print("%-14s   sigma %.2f°   parecido con la ola: cabeceo %+.3f, escora %+.3f"
			% ["", sigma, rc, re])

	get_tree().quit(0)


## Ángulo de asiento que pide la ola integrando a lo largo de la eslora con el ancho de la
## flotación como peso, que para una elipse va con √(1−(x/L)²). Es una recta por mínimos
## cuadrados ponderada: pendiente = Σ w·h·x / Σ w·x².
func _asiento_ponderado(c: Vector2, ph: Vector2, eslora: float) -> float:
	const N := 7
	var num := 0.0
	var den := 0.0
	for j in N:
		var u := -1.0 + 2.0 * float(j) / float(N - 1)
		var w: float = sqrt(maxf(1.0 - u * u, 0.0))
		var x := u * eslora
		var h: float = Oleaje.altura_en(c + ph * x)
		num += w * h * x
		den += w * x * x
	if den < 1e-6:
		return 0.0
	return -atan(num / den)

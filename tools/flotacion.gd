extends Node

## Si el barco flota sobre el mar que se ve, o sobre otro.
##
## Cuatro cifras, y las cuatro hacen falta:
##
## - **error de flotación**: cuánto se separa la línea de flotación del casco de la lámina que
##   hay debajo. Es el hueco por el que se ve el mar entrar por el costado, o el casco colgando
##   en el aire sobre el seno de la ola.
## - **cabeceo y escora**: lo que el casco se inclina de verdad.
## - **los que TOCARÍAN**: lo que se inclinaría apoyado en la ola, sacado de la altura del mar en
##   la proa, la popa y las dos bandas. La diferencia entre este y el anterior es lo que falta.
## - **parecido con el mar**: correlación entre lo que sube el barco y lo que sube el agua bajo
##   él. Es la que distingue "se mueve" de "se mueve CON el mar": un `sin()` propio da mucho
##   movimiento y cero parecido, que es exactamente lo que había.
##
##     godot --path . tools/flotacion.tscn            # con la mar de siempre
##     godot --path . tools/flotacion.tscn -- 1.9      # con el viento que se le diga (temporal)
##
## Con ventana y sobre el mundo real, porque lo que se compara es contra el agua de la escena.

const SEGUNDOS := 20.0


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	for a in OS.get_cmdline_user_args():
		Viento.fuerza_base = maxf(String(a).to_float(), 0.05)
	# 6 s: el mar pone una malla basta al arrancar y la fina después (ver `mar.gd`), y su
	# `Oleaje.nivel` se fija en ese momento.
	await get_tree().create_timer(6.0).timeout
	Oleaje.asentar()

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco")
		get_tree().quit(1)
		return
	# Semiejes del casco: el propio barco los publica para el recorte del agua.
	var r: Vector2 = b.get("recorte_radio")
	var manga: float = r.x
	var eslora: float = r.y
	print("\n─── flotación ───")
	print("casco de %.1f m de eslora y %.1f de manga (semiejes %.2f, %.2f)"
		% [eslora * 2.0, manga * 2.0, manga, eslora])
	print("viento %.2f -> mar de %.2f m pico a pico nominal" % [Viento.fuerza, Oleaje.altura])

	var separacion_reposo: float = float(b.get("altura_flotacion")) - Oleaje.nivel
	# OJO: `altura_flotacion` es la Y del ORIGEN del barco, y el de la balandra está en la quilla,
	# o sea por DEBAJO del agua. La separación en reposo sale negativa y es justo su calado; lo
	# que se mide después es cuánto se aparta de ella, no su valor.
	print("origen del casco en y=%.3f, lámina en y=%.3f -> %.2f m de separación en reposo"
		% [float(b.get("altura_flotacion")), Oleaje.nivel, separacion_reposo])
	var err_medio := 0.0
	var err_peor := 0.0
	var s_quieto := 0.0
	var peor_quieto := 0.0
	var cab := [INF, -INF]
	var esc := [INF, -INF]
	var cab_toca := [INF, -INF]
	var esc_toca := [INF, -INF]
	# Para la correlación: sumas de y del barco y altura del mar.
	var sy := 0.0
	var sm := 0.0
	var syy := 0.0
	var smm := 0.0
	var sym := 0.0
	var n := 0
	var t := 0.0
	while t < SEGUNDOS:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		b.set("anclado", false)
		var g := b.global_transform
		var proa := -g.basis.z
		var lado := g.basis.x
		# Los cuatro puntos, en el plano horizontal: el casco se apoya en la ola, no en su propia
		# inclinación, así que se muestrea en planta.
		var ph := Vector2(proa.x, proa.z).normalized()
		var lh := Vector2(lado.x, lado.z).normalized()
		var c := Vector2(g.origin.x, g.origin.z)
		var h_proa: float = Oleaje.altura_en(c + ph * eslora)
		var h_popa: float = Oleaje.altura_en(c - ph * eslora)
		var h_est: float = Oleaje.altura_en(c + lh * manga)
		var h_bab: float = Oleaje.altura_en(c - lh * manga)
		var h_mar := (h_proa + h_popa + h_est + h_bab) * 0.25

		# El error es cuánto se aparta la separación casco-agua de la que tiene en reposo, NO la
		# diferencia bruta de alturas: el casco flota con su separacion_reposo por encima de la lámina
		# y restar eso es parte de la medida. Sin ello el número sale casi igual con el barco
		# siguiendo la ola y sin seguirla, que es como se colaba.
		var e: float = absf((g.origin.y - h_mar) - separacion_reposo)
		err_medio += e
		err_peor = maxf(err_peor, e)
		# Lo que le pasaría a un casco que NO siguiera al mar: el agua le sube y le baja entera.
		# Va en la misma tirada para que la comparación sea contra el mismo mar.
		s_quieto += absf(h_mar - Oleaje.nivel)
		peor_quieto = maxf(peor_quieto, absf(h_mar - Oleaje.nivel))

		var eu := g.basis.get_euler()
		cab[0] = minf(cab[0], rad_to_deg(eu.x)); cab[1] = maxf(cab[1], rad_to_deg(eu.x))
		esc[0] = minf(esc[0], rad_to_deg(eu.z)); esc[1] = maxf(esc[1], rad_to_deg(eu.z))
		var ct := rad_to_deg(atan2(h_proa - h_popa, eslora * 2.0))
		var et := rad_to_deg(atan2(h_est - h_bab, manga * 2.0))
		cab_toca[0] = minf(cab_toca[0], ct); cab_toca[1] = maxf(cab_toca[1], ct)
		esc_toca[0] = minf(esc_toca[0], et); esc_toca[1] = maxf(esc_toca[1], et)

		sy += g.origin.y; sm += h_mar
		syy += g.origin.y * g.origin.y; smm += h_mar * h_mar
		sym += g.origin.y * h_mar
		n += 1

	var fn := float(maxi(n, 1))
	var vy: float = maxf(syy / fn - (sy / fn) * (sy / fn), 0.0)
	var vm: float = maxf(smm / fn - (sm / fn) * (sm / fn), 0.0)
	var cov: float = sym / fn - (sy / fn) * (sm / fn)
	var corr: float = cov / maxf(sqrt(vy * vm), 1e-9)

	print("\nerror de flotación  : %.3f m de media, %.3f m el peor" % [err_medio / fn, err_peor])
	print("   si no siguiera   : %.3f m de media, %.3f m el peor" % [s_quieto / fn, peor_quieto])
	print("cabeceo             : %.2f° a %.2f°   (tocaría %.2f° a %.2f°)"
		% [cab[0], cab[1], cab_toca[0], cab_toca[1]])
	print("escora              : %.2f° a %.2f°   (tocaría %.2f° a %.2f°)"
		% [esc[0], esc[1], esc_toca[0], esc_toca[1]])
	print("parecido con el mar : %.3f   (1 = sube y baja CON la ola, 0 = por su cuenta)" % corr)
	print("lo que sube el barco: %.3f m de desviación típica (el mar, %.3f)"
		% [sqrt(vy), sqrt(vm)])
	get_tree().quit(0)

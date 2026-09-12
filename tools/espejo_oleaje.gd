extends Node

## Si el mar que se VE es el mismo que el que CALCULA el juego.
##
## La altura de la ola está escrita dos veces —`assets/shaders/oleaje.gdshaderinc` la dibuja,
## el autoload `Oleaje` la responde— porque no hay manera de compartir código entre un shader y
## GDScript. Cuando divergen, el barco flota sobre olas distintas de las que se ven y NADA lo
## avisa: no hay error, no hay aviso, solo un casco que sube cuando el agua baja.
##
## Compara las dos en 64 puntos repartidos por la zona que se ve desde cubierta. La diferencia
## debe quedarse en el redondeo del empaquetado (0,25 mm).
##
##     godot --path . tools/espejo_oleaje.tscn
##
## Con ventana obligatoriamente: `--headless` no renderiza y el espejo sale en negro.

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(1))
	await get_tree().create_timer(1.0).timeout
	Viento.direccion_base = Vector3(1, 0, 0.3)
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(2.0).timeout

	var puntos := PackedVector2Array()
	var r := RandomNumberGenerator.new()
	r.seed = 20260911
	for i in 64:
		puntos.append(Vector2(r.randf_range(-60.0, 60.0), r.randf_range(-60.0, 60.0)))

	print("\n─── espejo del oleaje (shader contra GDScript) ───")
	print("mar                 : %.3f m pico a pico, ola más corta %.1f m"
		% [Oleaje.altura, Oleaje.longitud_mas_corta()])
	print("%-14s %12s %12s   %s" % ["magnitud", "peor error", "error medio", "muestra 0"])
	for modo in 4:
		var reloj: float = Oleaje.t
		var shader: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(
			get_tree(), puntos, modo)
		var peor := 0.0
		var suma := 0.0
		var s0 := 0.0
		var g0 := 0.0
		for i in puntos.size():
			var g: float = _gdscript(puntos[i], modo, reloj)
			var e: float = absf(g - shader[i])
			peor = maxf(peor, e)
			suma += e
			if i == 0:
				s0 = shader[i]; g0 = g
		print("%-14s %9.5f m %9.5f m   shader %+.4f  gdscript %+.4f"
			% [["altura", "arrastre x", "arrastre z", "normal.y"][modo],
				peor, suma / puntos.size(), s0, g0])
	get_tree().quit(0)


func _gdscript(p: Vector2, modo: int, reloj: float) -> float:
	match modo:
		0: return Oleaje.desplazamiento(p, reloj).y
		1: return Oleaje.desplazamiento(p, reloj).x
		2: return Oleaje.desplazamiento(p, reloj).z
		_: return Oleaje.normal(p, reloj).y

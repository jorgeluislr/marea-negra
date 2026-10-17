extends Node

## Cuánto discrepan el oleaje del shader y su espejo de GDScript según lo LEJOS del cero local
## que se pregunte.
##
##     godot --path . tools/espejo_lejos.tscn --max-fps 120
##
## La batería compara a ±60 m del cero; con el origen flotante el barco se aleja hasta `umbral`
## antes de recentrar, así que el espejo tiene que aguantar hasta ahí.

const RADIOS := [0.0, 100.0, 300.0, 1000.0, 2000.0, 3000.0, 5000.0]


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func():
		push_error("espejo_lejos: se acabó el tiempo"); get_tree().quit(1))
	await get_tree().process_frame
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.direccion_base = Vector3(1, 0, 0.3)
	Viento.fuerza_base = 1.0
	await get_tree().process_frame
	Oleaje.asentar()
	var r := RandomNumberGenerator.new()
	r.seed = 7
	Oleaje._al_recentrar(Vector3(12345.0, 0.0, -6789.0))
	await _barrer(r, "tras recentrar 14 km (primera llamada)")
	await _barrer(r, "otra vez")
	get_tree().quit()


func _barrer(r: RandomNumberGenerator, que: String) -> void:
	print("── ", que)
	for radio in RADIOS:
		var puntos := PackedVector2Array()
		for i in 48:
			var ang := r.randf() * TAU
			puntos.append(Vector2(cos(ang), sin(ang)) * radio
				+ Vector2(r.randf_range(-60, 60), r.randf_range(-60, 60)))
		var reloj: float = Oleaje.t
		var antes := PackedFloat32Array()
		for p in puntos:
			antes.append(Oleaje.desplazamiento(p, reloj).y)
		var sh: PackedFloat32Array = await UtilesPruebas.oleaje_del_shader(get_tree(), puntos, 0)
		var peor := 0.0
		var media := 0.0
		for i in puntos.size():
			var e := absf(antes[i] - sh[i])
			peor = maxf(peor, e)
			media += e / puntos.size()
		print("a %5.0f m del cero local: peor %.4f m, media %.4f m" % [radio, peor, media])

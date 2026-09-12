extends Node

## QUÉ arista se pasa del 25 %, y cuánto es eso en milímetros.
##
## El porcentaje engaña: una arista de reposo corta se pone al 240 % con dos centímetros y no se
## ve, mientras que un 26 % en una arista larga sí. Antes de tocar nada hay que saber de cuál de
## las dos se trata, así que esto lista las peores con su largo de reposo al lado.
##
## Compara las dos frecuencias en la misma ejecución, con el mismo paño ya asentado.

func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	var barco := esc.instantiate() as Node3D
	add_child(barco)
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	barco.set("anclado", true)
	await get_tree().create_timer(6.0).timeout

	var tela: Node = null
	for h in barco.get_children():
		if h.has_method("datos_depuracion") and str(h.get("nombre_malla")) == "foque":
			tela = h
	for hz in [60, 120]:
		Engine.physics_ticks_per_second = hz
		await get_tree().create_timer(4.0).timeout
		_listar(tela, hz)
	get_tree().quit()


func _listar(tela: Node, hz: int) -> void:
	var d: Dictionary = tela.datos_depuracion()
	var cuerpo: SoftBody3D = d["cuerpo"]
	var ar: PackedInt32Array = d["aristas"]
	var l0s: PackedFloat32Array = d["largo0"]
	var fijo: PackedByteArray = d["fijo"]
	var peores := []
	for e in l0s.size():
		var l0: float = l0s[e]
		if l0 < 1e-6:
			continue
		var a: int = ar[e * 2]
		var b: int = ar[e * 2 + 1]
		var l := cuerpo.get_point_transform(a).distance_to(cuerpo.get_point_transform(b))
		peores.append([(l - l0) / l0, l0, l, a, b, fijo[a] + fijo[b]])
	peores.sort_custom(func(x, y): return x[0] > y[0])
	var malas := 0
	for x in peores:
		if x[0] > 0.25:
			malas += 1
	print("\n-- foque a %d Hz: %d aristas pasadas del 25 %% de %d" % [hz, malas, l0s.size()])
	print("   %-9s %-11s %-11s %-10s %s" % ["estira", "reposo", "ahora", "crece", "anclados"])
	for i in min(5, peores.size()):
		var x = peores[i]
		print("   %8.1f%% %8.1f mm %8.1f mm %7.1f mm   %d de 2" % [x[0] * 100.0, x[1] * 1000.0, x[2] * 1000.0, (x[2] - x[1]) * 1000.0, x[5]])

extends Node
## Da la vuelta a la flota con TAB y vuelve a la balandra, midiendo el estiramiento de sus
## velas la primera vez y la segunda. Si la segunda es peor, el barco reinstanciado arranca mal.
@export var carpeta := ""
## Con false no se pulsa TAB: es el CONTROL, para saber si lo que cambia en la segunda
## medida es haber cambiado de barco o simplemente el viento y el rumbo de ese instante.
@export var cambiar_de_barco := true

func _ready() -> void: _correr()

func _tecla(k: int) -> void:
	for p in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k; e.physical_keycode = k; e.pressed = p
		Input.parse_input_event(e)
		await get_tree().process_frame

## Mide en condiciones IGUALES las dos veces: barco anclado y viento fijo, porque si no, lo que
## cambia entre la primera medida y la segunda es el rumbo respecto al viento y no el codigo.
func _estabilizar() -> void:
	var b := get_tree().get_nodes_in_group("barco_activo")[0]
	b.set("anclado", true)
	for i in 180:
		Viento.direccion = Vector3(1, 0, 0)
		Viento.fuerza = 1.0
		await get_tree().process_frame

func _medir(cuando: String) -> void:
	var b := get_tree().get_nodes_in_group("barco_activo")[0]
	print("--- %s: %s ---" % [cuando, b.name])
	for v in b.get_children():
		if not v.has_method("datos_depuracion"):
			continue
		var d: Dictionary = v.datos_depuracion()
		if d.is_empty():
			print("   %s: SIN CUERPO todavia" % v.name)
			continue
		var cuerpo: SoftBody3D = d["cuerpo"]
		var ar: PackedInt32Array = d["aristas"]
		var l0: PackedFloat32Array = d["largo0"]
		var suma := 0.0; var peor := 0.0; var n := 0
		for e in l0.size():
			var a: Vector3 = cuerpo.get_point_transform(ar[e * 2])
			var c: Vector3 = cuerpo.get_point_transform(ar[e * 2 + 1])
			var f: float = absf(a.distance_to(c) - l0[e]) / maxf(l0[e], 0.0001)
			suma += f; peor = maxf(peor, f); n += 1
		# Las peores aristas, con su tipo: una fijo/fijo estirada NO la puede arreglar el solver
		# (los dos extremos estan clavados a la piel), asi que dice que el problema es la PIEL.
		var fijo: PackedByteArray = d["fijo"]
		var peores: Array = []
		for e in l0.size():
			var a2: Vector3 = cuerpo.get_point_transform(ar[e * 2])
			var c2: Vector3 = cuerpo.get_point_transform(ar[e * 2 + 1])
			var f2: float = absf(a2.distance_to(c2) - l0[e]) / maxf(l0[e], 0.0001)
			if f2 > 0.25:
				peores.append([f2, ar[e * 2], ar[e * 2 + 1], l0[e],
					"%s/%s" % ["fijo" if fijo[ar[e * 2]] == 1 else "libre",
						"fijo" if fijo[ar[e * 2 + 1]] == 1 else "libre"]])
		peores.sort_custom(func(x, y): return x[0] > y[0])
		var det := ""
		for i in mini(4, peores.size()):
			det += "
        v%d-v%d %s  %.3f m -> +%.0f %%" % [
				peores[i][1], peores[i][2], peores[i][4], peores[i][3], 100.0 * peores[i][0]]
		var apa: Variant = v.get("aparejo")
		print("   %-18s estiramiento medio %6.2f %%  peor %5.0f %%  | izada=%s arriado=%.3f recogiendo=%s%s" % [
			v.name, 100.0 * suma / maxf(n, 1), 100.0 * peor,
			v.esta_izada() if v.has_method("esta_izada") else "-",
			apa.arriado_medido() if apa != null else -1.0, d.get("recogiendo", "-"), det])

func _foto(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(n))

func _correr() -> void:
	await get_tree().create_timer(4.0).timeout
	await _estabilizar()
	_medir("primera balandra")
	await _foto("vuelta_1_primera.png")
	for i in 4:
		if cambiar_de_barco:
			await _tecla(KEY_TAB)
		await get_tree().create_timer(3.0).timeout
	await _estabilizar()
	_medir("segunda medida (%s)" % ("tras 4 TAB" if cambiar_de_barco else "SIN cambiar de barco"))
	await _foto("vuelta_2_segunda.png")
	get_tree().quit()

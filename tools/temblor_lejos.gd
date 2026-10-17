extends Node

## Cuánto TIEMBLAN el casco y la tela lejos del origen del mundo, con y sin origen flotante, y
## si recentrar da un tirón o hace saltar el mar.
##
##     godot --path . tools/temblor_lejos.tscn --max-fps 120
##
## Por qué hace falta: el Caribe de este mundo mide 122 × 80 km y las posiciones van en precisión
## simple. A 50 km un `float` solo distingue pasos de 3,9 mm (2⁻⁸ m), así que cada paso de física
## el casco y cada punto del paño caen en la rejilla de 4 mm más cercana. Eso no se ve en la
## posición sino en la ACELERACIÓN: la segunda diferencia entre pasos consecutivos (ver
## `UtilesPruebas.temblor`, que es la medida que usan también las pruebas).
##
## Casos:
##   origen          el barco nace en el origen                              (la referencia)
##   50 km           nace a 50 km y nadie recentra                           (el fallo)
##   50 km + O       nace a 50 km con el origen flotante encendido           (el arreglo)
##   recentrado      navegando junto al origen, se recentra a mitad de medida: tirón del casco y
##                   de la tela en el paso del recentrado, y altura de la ola en el MISMO punto
##                   absoluto antes y después.
##   20 recentrados  seguidos: si correr la tela le inventara velocidad o le rehiciera las
##                   longitudes de reposo, se acumularía aquí.
##
## Medido el 17-10-2026 (segunda diferencia por paso; estiramiento, el medio del peor paño):
##
##                   casco      tela libre   tela anclada   estiramiento
##     origen        0,20 mm    2,7 mm       0,004 mm       0,007-0,018
##     50 km         0,20       7,2          2,80           0,036, 1-2 aristas > 25 %
##     50 km + O     0,11       2,4          0,004          0,016
##
##     recentrado: tirón del casco 0,07 mm (0,39 el peor del resto), de la tela 91 mm (110 el
##     peor del resto: el paño flamea), ola 0,001 mm; 20 recentrados, 0 aristas > 25 %.
##
## (El casco a 50 km sin recentrar llegó a medir 1,55 mm; era el MAR, que rolaba alrededor del cero
## del mundo y a 50 km amplificaba el redondeo de la dirección. Desde que rola alrededor del barco
## da 0,20 aunque no se recentre: lo que sigue delatando la precisión simple es la tela anclada.)
##
## Correr la tela moviendo el nodo `SoftBody3D` en vez de punto a punto la revienta: 272 aristas
## pasadas del 25 % al primer recentrado. Ver `TelaFisica._al_recentrar`.

const MUNDO := "res://scenes/world/main_world.tscn"
const PASOS := 240
const LEJOS := 50000.0

var _mundo: Node3D


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func():
		push_error("temblor_lejos: se acabó el tiempo"); get_tree().quit(1))
	var origen := get_node_or_null("/root/Origen")
	await _caso("origen", 0.0, false)
	await _caso("50 km", LEJOS, false)
	if origen != null:
		await _caso("50 km + O", LEJOS, true)
		await _recentrado()
	else:
		print("(no hay autoload Origen: solo se miden los casos sin origen flotante)")
	get_tree().quit()


func _montar(x: float, con_origen: bool) -> Node3D:
	var origen := get_node_or_null("/root/Origen")
	if origen != null:
		origen.reiniciar()
		origen.activo = con_origen
	_mundo = (load(MUNDO) as PackedScene).instantiate() as Node3D
	var gestor := _mundo.get_node("GestorBarcos") as Node3D
	gestor.position.x += x
	add_child(_mundo)
	var b: Node3D = null
	var t := 0.0
	while t < 20.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		b = UtilesPruebas.barco(get_tree())
		if b != null and _montadas() >= 3:
			break
	if b == null:
		return null
	await UtilesPruebas.estabilizar(get_tree(), 4.0)
	return b


func _montadas() -> int:
	var n := 0
	for t in UtilesPruebas.telas(get_tree()):
		if not (t.datos_depuracion() as Dictionary).is_empty():
			n += 1
	return n


func _desmontar() -> void:
	_mundo.queue_free()
	_mundo = null
	await get_tree().process_frame
	await get_tree().process_frame


func _caso(nombre: String, x: float, con_origen: bool) -> void:
	var b := await _montar(x, con_origen)
	if b == null:
		print("%-12s  no hay barco con telas" % nombre)
		await _desmontar()
		return
	var origen := get_node_or_null("/root/Origen")
	var abs_x: float = b.global_position.x + (origen.x if origen != null else 0.0)
	var m: Dictionary = await UtilesPruebas.temblor(get_tree(), b, PASOS)
	print(("%-12s  x local %9.1f m (absoluta %8.0f)   casco %6.3f mm   tela libre %6.3f mm"
		+ " (anclada %6.3f)   estiramiento medio %.4f  aristas > 25 %%: %d")
		% [nombre, b.global_position.x, abs_x, m["casco"] * 1000.0, m["libre"] * 1000.0,
			m["anclada"] * 1000.0, m["estir"], m["malas"]])
	await _desmontar()


## Navegando junto al origen se fuerza un recentrado de 2 km a mitad de la medida; después, veinte
## seguidos.
func _recentrado() -> void:
	var b := await _montar(0.0, true)
	if b == null:
		return
	await UtilesPruebas.navegar(get_tree(), 6.0)
	var origen := get_node("/root/Origen")
	var e := {}
	var accion := func():
		# La ola en un punto ABSOLUTO a 30 m de proa, con el reloj congelado para que lo único
		# que cambie sea el recentrado.
		var p := b.global_position - b.global_transform.basis.z * 30.0
		e["abs"] = origen.a_global(p)
		e["h0"] = Oleaje.altura_en(Vector2(p.x, p.z), Oleaje.t)
		origen.recentrar(Vector3(2000.0, 0.0, 0.0))
		var q: Vector3 = origen.a_local(e["abs"])
		e["h1"] = Oleaje.altura_en(Vector2(q.x, q.z), Oleaje.t)
	var m: Dictionary = await UtilesPruebas.temblor(get_tree(), b, 120, 60, accion)
	print("recentrado")
	print("   casco: tirón %.3f mm (peor del resto %.3f)   tela: tirón %.3f mm (peor del resto %.3f)"
		% [m["casco_pico"] * 1000.0, m["casco_resto"] * 1000.0, m["tela_pico"] * 1000.0,
			m["tela_resto"] * 1000.0])
	print("   ola en el mismo punto absoluto: %.5f -> %.5f m (salto %.3f mm)"
		% [e["h0"], e["h1"], absf(e["h1"] - e["h0"]) * 1000.0])
	print("   estiramiento medio %.4f  aristas > 25 %%: %d" % [m["estir"], m["malas"]])
	var antes := await _estir_total()
	for i in 20:
		origen.recentrar(Vector3(-1000.0 if i % 2 == 0 else 1000.0, 0.0, 700.0))
		for _k in 6:
			await get_tree().physics_frame
	await UtilesPruebas.navegar(get_tree(), 2.0)
	var despues := await _estir_total()
	print("   20 recentrados: estiramiento medio %.4f -> %.4f, aristas > 25 %%: %d -> %d"
		% [antes.x, despues.x, int(antes.y), int(despues.y)])
	await _desmontar()


func _estir_total() -> Vector2:
	var peor := 0.0
	var malas := 0
	for t in UtilesPruebas.telas(get_tree()):
		var d: Dictionary = await UtilesPruebas.estiramiento(get_tree(), t)
		peor = maxf(peor, d.get("medio", 0.0))
		malas += int(d.get("malas", 0))
	return Vector2(peor, malas)

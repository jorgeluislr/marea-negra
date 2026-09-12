class_name UtilesPruebas
extends RefCounted

## Lo que necesitan varias pruebas: encontrar el barco, teclear, y medir tela.


static func barco(arbol: SceneTree) -> Node3D:
	var l := arbol.get_nodes_in_group("barco_activo")
	return l[0] as Node3D if not l.is_empty() else null


## Pulsa y suelta una tecla como lo haría el jugador, para probar los controles de verdad y no
## llamando a los métodos por dentro.
static func tecla(arbol: SceneTree, k: int) -> void:
	for pulsada in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pulsada
		Input.parse_input_event(e)
		await arbol.process_frame


## Deja el barco quieto y el viento constante durante `segundos`.
##
## OJO: asignar `Viento.direccion` NO fija el viento — el autoload lo recalcula cada frame desde
## `direccion_base` con su bamboleo y sus ráfagas del ±45 %. Hay que tocar la BASE y anular la
## variación, o creerás estar midiendo en calma y estarás midiendo en ráfaga.
static func estabilizar(arbol: SceneTree, segundos := 3.0, dir := Vector3(1, 0, 0)) -> void:
	var t := 0.0
	while t < segundos:
		Viento.direccion_base = dir
		Viento.bamboleo_dir = 0.0
		Viento.variacion_fuerza = 0.0
		Viento.fuerza_base = 1.0
		var b := barco(arbol)
		if b != null:
			b.set("anclado", true)
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame


## Deja el barco NAVEGANDO con viento constante durante `segundos`, y devuelve su velocidad.
##
## Lo contrario de `estabilizar`, que lo ancla. Hace falta para todo lo que dependa del viento
## APARENTE: con el barco quieto el aparente y el real son el mismo vector y la prueba no puede
## distinguirlos.
static func navegar(arbol: SceneTree, segundos := 8.0, dir := Vector3(0, 0, -1)) -> float:
	var t := 0.0
	var b := barco(arbol)
	while t < segundos:
		Viento.direccion_base = dir
		Viento.bamboleo_dir = 0.0
		Viento.variacion_fuerza = 0.0
		Viento.fuerza_base = 1.0
		if b != null:
			b.set("anclado", false)
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame
	return (b as CharacterBody3D).velocity.length() if b is CharacterBody3D else 0.0


## Desvío MEDIO, en grados, entre el vuelo de un paño y una dirección, promediado en el tiempo.
##
## Promediado porque un paño que flamea cruza su dirección de equilibrio a cada momento: una
## muestra suelta puede dar 0° o 40° con el mismo paño perfectamente orientado.
static func desvio_del_vuelo(arbol: SceneTree, tela: Node, dir: Vector3, segundos := 6.0) -> float:
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty() or dir.length() < 0.01:
		return 999.0
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var objetivo := Vector3(dir.x, 0.0, dir.z).normalized()
	var suma := 0.0
	var n := 0
	var t := 0.0
	while t < segundos:
		await arbol.physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var anc := Vector3.ZERO
		var na := 0
		var lej := Vector3.ZERO
		var nl := 0
		for i in fijo.size():
			var p: Vector3 = cuerpo.get_point_transform(i)
			if fijo[i] == 1:
				anc += p; na += 1
			else:
				lej += p; nl += 1
		if na == 0 or nl == 0:
			continue
		var vuelo := (lej / float(nl)) - (anc / float(na))
		vuelo.y = 0.0
		if vuelo.length() < 0.01:
			continue
		suma += rad_to_deg(acos(clampf(vuelo.normalized().dot(objetivo), -1.0, 1.0)))
		n += 1
	return suma / maxf(n, 1)


## Las telas del barco activo (las que saben describirse para el visor).
static func telas(arbol: SceneTree) -> Array:
	var b := barco(arbol)
	var l := []
	if b == null:
		return l
	for v in b.get_children():
		if v.has_method("datos_depuracion"):
			l.append(v)
	return l


## Estiramiento de un paño: {medio, peor, malas, peor_m}, en tanto por uno salvo `peor_m` (m).
##
## Se mide en el reloj de la FÍSICA porque los puntos libres del `SoftBody` solo cambian en los
## pasos de física mientras las anclas se mueven en `_process`: leyendo desde el render se
## comparan dos instantes distintos y el resultado alterna entre dos valores muy separados.
static func estiramiento(arbol: SceneTree, tela: Node) -> Dictionary:
	await arbol.physics_frame
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return {}
	var cuerpo: SoftBody3D = d["cuerpo"]
	var ar: PackedInt32Array = d["aristas"]
	var l0: PackedFloat32Array = d["largo0"]
	var suma := 0.0
	var peor := 0.0
	var peor_m := 0.0
	var malas := 0
	for e in l0.size():
		var largo: float = cuerpo.get_point_transform(ar[e * 2]).distance_to(
			cuerpo.get_point_transform(ar[e * 2 + 1]))
		var f: float = absf(largo - l0[e]) / maxf(l0[e], 0.0001)
		suma += f
		peor = maxf(peor, f)
		peor_m = maxf(peor_m, absf(largo - l0[e]))
		if f > 0.25:
			malas += 1
	return {
		"medio": suma / maxf(l0.size(), 1),
		"peor": peor,
		"peor_m": peor_m,
		"malas": malas,
		"recogiendo": d.get("recogiendo", false),
	}


## Cuánto ONDEA un paño: {medio, peor}, en metros.
##
## Es la desviación típica TEMPORAL de cada punto libre respecto al centroide de sus anclajes,
## promediada sobre los puntos. Un paño inmóvil da cero por muy hinchado que esté, que es justo
## lo que hay que distinguir de "no ondea".
##
## En ejes del BARCO: en ejes de mundo lo que se mide es el bamboleo del casco, que es un orden
## de magnitud mayor que el movimiento del paño.
static func ondeo(arbol: SceneTree, tela: Node, segundos := 8.0) -> Dictionary:
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return {}
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var b := barco(arbol)
	var libres: Array[int] = []
	for i in fijo.size():
		if fijo[i] == 0:
			libres.append(i)
	var suma: Array[Vector3] = []
	var suma2: PackedFloat32Array = PackedFloat32Array()
	suma.resize(libres.size()); suma2.resize(libres.size())
	for k in libres.size():
		suma[k] = Vector3.ZERO; suma2[k] = 0.0
	var n := 0
	var t := 0.0
	while t < segundos:
		await arbol.physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var inv := b.global_transform.affine_inverse()
		var anc := Vector3.ZERO
		var na := 0
		for i in fijo.size():
			if fijo[i] == 1:
				anc += inv * cuerpo.get_point_transform(i); na += 1
		anc /= float(maxi(na, 1))
		for k in libres.size():
			var q := (inv * cuerpo.get_point_transform(libres[k])) - anc
			suma[k] += q
			suma2[k] += q.length_squared()
		n += 1
	var total := 0.0
	var peor := 0.0
	for k in libres.size():
		var media: Vector3 = suma[k] / float(n)
		# var(x)+var(y)+var(z) = E[|q|²] - |E[q]|²
		var v: float = maxf(suma2[k] / float(n) - media.length_squared(), 0.0)
		total += sqrt(v)
		peor = maxf(peor, sqrt(v))
	return {"medio": total / maxf(libres.size(), 1), "peor": peor}


## Dirección MEDIA del vuelo de un paño (del centroide de sus anclas al de sus puntos libres),
## en horizontal y promediada en el tiempo. Promediada porque un paño que flamea cruza su
## dirección de equilibrio a cada momento.
static func vuelo_medio(arbol: SceneTree, tela: Node, segundos := 3.0) -> Vector3:
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return Vector3.ZERO
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var suma := Vector3.ZERO
	var n := 0
	var t := 0.0
	while t < segundos:
		await arbol.physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var anc := Vector3.ZERO
		var na := 0
		var lej := Vector3.ZERO
		var nl := 0
		for i in fijo.size():
			var p: Vector3 = cuerpo.get_point_transform(i)
			if fijo[i] == 1:
				anc += p; na += 1
			else:
				lej += p; nl += 1
		if na == 0 or nl == 0:
			continue
		var v := (lej / float(nl)) - (anc / float(na))
		v.y = 0.0
		if v.length() > 0.01:
			suma += v.normalized(); n += 1
	return (suma / maxf(n, 1)).normalized() if n > 0 else Vector3.ZERO


## Mete timón hasta virar `grados` (positivo = a estribor) y lo suelta. Devuelve lo que viró.
##
## Con la tecla, no llamando al método: así la prueba cubre también el cableado del gobierno.
static func virar(arbol: SceneTree, grados := 90.0, tope := 12.0) -> float:
	var b := barco(arbol)
	if b == null:
		return 0.0
	var r0 := _rumbo(b)
	var k := KEY_D if grados > 0.0 else KEY_A
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var t := 0.0
	while absf(wrapf(_rumbo(b) - r0, -180.0, 180.0)) < absf(grados) and t < tope:
		b.set("anclado", false)
		t += arbol.root.get_process_delta_time()
		await arbol.process_frame
	e.pressed = false
	Input.parse_input_event(e)
	return absf(wrapf(_rumbo(b) - r0, -180.0, 180.0))


static func _rumbo(b: Node3D) -> float:
	var f := -b.global_transform.basis.z
	return rad_to_deg(atan2(f.x, f.z))


## Largo MEDIO del vuelo de un paño, en metros: del centroide de sus anclas al de sus puntos
## libres. Un paño que se queda flojo o enrollado se ACORTA, y eso el ángulo no lo ve.
static func largo_del_vuelo(arbol: SceneTree, tela: Node, segundos := 2.0) -> float:
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return 0.0
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var suma := 0.0
	var n := 0
	var t := 0.0
	while t < segundos:
		await arbol.physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var anc := Vector3.ZERO
		var na := 0
		var lej := Vector3.ZERO
		var nl := 0
		for i in fijo.size():
			var p: Vector3 = cuerpo.get_point_transform(i)
			if fijo[i] == 1:
				anc += p; na += 1
			else:
				lej += p; nl += 1
		if na == 0 or nl == 0:
			continue
		suma += ((lej / float(nl)) - (anc / float(na))).length()
		n += 1
	return suma / maxf(n, 1)


## Cuánto se abre la COSTURA de un paño: las aristas que unen un punto anclado con uno libre.
## Devuelve {medio, peor} en METROS.
##
## En metros y no en porcentaje porque el porcentaje engaña: una arista de reposo corta se pone
## al 240 % con dos centímetros y no se ve. Y es LA medida que faltaba — todo lo demás se medía
## con el barco anclado, y esto solo aparece navegando.
static func costura(arbol: SceneTree, tela: Node, segundos := 1.5) -> Dictionary:
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return {"medio": 0.0, "peor": 0.0}
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var ar: PackedInt32Array = d["aristas"]
	var l0s: PackedFloat32Array = d["largo0"]
	var suma := 0.0
	var peor := 0.0
	var n := 0
	var t := 0.0
	while t < segundos:
		await arbol.physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		for e in l0s.size():
			var a: int = ar[e * 2]
			var b: int = ar[e * 2 + 1]
			if fijo[a] == fijo[b]:
				continue
			var l0: float = l0s[e]
			if l0 < 1e-6:
				continue
			var dm := cuerpo.get_point_transform(a).distance_to(cuerpo.get_point_transform(b)) - l0
			suma += absf(dm)
			peor = maxf(peor, dm)
			n += 1
	return {"medio": suma / maxf(n, 1), "peor": peor}


## Cuánto DESTACA el pico de movimiento de un paño sobre su fondo: máximo partido por mediana.
##
## Es la cifra que distingue un "latido" —picos aislados sobre una tela por lo demás tranquila—
## de un flameo, donde el paño se mueve todo el rato y el pico no destaca. Un espectro no vale
## para esto: dice a qué ritmo pasa algo, no si es un golpe o un vaivén.
static func relieve_del_pico(arbol: SceneTree, tela: Node, segundos := 20.0) -> float:
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return 0.0
	var cuerpo: SoftBody3D = d["cuerpo"]
	var _n_puntos: int = (d["fijo"] as PackedByteArray).size()
	var b := barco(arbol)
	var movs: Array[float] = []
	var prev := PackedVector3Array()
	var t := 0.0
	while t < segundos:
		await arbol.physics_frame
		var delta := 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		t += delta
		var inv := b.global_transform.affine_inverse()
		# Muestreo derivado del tamaño REAL del paño, nunca con paso fijo: un `i * 5` sobre 200
		# muestras llegaba al índice 995, que valía con los 1.217 puntos de la mayor y se salió
		# al bajarla a 613. `get_point_transform` fuera de rango no aborta: devuelve cero y
		# escribe un error por muestra y por frame, y la prueba pasó de 75 s a más de 280.
		var n_pts := _n_puntos
		var muestras: int = mini(200, n_pts)
		var paso: int = maxi(1, n_pts / maxi(muestras, 1))
		var ps := PackedVector3Array()
		ps.resize(muestras)
		for i in muestras:
			ps[i] = inv * cuerpo.get_point_transform(mini(i * paso, n_pts - 1))
		if prev.size() == ps.size():
			var mov := 0.0
			for i in ps.size():
				mov = maxf(mov, ps[i].distance_to(prev[i]))
			movs.append(mov / delta)
		prev = ps
	if movs.size() < 10:
		return 0.0
	movs.sort()
	var mediana: float = movs[movs.size() / 2]
	return movs[movs.size() - 1] / maxf(mediana, 1e-6)


## Cuántos puntos LIBRES de un paño se han metido dentro del palo del que cuelga, y a qué
## distancia del eje llegó el más hondo. Devuelve {puntos, mas_cerca} en unidades y metros.
##
## Es la medida del ENROLLADO, el defecto que sacó a la bandera de la física en septiembre de
## 2026: al virar, el hueso lleva el gratil alrededor del mástil, la lona libre va con retraso y
## termina al otro lado del palo. Una vez envuelta no sale, porque el conflicto es TOPOLÓGICO —
## hay tela al otro lado tirando— y ninguna fuerza lo deshace.
##
## Solo cuenta los puntos LIBRES: las anclas de esta bandera van cosidas a 54,8 mm del eje, o
## sea que ellas SIEMPRE están dentro del radio de prueba y contarlas daría 11 de fondo.
##
## `puntos` es el PEOR frame de la ventana, no la media: el enrollado o pasa o no pasa, y
## promediarlo con los frames buenos lo diluye hasta que no se ve.
static func puntos_en_el_palo(arbol: SceneTree, tela: Node, hueso := "giro_bandera",
		radio := 0.1, segundos := 1.0) -> Dictionary:
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return {"puntos": 0, "mas_cerca": INF}
	var cuerpo: SoftBody3D = d["cuerpo"]
	var skel: Skeleton3D = d["skel"]
	var fijo: PackedByteArray = d["fijo"]
	var b := skel.find_bone(hueso)
	if b < 0:
		return {"puntos": 0, "mas_cerca": INF}
	# El eje sale del REPOSO del hueso y no de su pose: la bandera gira ALREDEDOR de ese eje, así
	# que la pose no lo mueve, y el reposo no depende del instante en que se lea.
	var g := skel.global_transform * skel.get_bone_global_rest(b)
	var o := g.origin
	var u := g.basis.y.normalized()
	var peor := 0
	var cerca := INF
	var t := 0.0
	while t < segundos:
		await arbol.physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var n := 0
		for i in fijo.size():
			if fijo[i] == 1:
				continue
			var v: Vector3 = cuerpo.get_point_transform(i) - o
			var dist := (v - u * v.dot(u)).length()
			if dist < radio:
				n += 1
				cerca = minf(cerca, dist)
		peor = maxi(peor, n)
	return {"puntos": peor, "mas_cerca": cerca}


## Cuánto se separa cada punto ANCLADO de SU nodo de anclaje: {medio, peor} en metros.
##
## Es la línea magenta de la vista 1 del visor, y debería ser cero: el nodo de anclaje es hijo
## del `Skeleton3D` y viaja rígido con el barco, así que el punto clavado a él no tiene por qué
## quedarse atrás nunca.
##
## **Hay que fijar los FPS para que esto discrimine.** El desfase sale de que las anclas se
## recolocan una vez por FRAME y la física da varios pasos entre frame y frame; si el frame dura
## lo mismo que el paso —lo que pasa en esta máquina con vsync a 120 Hz y la escena vacía— hay
## un paso por frame y la medida da 0,0 mm con el defecto dentro.
static func retraso_anclas(arbol: SceneTree, tela: Node, fps := 60, segundos := 1.5) -> Dictionary:
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return {"medio": 0.0, "peor": 0.0}
	var cuerpo: SoftBody3D = d["cuerpo"]
	var anclas: Array[Node3D] = d["anclas"]
	var fijo: PackedByteArray = d["fijo"]
	var antes := Engine.max_fps
	Engine.max_fps = fps
	var suma := 0.0
	var peor := 0.0
	var n := 0
	var t := 0.0
	while t < segundos:
		await arbol.physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var s := 0.0
		var na := 0
		for k in fijo.size():
			if fijo[k] == 0:
				continue
			var e := cuerpo.get_point_transform(k).distance_to(anclas[k].global_position)
			s += e
			peor = maxf(peor, e)
			na += 1
		if na > 0:
			suma += s / float(na)
			n += 1
	Engine.max_fps = antes
	return {"medio": suma / maxf(n, 1), "peor": peor}


## Lo que dice el SHADER del oleaje en unos puntos del mundo, en metros.
##
## `modo`: 0 = altura, 1 = arrastre en x, 2 = arrastre en z, 3 = normal.y.
##
## Es la única forma de leer una función de shader desde código —lo que el vertex shader hace
## con la malla del agua no se puede consultar—, y hace falta porque la altura de la mar está
## escrita dos veces: en `oleaje.gdshaderinc` y en el autoload `Oleaje`. Si divergen, el barco
## flota sobre olas distintas de las que se ven y nada lo avisa: ni error, ni aviso, solo un
## casco que sube cuando el agua baja.
##
## El reloj se pasa a mano y NO se toma de `Oleaje.t`: entre la llamada y el render pasan dos
## frames, y comparar la altura de dos instantes distintos daría error donde no lo hay.
const ESPEJO_MUESTRAS := 64
const ESPEJO_RANGO := 16.0

static func oleaje_del_shader(arbol: SceneTree, puntos: PackedVector2Array,
		modo := 0) -> PackedFloat32Array:
	var ps := PackedVector2Array(puntos)
	ps.resize(ESPEJO_MUESTRAS)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tools/espejo_oleaje.gdshader")
	# Los coeficientes los pone el propio Oleaje: lo que se compara es la FÓRMULA, no que
	# alguien haya copiado bien los números a mano.
	Oleaje.aplicar(mat)
	mat.set_shader_parameter("puntos", ps)
	mat.set_shader_parameter("modo", modo)
	var vp := SubViewport.new()
	vp.size = Vector2i(ESPEJO_MUESTRAS, 1)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rect := ColorRect.new()
	rect.size = Vector2(ESPEJO_MUESTRAS, 1)
	rect.material = mat
	vp.add_child(rect)
	arbol.root.add_child(vp)
	# Dos vueltas: en la primera el render target se está creando y sale en negro.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var salida := PackedFloat32Array()
	for i in puntos.size():
		var c := img.get_pixel(mini(i, ESPEJO_MUESTRAS - 1), 0)
		# 16 bits: el rojo lleva el paso grande y el verde lo divide en otros 255.
		var v := (roundf(c.r * 255.0) + roundf(c.g * 255.0) / 255.0) / 255.0
		salida.append((v - 0.5) * ESPEJO_RANGO)
	vp.queue_free()
	return salida

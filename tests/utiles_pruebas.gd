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


## Deja al jugador al TIMÓN. Con el personaje en cubierta, A, D y S lo mueven a él y no al barco,
## así que todo escenario que gobierne o maniobre con teclas empieza por aquí.
static func al_timon(arbol: SceneTree) -> void:
	var b := barco(arbol)
	if b == null or bool(b.get("gobierno")):
		return
	await tecla(arbol, KEY_F)
	for i in 90:
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
		modo := 0, dist := 0.0, huella := 0.01, estela: Estela = null) -> PackedFloat32Array:
	var ps := PackedVector2Array(puntos)
	ps.resize(ESPEJO_MUESTRAS)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://tools/espejo_oleaje.gdshader")
	# Los coeficientes los pone el propio Oleaje: lo que se compara es la FÓRMULA, no que
	# alguien haya copiado bien los números a mano.
	Oleaje.aplicar(mat)
	mat.set_shader_parameter("puntos", ps)
	mat.set_shader_parameter("modo", modo)
	mat.set_shader_parameter("dist", dist)
	mat.set_shader_parameter("huella", huella)
	if estela != null:
		estela.aplicar(mat)
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


## Cuánto paño ha pasado al otro lado de los obenques: {pasados, total, az_vela, az_obenque}.
##
## La vela de cangreja y los obenques nacen del MISMO eje —el mástil—, así que basta comparar
## azimutes alrededor de ese eje: si el paño gira más que el obenque de popa de su banda, los
## dos se cruzan necesariamente, y eso es lo que se ve como la jarcia atravesando la lona. Medir
## distancias punto a cabo no distingue "roza" de "la atraviesa entera"; el azimut sí.
##
## Todo en ejes del BARCO. Los ángulos salen en grados, positivos a estribor.
static func vela_en_jarcia(arbol: SceneTree, barco: Node3D, tela: Node) -> Dictionary:
	await arbol.physics_frame
	var d: Dictionary = tela.datos_depuracion()
	var apa: Resource = tela.get("aparejo")
	if d.is_empty() or apa == null:
		return {}
	var skel: Skeleton3D = null
	for n in barco.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	var h := skel.find_bone(String(apa.get("trimado_hueso"))) if skel != null else -1
	if h < 0:
		return {}
	var al_barco := barco.global_transform.affine_inverse() * skel.global_transform
	var rest := skel.get_bone_global_rest(h)
	var origen := al_barco * rest.origin
	var eje := (al_barco.basis * rest.basis.y).normalized()
	var popa := (Vector3(0, 0, 1) - eje * eje.z).normalized()
	var lat := (Vector3(1, 0, 0) - eje * eje.x).normalized()
	var az := func(p: Vector3) -> float:
		var q := p - origen
		q -= eje * q.dot(eje)
		return rad_to_deg(atan2(q.dot(lat), q.dot(popa)))

	# El obenque que topa primero es el de POPA de cada banda: el de menor azimut.
	var az_ob := {-1.0: 180.0, 1.0: 180.0}
	for mi in barco.find_children("obenque*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var tr := al_barco * _hasta(m, skel)
		# El extremo de la MESA, que es el que se separa del palo; arriba el cabo muere en el
		# tope del mástil, donde el azimut no significa nada porque el radio es cero.
		var bajo := Vector3.INF
		for v in (m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var p: Vector3 = tr * v
			if p.y < bajo.y:
				bajo = p
		var a: float = az.call(bajo)
		var banda: float = signf(a)
		if absf(a) < absf(az_ob[banda]):
			az_ob[banda] = a

	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var suma := 0.0
	var azs := PackedFloat32Array()
	for i in fijo.size():
		var p := barco.global_transform.affine_inverse() * cuerpo.get_point_transform(i)
		var a: float = az.call(p)
		azs.append(a)
		suma += a
	var medio := suma / maxf(azs.size(), 1)
	var banda: float = signf(medio)
	var limite: float = az_ob[banda]
	var pasados := 0
	for a in azs:
		if signf(a) == banda and absf(a) > absf(limite):
			pasados += 1
	return {
		"pasados": pasados,
		"total": azs.size(),
		"az_vela": medio,
		"az_obenque": limite,
	}


## Cuántas caras de la lona ATRAVIESA cada obenque: {cruces, por_cabo}.
##
## Es el defecto tal como se ve —el cabo saliendo por el medio del paño— y no lo mismo que
## `vela_en_jarcia()`. El azimut cuenta como "pasado" todo punto que gire más que el obenque,
## incluido el paño que está por FUERA del cabo y solo se ha doblado al apoyarse en él: con la
## lona descansando en la jarcia ese número no baja, y aquí sí tiene que dar cero.
##
## El cabo se toma como el segmento entre su vértice más bajo y el más alto: es recto y tiene
## 1,5 cm de radio, así que su eje es él. Se cruza con cada triángulo del `SoftBody`, cuyos
## puntos son los vértices de su propia malla soldada.
static func jarcia_por_la_lona(arbol: SceneTree, barco: Node3D, tela: Node,
		patron := "obenque*") -> Dictionary:
	await arbol.physics_frame
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return {}
	var cuerpo: SoftBody3D = d["cuerpo"]
	var idx: PackedInt32Array = cuerpo.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var n := (cuerpo.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var p := PackedVector3Array()
	p.resize(n)
	for i in n:
		p[i] = cuerpo.get_point_transform(i)
	var por_cabo := {}
	var cruces := 0
	for mi in barco.find_children(patron, "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var bajo := Vector3(0.0, INF, 0.0)
		var alto := Vector3(0.0, -INF, 0.0)
		for v in (m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var g: Vector3 = m.global_transform * v
			if g.y < bajo.y:
				bajo = g
			if g.y > alto.y:
				alto = g
		var k := 0
		for t in range(0, idx.size(), 3):
			if Geometry3D.segment_intersects_triangle(bajo, alto,
					p[idx[t]], p[idx[t + 1]], p[idx[t + 2]]) != null:
				k += 1
		if k > 0:
			por_cabo[String(m.name)] = k
		cruces += k
	return {"cruces": cruces, "por_cabo": por_cabo}


## Cómo está la lona respecto a los MUROS de detrás de los obenques (`Lona_*` de
## `perchas_solidas`): {dentro, hondo, cerca}. `dentro` son los puntos libres metidos en algún
## muro, `hondo` cuánto se mete el más metido y `cerca` lo más que se acerca un punto a la cara
## del muro (negativo si está dentro), todo en metros.
##
## Sirve para saber si una prueba de la jarcia llega a TOCAR el muro: fondeado con el viento de
## 160° la mayor pasa del obenque por azimut y no lo roza (`cerca` de varios centímetros), así que
## un cero de caras atravesadas ahí no dice nada del muro.
static func lona_en_muros(arbol: SceneTree, barco: Node3D, tela: Node) -> Dictionary:
	await arbol.physics_frame
	var d: Dictionary = tela.datos_depuracion()
	if d.is_empty():
		return {}
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var muros := []
	for c in barco.find_children("Lona_*", "StaticBody3D", true, false):
		var cs := c.get_child(0) as CollisionShape3D
		var cap := cs.shape as CapsuleShape3D
		muros.append([(c as Node3D).global_transform * cs.transform, cap.radius,
			maxf(cap.height * 0.5 - cap.radius, 0.0)])
	var dentro := 0
	var cerca := INF
	for i in fijo.size():
		if fijo[i] == 1:
			continue
		var p := cuerpo.get_point_transform(i)
		var mia := INF
		for m in muros:
			var q: Vector3 = (m[0] as Transform3D).affine_inverse() * p
			mia = minf(mia, q.distance_to(Vector3(0.0, clampf(q.y, -m[2], m[2]), 0.0)) - float(m[1]))
		if mia < 0.0:
			dentro += 1
		cerca = minf(cerca, mia)
	return {"dentro": dentro, "hondo": maxf(-cerca, 0.0), "cerca": cerca, "muros": muros.size()}


static func _hasta(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D()
	var x: Node = n
	while x != null and x != raiz:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


## Cuánto TIEMBLAN el casco y sus telas: segunda diferencia RMS por paso de física, en metros.
##
## {casco, libre, anclada, estir, malas} y, si se pasa `al_paso`, también el tirón en los tres
## pasos que rodean a ese paso (`casco_pico`, `tela_pico`) contra el peor del resto de la serie
## (`casco_resto`, `tela_resto`). `accion` se llama justo antes de esperar ese paso.
##
## La segunda diferencia y no la posición porque lo que delata la precisión simple es la
## ACELERACIÓN: a 50 km un `float` solo distingue pasos de 3,9 mm, así que cada paso el casco y
## cada punto del paño caen en esa rejilla. Un bamboleo de medio metro cada cinco segundos da
## 0,2 mm de segunda diferencia a 60 Hz; la rejilla, milímetros.
##
## Las restas van en DOBLE (los `float` de GDScript son de 64 bits) sobre valores que ya vienen
## cuantizados del motor, y restar dos `float` cercanos es exacto: lo que se mide es el temblor
## del motor, no el de la medida. La tela, en ejes del BARCO: en ejes de mundo saldría el
## bamboleo del casco. Y la resta va ANTES del giro, o el error de 50 km se mezcla en el giro.
static func temblor(arbol: SceneTree, b: Node3D, pasos: int, al_paso := -1,
		accion := Callable()) -> Dictionary:
	var ts := telas(arbol).filter(func(t): return not (t.datos_depuracion() as Dictionary).is_empty())
	var casco: Array = []
	var puntos := {}
	for tela in ts:
		puntos[tela] = []
	# El casco, en ABSOLUTO si hay origen flotante: un recentrado corre su posición local
	# kilómetros, y eso no es un tirón.
	var origen := arbol.root.get_node_or_null("Origen")
	for paso in pasos:
		if paso == al_paso and accion.is_valid():
			accion.call()
		await arbol.physics_frame
		var o := _dobles(b.global_position)
		var oa := o.duplicate()
		if origen != null:
			oa[0] += float(origen.x)
			oa[2] += float(origen.z)
		casco.append(oa)
		var inv := b.global_transform.basis.inverse()
		for tela in ts:
			var d: Dictionary = tela.datos_depuracion()
			var cuerpo: SoftBody3D = d["cuerpo"]
			var n: int = (d["fijo"] as PackedByteArray).size()
			var fila := PackedFloat64Array()
			fila.resize(n * 3)
			for k in n:
				var p := _dobles(cuerpo.get_point_transform(k))
				var rel := inv * Vector3(p[0] - o[0], p[1] - o[1], p[2] - o[2])
				fila[k * 3] = rel.x
				fila[k * 3 + 1] = rel.y
				fila[k * 3 + 2] = rel.z
			puntos[tela].append(fila)
	var r := {"casco": _rms2(casco, 0, 1), "libre": 0.0, "anclada": 0.0, "estir": 0.0, "malas": 0}
	var nl := 0
	var na := 0
	for tela in ts:
		var d: Dictionary = tela.datos_depuracion()
		var fijo: PackedByteArray = d["fijo"]
		var filas: Array = puntos[tela]
		for k in fijo.size():
			var v := _rms2(filas, k, 3)
			if fijo[k] == 1:
				r["anclada"] += v
				na += 1
			else:
				r["libre"] += v
				nl += 1
		var e: Dictionary = await estiramiento(arbol, tela)
		r["estir"] = maxf(r["estir"], e.get("medio", 0.0))
		r["malas"] += int(e.get("malas", 0))
	r["libre"] /= maxf(nl, 1)
	r["anclada"] /= maxf(na, 1)
	if al_paso >= 2 and al_paso + 1 < pasos:
		for clave in ["casco_pico", "casco_resto", "tela_pico", "tela_resto"]:
			r[clave] = 0.0
		for i in range(1, pasos - 1):
			var cerca := absi(i - al_paso) <= 1
			var c := _d2(casco, 0, 1, i)
			r["casco_pico" if cerca else "casco_resto"] = maxf(
				r["casco_pico" if cerca else "casco_resto"], c)
			for tela in ts:
				var filas: Array = puntos[tela]
				var np: int = (filas[0] as PackedFloat64Array).size() / 3
				for k in np:
					var v := _d2(filas, k, 3, i)
					r["tela_pico" if cerca else "tela_resto"] = maxf(
						r["tela_pico" if cerca else "tela_resto"], v)
	return r


static func _dobles(v: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([float(v.x), float(v.y), float(v.z)])


## Módulo de la segunda diferencia de la serie en el paso `i`.
static func _d2(serie: Array, k: int, ancho: int, i: int) -> float:
	var s := 0.0
	for c in 3:
		var a: float = serie[i - 1][k * ancho + c]
		var m: float = serie[i][k * ancho + c]
		var z: float = serie[i + 1][k * ancho + c]
		s += pow(z - 2.0 * m + a, 2.0)
	return sqrt(s)


static func _rms2(serie: Array, k: int, ancho: int) -> float:
	var s := 0.0
	var n := 0
	for i in range(1, serie.size() - 1):
		s += pow(_d2(serie, k, ancho, i), 2.0)
		n += 1
	return sqrt(s / maxf(n, 1))

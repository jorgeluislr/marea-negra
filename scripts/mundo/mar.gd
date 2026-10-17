extends MeshInstance3D
## Gestiona el mar: malla del agua, shader de olas, estela del barco y recorte del casco.
## Encuentra el barco por el grupo "barco_activo" (sin rutas fijas), así funciona con
## cualquier embarcación instanciada o cambiada en runtime. Lee la forma del recorte
## de los parámetros del propio barco.
##
## **La malla se GENERA aquí, no viene de la escena.** El `PlaneMesh` que había eran cuatro
## vértices en las esquinas, a 250 m: el shader tenía sus olas desde el principio y no se veían
## nunca porque no había con qué dibujarlas. Y una rejilla uniforme fina tampoco vale — mallar
## 800 × 800 m a medio metro son 2,5 millones de cuadros para que se vean cuatro junto al
## barco.
##
## La rejilla que se construye es uniforme en un parámetro y se estira al llevarla al mundo, de
## forma que la celda crece al alejarse: 0,55 m junto a la cámara y 6,4 m en el borde, con la
## misma cuenta de vértices en todas partes. No hay costuras porque es una sola rejilla, no
## anillos encajados.
##
## **Es un DISCO, no un cuadrado**, porque un cuadrado enseña sus esquinas: subiendo la cámara
## se veía el borde del agua y, más allá, el azul plano con que el cielo pinta por debajo del
## horizonte. La rejilla cuadrada se lleva al disco con el mapeo elíptico
## (`x·√(1−y²/2)`, `y·√(1−x²/2)`), que manda el borde del cuadrado EXACTAMENTE a la
## circunferencia y no deja ningún vértice degenerado en el centro, como sí haría una rejilla
## polar —donde todos los radios se juntarían en un punto.
##
## **Y el detalle no se puede estirar hasta el horizonte: son dos mallas.** Subir el radio del
## disco fino de 400 a 1500 m hunde el primer plano de 8,85 puntos por ola a 4,9, porque la
## cuenta de vértices es la misma y hay que repartirla entre veinte veces más superficie. El
## disco se queda en su radio y un FALDÓN plano lo prolonga hasta el horizonte: donde empieza,
## el LOD ya ha apagado hasta la ola más larga, así que es agua lisa, empalma sin costura y no
## gasta casi nada (128 × 16 cuadros para 20 km).

@export_group("Malla")
## Hasta dónde llega el agua, en metros. Más allá se ve el cielo, que en el horizonte pinta el
## mismo color.
@export var radio := 1200.0
## Celdas por lado. El coste va con el cuadrado: 512 son 262.144 cuadros.
@export var resolucion := 512
## Tamaño de celda junto a la cámara, en metros. De aquí sale el estirado, y no al revés: lo
## que hay que fijar es esto —la ola más corta mide 7 m y necesita ocho puntos— y dejar que la
## celda crezca sola hacia el borde.
@export var celda_cerca := 0.62
## Hasta dónde llega el faldón plano que prolonga el agua, en metros. El horizonte de verdad
## está a 4,7 km desde cubierta y a 19,6 desde 30 m de altura, de ahí los 20.000.
@export var radio_lejano := 20000.0
## Sectores y anillos del faldón. No necesita más: es agua lisa y lo único que se le pide es no
## acabarse antes que la vista.
@export var faldon_sectores := 128
@export var faldon_anillos := 16
@export_group("")

@export var barco_path: NodePath  # opcional: respaldo si no hay nada en el grupo


var _mat: ShaderMaterial
var _barco: Node3D
var _paso_fino := 0.0
var _t0 := 0
var _trozos := 0
## El rastro del barco activo, que dibuja la estela. Ver `Estela`.
var _rastro := Estela.new()
## De qué barco es el rastro: al cambiar de barco con TAB empieza uno nuevo.
var _barco_del_rastro: Node3D = null


func _ready() -> void:
	add_to_group("mar")
	# Primero un disco BASTO, que cuesta un milisegundo: así hay agua desde el primer frame.
	# El fino viene después, cuando las telas del barco ya se hayan montado; ver `_a_su_tiempo()`.
	_construir_malla(RESOLUCION_PROVISIONAL)
	_poner_faldon()
	_a_su_tiempo()
	# Sin esto el agua desaparece a ratos: el motor descarta lo que no toca el frustum usando la
	# caja de la malla SIN deformar, y la ola saca los vértices de ella.
	custom_aabb = AABB(Vector3(-radio, -30.0, -radio), Vector3(radio * 2.0, 60.0, radio * 2.0))
	# Un plano de 800 m proyectando sombra sobre sí mismo no aporta nada y cuesta.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# La lámina de este mundo no está en el cero (está en −0,882), y quien pregunte la altura de
	# una ola la quiere en coordenadas de mundo, no relativa a un plano que no ve.
	Oleaje.nivel = global_position.y
	_fijar_alcances()
	_mat = material_override as ShaderMaterial
	if _mat == null:
		_mat = get_active_material(0) as ShaderMaterial
	if _mat == null:
		push_warning("mar.gd: el agua no tiene un ShaderMaterial (agua.gdshader).")
	var o := get_node_or_null("/root/Origen")
	if o != null:
		o.recentrado.connect(_al_recentrar)


## El mundo se ha corrido `-d` (origen flotante): el rastro de la estela guarda posiciones de mundo
## y se corre con él. La malla no hace falta, que se recoloca sola en `_seguir_a_la_camara()`.
func _al_recentrar(d: Vector3) -> void:
	_rastro.desplazar(Vector2(d.x, d.z))


func _barco_activo() -> Node3D:
	if _barco == null or not is_instance_valid(_barco):
		_barco = get_tree().get_first_node_in_group("barco_activo") as Node3D
		if _barco == null and barco_path != NodePath():
			_barco = get_node_or_null(barco_path) as Node3D
	return _barco


func _process(delta: float) -> void:
	if _mat == null:
		return
	# El oleaje lo publica SIEMPRE el autoload, nunca se escriben estos uniformes a mano: el mar
	# que se ve y el que responde `Oleaje.altura_en()` tienen que salir de los mismos números.
	Oleaje.aplicar(_mat)
	_mat.set_shader_parameter("radio_tierra",
		Horizonte.radio_tierra if Horizonte.activa else 1e12)
	_seguir_a_la_camara()

	var barco := _barco_activo()
	_seguir_el_rastro(barco, delta)
	if barco:
		# Recorte del agua: la caja de la BODEGA del barco, en sus ejes, y su matriz inversa para
		# llevar cada fragmento allí. Sin bodega declarada no se recorta —mejor ver el mar dentro
		# que abrir un agujero donde no toca—, y hoy eso es el caso de la lancha, la barca y la
		# goleta, por las que además no se anda.
		var caja: Array = barco.caja_recorte()
		_mat.set_shader_parameter("recorte_activo", bool(barco.recorta_el_agua) and caja.size() == 2)
		if caja.size() == 2:
			_mat.set_shader_parameter("barco_inv", barco.global_transform.affine_inverse())
			_mat.set_shader_parameter("recorte_min", caja[0])
			_mat.set_shader_parameter("recorte_max", caja[1])
	else:
		_mat.set_shader_parameter("recorte_activo", false)

	_rastro.aplicar(_mat)


## Lleva el rastro del barco activo: su centro y su proa en planta, y la silueta de su casco en
## la flotación —medida de la malla por el propio barco—, que es lo que da la forma a la estela.
func _seguir_el_rastro(barco: Node3D, delta: float) -> void:
	if barco != _barco_del_rastro:
		_barco_del_rastro = barco
		_rastro.vaciar()
		if barco != null and barco.has_method("silueta_de_flotacion"):
			var sil: Dictionary = barco.silueta_de_flotacion()
			if not sil.is_empty():
				_rastro.fijar_casco(sil["ancho"], sil["lo"], sil["hi"])
	if barco == null:
		return
	var g := barco.global_transform
	var proa := Vector2(-g.basis.z.x, -g.basis.z.z)
	_rastro.registrar(Vector2(g.origin.x, g.origin.z), proa, delta)


## La malla persigue a la cámara para que el detalle esté siempre donde se mira.
##
## En saltos de una celda fina, no continuo: moviéndola libremente los vértices se deslizan
## sobre la ola —que vive en coordenadas de mundo y no se entera— y la superficie parece hervir.
## Saltando de celda en celda cada vértice cae donde caía el anterior y no se nota nada.
##
## La rejilla se cuenta en coordenadas ABSOLUTAS (`Origen`), en doble precisión: contada en las
## locales, un recentrado que no fuera múltiplo de la celda dejaría los vértices a media celda de
## donde estaban y el mar herviría ese frame.
func _seguir_a_la_camara() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _paso_fino <= 0.0:
		return
	var c := cam.global_position
	var o := get_node_or_null("/root/Origen")
	var ox: float = o.x if o != null else 0.0
	var oz: float = o.z if o != null else 0.0
	global_position.x = snappedf(float(c.x) + ox, _paso_fino) - ox
	global_position.z = snappedf(float(c.z) + oz, _paso_fino) - oz


## Monta el disco fino cuando el barco ya tiene sus telas, no antes.
##
## Un `SoftBody3D` que nace en un frame lento sale roto, y construir esta malla es lo más caro
## que pasa en el arranque, así que el mar se aparta y deja nacer primero: con el disco basto
## desde el frame 0 hay agua igual, y el fino entra sobre el frame 31, cuando los tres paños ya
## están montados (5, 6 y 7). Medido con `tools/tirones_del_arranque.tscn`.
##
## Que quede claro lo que esto NO arregla: la arista suelta del foque es intermitente y es de
## antes de que hubiera mar (ver la nota del foque en CLAUDE.md).
##
## Espera a que ningún paño del barco esté pendiente, con un tope por si no hay barco ninguno
## (una herramienta de medida, una escena suelta).
func _a_su_tiempo() -> void:
	var t := 0.0
	# Tope corto: los paños nacen sobre el frame 7 y lo que se está esquivando dura menos de un
	# segundo. Con un tope largo, cualquier escena sin telas —una herramienta de medida— se pasa
	# ese tiempo con el disco basto puesto y mide OTRO mar: la primera vez dio 0,52 puntos por
	# ola donde el fino da 8,3.
	while t < 1.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		var b := get_tree().get_first_node_in_group("barco_activo")
		if b == null:
			continue
		var faltan := false
		for h in b.get_children():
			if h.has_method("datos_depuracion") and (h.datos_depuracion() as Dictionary).is_empty():
				faltan = true
		if not faltan:
			# Y todavía un margen: el paño no solo tiene que estar montado, tiene que haberse
			# ASENTADO. Construir la malla buena mete unos milisegundos en cada uno de la treintena
			# de frames que dura, y cayendo sobre los primeros pasos del solver la mayor se abrió
			# **99 aristas** por encima del 25 % con 12 cm de costura, naciendo en un frame
			# perfectamente normal de 0,013 s — o sea que no era el tirón del parto, era lo de
			# después.
			await get_tree().create_timer(MARGEN_ASENTADO).timeout
			break
	await _construir_malla(resolucion)


## Le dice al oleaje entre qué distancias tiene que apagar cada tren con ESTA malla.
##
## Una ola de 7 m sobre celdas de 3 no sale como ola: sale como un encaje de escamas regulares
## que hierve al mover la cámara, y no se parece en nada a la ola porque es el patrón de
## interferencia entre la ola y la rejilla. Hay que apagarla, y lo que se decide aquí es
## **dónde empieza y dónde acaba** ese apagado.
##
## Son dos distancias porque con una sola el degradado sale corto y se ve la juntura entre el
## mar con olas y el mar liso — lo dijo el usuario mirándolo, y el número le daba la razón: las
## olas morían a 380 m y el horizonte está a 1,6 km, o sea más de un kilómetro de agua lisa.
## El tren empieza a perder amplitud donde la celda ya solo le da `PUNTOS_BUENOS` por ola y
## termina apagado donde le da `PUNTOS_MIN`: un degradado largo y atado a lo que la malla puede
## dibujar, no a un número puesto a ojo.
const PUNTOS_BUENOS := 8.0
const PUNTOS_MIN := 3.0

func _fijar_alcances() -> void:
	var a := PackedVector2Array()
	for largo in Oleaje.LARGOS:
		# Acotado al borde del disco: más allá empieza el faldón, que es plano, y una ola viva en
		# la juntura se vería como un escalón recorriendo el mar.
		var fin := minf(_alcance_para(float(largo), PUNTOS_MIN), radio * 0.95)
		a.append(Vector2(minf(_alcance_para(float(largo), PUNTOS_BUENOS), fin * 0.9), fin))
	Oleaje.alcances = a
	print("mar: cada tren se apaga entre %s m" % [a])


## A qué distancia la celda de la malla deja de tener `puntos` puntos por ola. Por bisección
## sobre el parámetro de la rejilla, porque el estirado no se invierte a mano.
func _alcance_para(largo: float, puntos: float) -> float:
	var objetivo := largo / puntos
	var du := 2.0 / float(resolucion)
	var r := _reparto()
	var lo := 0.0
	var hi := 1.0
	for _i in 40:
		var u := (lo + hi) * 0.5
		# Derivada del estirado por el paso del parámetro: el tamaño de celda ahí.
		if radio * (r + (1.0 - r) * 3.0 * u * u) * du < objetivo:
			lo = u
		else:
			hi = u
	return _estirar(lo)


## Cuántos milisegundos como mucho se pasa construyendo la malla en un frame.
##
## Montar el disco entero de una vez cuesta 54 ms con 320 × 320 (y 140 con 512 × 512) en un solo
## frame, y ese frame cae **justo donde nacen las telas**: un `SoftBody3D` que se crea durante un
## tirón sale roto y el solver no cierra esas aristas nunca (ver `TelaFisica` y la nota del
## arranque en CLAUDE.md). Medido: con el disco de golpe el foque daba 2, 1, 1 aristas pasadas
## del 25 % en tres tiradas contra un tope de 1; con el mar viejo, 1, 1, 1.
##
## En MILISEGUNDOS y no en filas: por filas hay que reajustarlo cada vez que cambia la
## resolución —al pasar de 320 a 512 el trozo se encareció un 60 % sin que nada lo avisara— y
## además una máquina más lenta necesitaría otro número. Con un presupuesto de tiempo se
## reparte solo.
const MS_POR_FRAME := 5

## Resolución del disco PROVISIONAL, el que se monta en el primer frame. 48 × 48 cuesta menos de
## un milisegundo: hay agua desde el principio, con sus olas, solo que basta.
const RESOLUCION_PROVISIONAL := 48

## Segundos que se espera desde que el último paño se monta hasta empezar el disco fino.
const MARGEN_ASENTADO := 2.5


## Rejilla estirada y llevada al disco: uniforme en el parámetro, con la celda creciendo hacia
## fuera en el mundo.
func _construir_malla(res: int) -> void:
	_t0 = Time.get_ticks_msec()
	_trozos = 0
	var n := res + 1
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	vs.resize(n * n)
	ns.resize(n * n)
	var reloj := Time.get_ticks_msec()
	for j in n:
		# Una pausa en cuanto se agota el presupuesto: ver la nota de MS_POR_FRAME.
		if Time.get_ticks_msec() - reloj >= MS_POR_FRAME:
			_trozos += 1
			await get_tree().process_frame
			reloj = Time.get_ticks_msec()
		var b := 2.0 * float(j) / float(res) - 1.0
		for i in n:
			var a := 2.0 * float(i) / float(res) - 1.0
			# Cuadrado -> disco (mapeo elíptico). El borde del cuadrado cae EXACTAMENTE sobre la
			# circunferencia, así que el faldón empalma con él sin rendija.
			var x := a * sqrt(1.0 - b * b * 0.5)
			var y := b * sqrt(1.0 - a * a * 0.5)
			var u := sqrt(x * x + y * y)
			var f := _estirar(u) / u if u > 0.000001 else 0.0
			vs[j * n + i] = Vector3(x * f, 0.0, y * f)
			ns[j * n + i] = Vector3.UP
	var idx := PackedInt32Array()
	idx.resize(res * res * 6)
	var k := 0
	for j in res:
		for i in res:
			var a := j * n + i
			idx[k] = a; idx[k + 1] = a + 1; idx[k + 2] = a + n
			idx[k + 3] = a + 1; idx[k + 4] = a + n + 1; idx[k + 5] = a + n
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_paso_fino = _estirar(2.0 / float(res))
	mesh = m
	if res < resolucion:
		return
	print("mar: disco de %.0f m, %d x %d celdas, de %.2f m junto a la cámara a %.1f m en el borde"
		% [radio, res, res, _paso_fino,
			_estirar(1.0) - _estirar(1.0 - 2.0 / float(res))]
		+ "  (en %d trozos de %d ms)" % [_trozos + 1, MS_POR_FRAME])


## Faldón: el anillo plano que lleva el agua desde el borde del disco hasta el horizonte.
##
## Va como hijo y no como segunda superficie de la misma malla porque así hereda el movimiento
## del nodo sin más, y puede tener su propia caja de recorte —que es enorme— sin inflar la del
## disco fino.
func _poner_faldon() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Faldon"
	mi.mesh = _construir_faldon()
	mi.material_override = material_override
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-radio_lejano, -30.0, -radio_lejano),
		Vector3(radio_lejano * 2.0, 60.0, radio_lejano * 2.0))
	add_child(mi)


func _construir_faldon() -> ArrayMesh:
	# Los anillos crecen en progresión geométrica desde la celda del borde del disco: así el
	# primero casa de tamaño con lo que hay dentro y el último puede medir kilómetros.
	var primera := _estirar(1.0) - _estirar(1.0 - 2.0 / float(resolucion))
	var q := 1.0
	if radio_lejano > radio + primera:
		# q tal que primera·(q^anillos - 1)/(q - 1) cubra lo que falta. Por bisección.
		var falta := (radio_lejano - radio) / primera
		var lo := 1.0001
		var hi := 8.0
		for _i in 60:
			q = (lo + hi) * 0.5
			if (pow(q, faldon_anillos) - 1.0) / (q - 1.0) < falta:
				lo = q
			else:
				hi = q
	var radios := PackedFloat32Array([radio])
	var paso := primera
	for i in faldon_anillos:
		radios.append(radios[i] + paso)
		paso *= q
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	for r in radios:
		for sec in faldon_sectores:
			var ang := TAU * float(sec) / float(faldon_sectores)
			vs.append(Vector3(cos(ang) * r, 0.0, sin(ang) * r))
			ns.append(Vector3.UP)
	var idx := PackedInt32Array()
	for i in faldon_anillos:
		for sec in faldon_sectores:
			var s2 := (sec + 1) % faldon_sectores
			var a := i * faldon_sectores + sec
			var b := i * faldon_sectores + s2
			var c := (i + 1) * faldon_sectores + sec
			var d := (i + 1) * faldon_sectores + s2
			# Ojo al orden: el del disco no vale copiado. Allí las dos direcciones de la rejilla
			# son x y z; aquí son la angular y la radial, y ese cambio invierte la orientación
			# de las caras. Con el orden del disco el faldón queda mirando hacia abajo y
			# desaparece entero —no se ve ni pintándolo de rojo, que es como se encontró.
			idx.append_array([a, c, b, b, c, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	print("mar: faldón de %.0f a %.0f m en %d anillos (el último de %.0f m)"
		% [radio, radios[radios.size() - 1], faldon_anillos,
			radios[radios.size() - 1] - radios[radios.size() - 2]])
	return m


## Lleva un radio de 0 a 1 a la distancia en metros. Mezcla una parte lineal (que fija el tamaño
## de la celda del centro) con un cubo (que la hace crecer hacia el borde).
func _estirar(u: float) -> float:
	var a := clampf(absf(u), 0.0, 1.0)
	var r := _reparto()
	return radio * (r * a + (1.0 - r) * a * a * a)


## Qué fracción del estirado va en la parte lineal. Sale de `celda_cerca`: junto al centro el
## estirado es casi recto, así que la celda de allí vale `radio · reparto · 2/resolucion`.
func _reparto() -> float:
	return clampf(celda_cerca * float(resolucion) / (2.0 * radio), 0.01, 1.0)

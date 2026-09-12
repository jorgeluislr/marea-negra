class_name Barco
extends CharacterBody3D

## Barco de vela. Propulsión por viento; el jugador lleva el timón (A/D) y gestiona
## las velas y el ancla:
##   · Tecla W → abrir/cerrar vela DELANTERA
##   · Tecla S → abrir/cerrar vela TRASERA
##   · ESPACIO → soltar/levar ANCLA (detiene el barco)
##   · Tecla F → alternar entre gobernar y andar por cubierta
## Las velas afectan a la propulsión (superficie abierta) y al giro (balance de velas).
## Cada acción emite una SEÑAL para engancharle animación más adelante.
##
## Lo que es PROPIO del barco vive aquí, no en scripts-nodo sueltos colgados de la escena:
## el timón (antes `control_timon.gd`), los colisionadores por los que se anda en cubierta
## (antes `colisiones_barco.gd`) y el cambio barco ↔ a pie (antes `paseo_cubierta.gd`).
## Las diferencias entre embarcaciones van en subclases (`Balandra extends Barco`).

signal vela_delantera_cambiada(abierta: bool)
signal vela_trasera_cambiada(abierta: bool)
signal ancla_cambiada(anclada: bool)

# ── Navegación ───────────────────────────────────────────────────────────────
@export var velocidad_max := 12.0
@export var aceleracion := 4.0
@export var velocidad_giro := 1.0
@export_range(0.0, 1.0) var giro_minimo := 0.2
@export var angulo_muerto := 45.0
@export var angulo_optimo := 100.0
@export_range(0.0, 1.0) var empuje_delantera := 0.4   # propulsión que aporta la vela delantera
@export_range(0.0, 1.0) var empuje_trasera := 0.6     # propulsión que aporta la vela trasera
@export var sesgo_giro_velas := 0.5                    # giro por balance de velas (rad/s a plena vela)
@export var nombre := "Barco"                          # nombre para el HUD/selector
@export var altura_flotacion := 1.74                   # Y a la que flota (línea de cubierta sobre el agua)
@export var recorte_radio := Vector2(1.0, 2.0)         # semiejes del recorte del casco (manga, eslora)
@export var recorte_proa_exp := 0.8                    # forma de la proa en el recorte del agua
@export var recorte_popa_exp := 0.4                    # forma de la popa en el recorte del agua

# ── Timón ────────────────────────────────────────────────────────────────────
## Gira el hueso del timón según la ENTRADA del jugador, no según el giro real del casco:
## así la caña responde al instante aunque el barco esté parado o anclado, que es lo que se
## ve en la realidad. No-op si el barco no lleva ese hueso riggeado.
@export_group("Timón")
@export var timon_hueso := "timon"
@export_range(0.0, 60.0) var timon_angulo_max := 35.0   ## Grados máximos a cada banda.
@export var timon_eje := Vector3(0, 1, 0)               ## Eje LOCAL del hueso sobre el que gira.
@export var timon_invertir := false                     ## Invierte el sentido del giro.
@export_range(0.5, 20.0) var timon_suavizado := 6.0     ## Rapidez con que la caña sigue a la entrada.

# ── Andar por cubierta ───────────────────────────────────────────────────────
@export_group("Cubierta")
@export var tecla_paseo := KEY_F
## Se deja vacío y se carga al bajar a cubierta por primera vez: con un `preload` aquí,
## los cuatro barcos de la flota traen el personaje en memoria desde el arranque.
@export var escena_jugador: PackedScene
@export var ruta_jugador := "res://scenes/character/player.tscn"
@export var altura_capsula := 0.9                       ## Media altura de la cápsula, para no nacer hundido.
@export var camara_path: NodePath = ^"CamaraNav"        ## Cámara de gobierno a la que se vuelve.

# ── Colisionadores de cubierta ───────────────────────────────────────────────
## Se generan en runtime a partir de las propias mallas del modelo, así que valen para
## cualquier casco de la flota sin volver a medir a mano:
##
##  - Las mallas de `colision_mallas_suelo` se convierten en colisionadores de malla
##    (trimesh). Son pocas caras (la cubierta de la balandra tiene 50) y así el suelo sigue
##    exactamente al modelo, incluidas las cubiertas de proa y popa a distinta altura.
##  - Del casco se saca la línea de regala muestreándolo por secciones a lo largo de su eje
##    largo: por cada sección se busca su punto más alto y la manga a esa altura. Con eso se
##    levantan dos cadenas de cajas por banda, una para la borda (con su cara superior a la
##    altura de la regala, así que se puede subir y andar por ella) y otra invisible por
##    encima que impide caerse por fuera.
##  - En cada sección se busca además la altura de cubierta cerca de la crujía (el punto más
##    alto por debajo de la regala) y se pone suelo donde la malla de cubierta no llega: en la
##    balandra el panel central cubre 9 m de los 12 y las cubiertas de proa y popa son del
##    propio casco, a otra altura.
##  - Y se cierran los dos extremos con una barrera transversal, porque ahí la regala se
##    junta y no hay banda que levantar: sin ellas se sale andando por la proa (medido).
##
## El casco NO se convierte en trimesh a propósito: son 23.930 triángulos y el barco se
## mueve, así que la forma tendría que reubicarse en el árbol de colisiones cada frame.
## Cajas cuesta una fracción de eso y para andar por cubierta dan igual de bien.
##
## Con `colision_casco` vacío no se monta nada: los barcos por los que aún no se anda
## (lancha, barca, goleta) no pagan el muestreo ni avisan de mallas que no tienen.
@export_group("Colisiones de cubierta")
@export var colision_casco := ""
@export var colision_mallas_suelo: Array[String] = []
@export_range(4, 40) var colision_secciones := 16
@export var colision_grueso_borda := 0.14   ## Grueso de la cadena de cajas de la borda.
@export var colision_alto_barrera := 1.6    ## Cuánto sube la barrera invisible sobre la regala.
@export var colision_margen_barrera := 0.02 ## Cuánto se separa hacia fuera, para no pisarla.
## Capa 3: la caja del casco va en la 2 y llena el interior del barco, así que el personaje
## no puede compartir capa con ella o andaría 1,2 m por encima de la cubierta.
@export_flags_3d_physics var colision_capa := 4
@export var colision_dibujar := false       ## Poner a true para ver las cajas mientras se ajusta.

# ── Carga ────────────────────────────────────────────────────────────────────
## Bultos estibados en cubierta (barriles, cajas). Cada uno es un `Carga` con su modelo, su
## sitio y su giro; el barco los instancia al arrancar y los cuelga de sí mismo, así que
## navegan y cabecean con él.
##
## Antes venían soldados dentro del `.glb` del casco, y eso los hacía inamovibles: no se podían
## quitar, ni cambiar de sitio, ni reutilizar en otro barco. Lo que hay aquí es la lista; el
## dónde y el cómo los sabe cada `Carga`.
@export_group("Carga")
@export var cargamento: Array[Carga] = []

# ── Acabado de la madera ─────────────────────────────────────────────────────
## Devuelve a la madera el relieve fino que el `.glb` no transporta: en Blender lo genera un
## grupo de nodos triplanar, y glTF solo lleva imágenes. Ver `AcabadoMadera`.
##
## Es una LISTA porque no todas las piezas quieren la fibra en el mismo sentido: el tablado de
## cubierta y el forro del casco la llevan girada respecto a los palos y las perchas.
@export_group("Acabado")
@export var acabado_madera: Array[AcabadoMadera] = []

# ── Artillería ───────────────────────────────────────────────────────────────
## Las piezas que monta el barco, cada una con su sitio y su banda. Misma idea que
## `cargamento`: es una LISTA de datos, así que artillar más o menos es editarla, no
## tocar la lógica de tiro. Vacía, el barco no monta nada y no paga nada.
@export_group("Artillería")
@export var artilleria: Array[Artilleria] = []
## Altura de la lámina de agua: es donde acaba la parábola del tiro. Si se deja en INF se
## busca sola en la escena (el nodo del agua), que es lo que hace falta para que la misma
## balandra valga en el mundo y en una escena de pruebas con el mar a otra altura.
@export var altura_mar := INF
## Balas en la santabárbara. Cada disparo gasta una.
@export var municion := 60
@export_group("")

const BOB_AMPLITUDE := 0.15
const BOB_SPEED := 1.2

# Estado de las acciones (empieza navegando: ambas velas abiertas, sin anclar).
var vela_delantera := true
var vela_trasera := true
var anclado := false
## Con false el barco ignora el teclado: se pone al andar por cubierta, porque el personaje
## usa WASD para lo suyo y si no gobernarías el barco a la vez.
var gobierno := true

## Timón mandado, de -1 (todo a babor) a +1 (todo a estribor). Lo escribe QUIEN GOBIERNA —el
## mando del jugador o un capitán de IA— y lo leen el casco y la caña. El barco NO lee el
## teclado: `Input.is_key_pressed` es global, así que con dos barcos en el agua los dos
## obedecían la misma tecla. Medido antes del cambio: dos balandras giraban +26,21° las dos,
## idénticos a la centésima, que es la firma de estar leyendo la misma entrada.
var orden_timon := 0.0:
	set(v):
		orden_timon = clampf(v, -1.0, 1.0)

var velocidad := 0.0
var time := 0.0
var base_y := 0.0

var _skel: Skeleton3D
var _timon_idx := -1
var _timon_reposo := Quaternion.IDENTITY
var _timon_angulo := 0.0

var _jugador: CharacterBody3D
var _andando := false
var _cuerpo_colisiones: StaticBody3D
## Las velas de este barco. Se recogen entre los HIJOS DIRECTOS, por el método que responden
## (`izar`), no por su tipo: al barco le da igual que una vela sea de tela física o de shader
## mientras sepa izarse. Solo hijos directos, no una búsqueda recursiva: las velas son piezas
## del barco puestas en su escena, no algo que aparezca en cualquier rincón del modelo.
var _velas: Array[Node] = []
var _canones: Array[Canon] = []
## Batería apuntada: "estribor", "babor", "proa" o "popa". Es la que dispara.
var banda_apuntada := "estribor"
## Con true están vivos los controles de artillería y se dibuja la guía. Lo enciende quien
## gobierna (el mando del jugador con B, o un capitán de IA cuando decide entrar en combate).
var modo_battle := false
## Línea de regala que deja `_montar_colisiones`, reaprovechada para saber a qué altura
## pasa la borda bajo cada pieza: es lo que decide si el tiro es a barbeta o por porta.
var _regala_centros: Array[float] = []
var _regala_altos: Array[float] = []
var _regala_eslora_z := true
## Alto del barco en metros, medido de sus mallas. Decide cuándo se ha hundido del todo tras el
## horizonte.
var _alto := 0.0

@onready var helm_position: Marker3D = $HelmPosition
@onready var camara: Camera3D = _buscar_camara()



## Y a la que va el casco: su altura de flotación, el bamboleo, y la CURVATURA de la Tierra.
##
## La curvatura es lo que hace que un barco lejano se hunda de abajo arriba —primero el casco,
## después las velas, el tope del palo lo último—, que es como desaparece un barco de verdad; y
## es la misma que hunde el agua en `agua.gdshader`, así que el casco y su mar bajan juntos. Si
## solo se curvase el agua, un barco lejano quedaría flotando por encima de ella.
##
## Se resta al BARCO y no a su modelo para que la arboladura y los paños bajen con él: las velas
## son `SoftBody3D` en espacio de mundo y van donde vayan sus anclas, que cuelgan del esqueleto.
##
## Sobre el barco del jugador no hace nada, y no por un caso especial: la cámara lo acompaña, su
## distancia es de metros y la caída va con el CUADRADO de ella — a 100 m son ocho décimas de
## milímetro.
func _altura_de_flotacion() -> float:
	var y := base_y + sin(time * BOB_SPEED) * BOB_AMPLITUDE
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return y
	var hundido := Horizonte.caida_entre(global_position, cam.global_position)
	# Cuando ni el tope del palo asoma ya no hay nada que dibujar. Sin esto el barco seguiría
	# ahí abajo, gastando y asomando por los reflejos.
	if _alto > 0.0:
		visible = hundido < _alto
	return y - hundido


## Alto del barco, del casco al tope, medido de sus mallas. Diferido porque el modelo se
## instancia con la escena, y saltando los `SoftBody3D`: un paño físico vive en espacio de mundo
## y su caja no dice nada de lo que mide el barco.
func _medir_alto() -> void:
	var bajo := INF
	var alto := -INF
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi is SoftBody3D or mi.mesh == null or not mi.is_inside_tree():
			continue
		var caja := mi.get_aabb()
		var t := global_transform.affine_inverse() * mi.global_transform
		for k in 8:
			var y: float = (t * caja.get_endpoint(k)).y
			bajo = minf(bajo, y)
			alto = maxf(alto, y)
	if alto > bajo:
		_alto = alto - bajo


func _ready() -> void:
	# Cada barco flota a SU altura (una balandra grande no flota igual que la lancha).
	position.y = altura_flotacion
	base_y = altura_flotacion
	# NO se anuncia solo como el del jugador. Lo hacía en su `_ready`, y con eso el segundo
	# barco de la escena se declaraba "activo": el mar, el HUD, la cámara y las flechas de
	# viento se iban con el enemigo. Quién es el barco del jugador lo decide quien le sube el
	# jugador a bordo — `tomar_mando_jugador()`.
	_medir_alto.call_deferred()
	_preparar_timon()
	for h in get_children():
		if h.has_method("izar"):
			_velas.append(h)
		if h.has_method("configurar"):
			h.configurar(self)
	# Diferido, y por dos razones distintas: las mallas del .glb no están en el árbol hasta
	# después de este _ready (colisiones), y las velas se montan ellas también en diferido, así
	# que la primera orden tiene que ir detrás de su montaje.
	if colision_casco != "":
		_montar_colisiones.call_deferred()
	if not cargamento.is_empty():
		_montar_carga.call_deferred()
	if not acabado_madera.is_empty():
		_montar_acabado.call_deferred()
	if not artilleria.is_empty():
		_montar_artilleria.call_deferred()
	_mandar_velas.call_deferred(true)


## El barco ya no lee teclas de maniobra ni de artillería: eso es de quien gobierna
## (`MandoJugador` o un capitán de IA). Aquí queda solo el cambio timón ↔ cubierta, que es del
## barco porque es él quien instancia al personaje y le da sitio en `HelmPosition`.
func _unhandled_input(event: InputEvent) -> void:
	if not is_in_group("barco_activo"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == tecla_paseo:
			alternar_modo()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_mover_timon(delta)
	# Si el personaje desaparece (por ejemplo al cambiar de barco con TAB), volver al timón.
	if _andando and (_jugador == null or not is_instance_valid(_jugador)):
		_a_gobernar()


func _physics_process(delta: float) -> void:
	time += delta

	if anclado:
		# Anclado: frena y se queda quieto (solo el balanceo del oleaje). No gira ni avanza.
		velocidad = move_toward(velocidad, 0.0, aceleracion * 3.0 * delta)
		velocity = -transform.basis.z * velocidad
		move_and_slide()
		position.y = _altura_de_flotacion()
		return

	# Timón: eficacia según la velocidad (más rápido = gira mejor).
	var giro := orden_timon
	var vel_norm := clampf(absf(velocidad) / maxf(0.01, velocidad_max), 0.0, 1.0)
	var giro_efectivo := velocidad_giro * (giro_minimo + (1.0 - giro_minimo) * vel_norm)
	rotate_y(giro * giro_efectivo * delta)

	# Sesgo de giro por balance de velas (trasera → orza; delantera → arriba).
	_aplicar_sesgo_velas(vel_norm, delta)

	# Propulsión: viento × ángulo × superficie de vela abierta.
	var objetivo := velocidad_max * factor_viento() * Viento.fuerza * _factor_velas()
	velocidad = move_toward(velocidad, objetivo, aceleracion * delta)

	velocity = -transform.basis.z * velocidad
	move_and_slide()
	position.y = _altura_de_flotacion()


# ── Acciones (con señal para animar más adelante) ────────────────────────────
func set_vela_delantera(v: bool) -> void:
	if vela_delantera == v:
		return
	vela_delantera = v
	vela_delantera_cambiada.emit(v)
	_mandar_velas()
	print("Vela delantera: ", "abierta" if v else "cerrada")


func set_vela_trasera(v: bool) -> void:
	if vela_trasera == v:
		return
	vela_trasera = v
	vela_trasera_cambiada.emit(v)
	_mandar_velas()
	print("Vela trasera: ", "abierta" if v else "cerrada")


func set_ancla(v: bool) -> void:
	if anclado == v:
		return
	anclado = v
	ancla_cambiada.emit(v)
	print("Ancla: ", "soltada (detenido)" if v else "levada")


## Da la orden a cada vela según el estado de su puesto en el aparejo. El barco decide QUÉ
## velas van abiertas —eso es cosa suya: sabe cuál es la de proa y cuál la de popa— y la vela
## decide CÓMO se iza: qué drizas mueve, cuánto recorren y cuándo recoge el paño.
func _mandar_velas(inmediato := false) -> void:
	for v in _velas:
		var abierta := vela_trasera
		match int(v.get("mando")):
			0:
				abierta = vela_delantera
			2:
				abierta = vela_delantera or vela_trasera
		if abierta:
			v.izar(inmediato)
		else:
			v.arriar(inmediato)


# ── Física de vela ───────────────────────────────────────────────────────────
# Superficie de vela abierta → cuánto propulsa (0 = todo cerrado; ~1 = todo abierto).
func _factor_velas() -> float:
	var f := 0.0
	if vela_delantera:
		f += empuje_delantera
	if vela_trasera:
		f += empuje_trasera
	return f


# La trasera abierta tiende a ORZAR (girar hacia el viento); la delantera a ARRIBAR
# (girar en contra). Con ambas se equilibra. Escala con la velocidad (el giro es
# consecuencia del movimiento).
func _aplicar_sesgo_velas(vel_norm: float, delta: float) -> void:
	var s := 0.0
	if vela_trasera:
		s -= 1.0   # popa → ORZA (gira hacia el viento)
	if vela_delantera:
		s += 1.0   # proa → ARRIBA (aleja del viento; ayuda a salir de la zona muerta)
	if absf(s) < 0.001 or vel_norm < 0.001:
		return
	var wind := Viento.direccion
	wind.y = 0.0
	if wind.length() < 0.001:
		return
	var src := (-wind).normalized()   # de dónde viene el viento
	var bow := -transform.basis.z
	bow.y = 0.0
	if bow.length() < 0.001:
		return
	bow = bow.normalized()
	# Ángulo con signo de la proa hacia el origen del viento.
	var ang := atan2(bow.x * src.z - bow.z * src.x, bow.dot(src))
	rotate_y(clampf(ang, -1.0, 1.0) * s * sesgo_giro_velas * vel_norm * delta)


## Factor de propulsión [0..1] según el ángulo entre la proa y el viento. Público porque no
## solo lo usa la propulsión: el audio saca de él la cadencia del flameo (cuánto viento NO está
## aprovechando la vela).
## Propulsión [0..1] con el rumbo ACTUAL.
func factor_viento() -> float:
	return factor_viento_en(-transform.basis.z)


## Propulsión [0..1] de un rumbo CUALQUIERA. Se pregunta al barco y no se calcula fuera porque
## la curva es del CASCO —su `angulo_muerto` y su `angulo_optimo`, 40° y 95° en la balandra— y
## quien se la recalcule por su cuenta acabará creyendo que ciñe más de lo que el barco ciñe.
## Misma razón por la que el tiro se decide con `Canon.punto_de_caida()` y no con una parábola
## propia.
func factor_viento_en(rumbo: Vector3) -> float:
	var wind := Viento.direccion
	wind.y = 0.0
	if wind.length() < 0.001:
		return 0.0
	wind = wind.normalized()
	var fwd := rumbo
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return 0.0
	fwd = fwd.normalized()
	var cos_ang := fwd.dot(-wind)
	var cos_muerto := cos(deg_to_rad(angulo_muerto))
	var cos_optimo := cos(deg_to_rad(angulo_optimo))
	var t := clampf((cos_muerto - cos_ang) / (cos_muerto - cos_optimo), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ── Timón ────────────────────────────────────────────────────────────────────
# Eje: el hueso apunta hacia arriba siguiendo el codaste, así que la pala barre girando
# sobre su propio eje (Y local), igual que el hueso 'vela'.
func _preparar_timon() -> void:
	_skel = _buscar_skeleton(self)
	if _skel == null:
		return
	_timon_idx = _skel.find_bone(timon_hueso)
	if _timon_idx >= 0:
		_timon_reposo = _skel.get_bone_rest(_timon_idx).basis.get_rotation_quaternion()


func _mover_timon(delta: float) -> void:
	if _timon_idx < 0:
		return   # este barco no lleva timón riggeado
	# Mismas teclas que el giro del casco (A = babor, D = estribor). El signo va al revés
	# que allí: con la orientación del hueso, la pala tiene que caer a la misma banda hacia
	# la que vira el barco.
	# Andando por cubierta el barco no lee el teclado: la caña vuelve al centro en vez de
	# responder a las teclas de andar del personaje.
	# El signo va al revés que en el casco: con la orientación del hueso, la pala cae a la
	# misma banda hacia la que vira el barco.
	var giro := -orden_timon
	if timon_invertir:
		giro = -giro
	var objetivo := giro * deg_to_rad(timon_angulo_max)

	# Seguimiento suave: la caña va y vuelve al centro sin saltos.
	_timon_angulo = lerpf(_timon_angulo, objetivo, clampf(timon_suavizado * delta, 0.0, 1.0))
	_skel.set_bone_pose_rotation(_timon_idx, _timon_reposo * Quaternion(timon_eje.normalized(), _timon_angulo))


# ── Modo: gobernar ↔ andar por cubierta ──────────────────────────────────────
## Al pasar a andar, el personaje se instancia como HIJO del barco: así el barco lo lleva
## consigo cuando navega y cabecea, que es lo que un CharacterBody3D en espacio de mundo no
## hace solo. Aparece en `HelmPosition`, que es donde estaría el timonel.
## Necesita los colisionadores de cubierta: sin ellos no hay cubierta que pisar.
func alternar_modo() -> void:
	if _andando:
		_a_gobernar()
	else:
		_a_andar()


func _a_andar() -> void:
	if escena_jugador == null:
		escena_jugador = load(ruta_jugador) as PackedScene
	if escena_jugador == null:
		push_warning("%s: sin escena de personaje ('%s')" % [nombre, ruta_jugador])
		return
	_jugador = escena_jugador.instantiate() as CharacterBody3D
	add_child(_jugador)
	var base: Vector3 = helm_position.position if helm_position != null else Vector3(0, 2.0, 0)
	_jugador.position = base + Vector3.UP * altura_capsula
	var cam := _jugador.find_children("*", "Camera3D", true, false)
	if not cam.is_empty():
		(cam[0] as Camera3D).make_current()
	gobierno = false
	_andando = true
	print("%s: a cubierta, en %v (pulsa %s para volver al timón)"
		% [nombre, _jugador.position, OS.get_keycode_string(tecla_paseo)])


func _a_gobernar() -> void:
	if _jugador != null and is_instance_valid(_jugador):
		_jugador.queue_free()
	_jugador = null
	gobierno = true
	if camara != null:
		camara.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_andando = false


# ── Colisionadores de cubierta ───────────────────────────────────────────────
func _montar_colisiones() -> void:
	_cuerpo_colisiones = StaticBody3D.new()
	_cuerpo_colisiones.name = "Colisiones"
	_cuerpo_colisiones.collision_layer = colision_capa
	_cuerpo_colisiones.collision_mask = 0
	add_child(_cuerpo_colisiones)

	# --- suelos: la malla tal cual
	var suelos := 0
	for nombre_malla in colision_mallas_suelo:
		var mi := _malla(nombre_malla)
		if mi == null or mi.mesh == null:
			push_warning("%s: no encuentro la malla de suelo '%s'" % [nombre, nombre_malla])
			continue
		var cs := CollisionShape3D.new()
		cs.name = "Suelo_" + nombre_malla
		cs.shape = mi.mesh.create_trimesh_shape()
		cs.transform = _relativo(mi)
		_cuerpo_colisiones.add_child(cs)
		suelos += mi.mesh.get_faces().size() / 3

	# --- casco: línea de regala por secciones
	var casco := _malla(colision_casco)
	if casco == null or casco.mesh == null:
		push_warning("%s: no encuentro el casco '%s'" % [nombre, colision_casco])
		return
	var tr := _relativo(casco)
	var vs: PackedVector3Array = casco.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var ps := PackedVector3Array()
	ps.resize(vs.size())
	var lo := Vector3.INF; var hi := -Vector3.INF
	for i in vs.size():
		var p := tr * vs[i]
		ps[i] = p
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	# Eje largo del casco (eslora) y eje transversal (manga), en el espacio del barco.
	var tam := hi - lo
	var eslora_z: bool = tam.z >= tam.x
	var largo: float = tam.z if eslora_z else tam.x
	var paso := largo / float(colision_secciones)
	var a0: float = lo.z if eslora_z else lo.x

	var hechas := 0
	var altos: Array[float] = []
	var mangas: Array[float] = []
	var centros: Array[float] = []
	var cubiertas: Array[float] = []
	for s in colision_secciones:
		var c := a0 + paso * (float(s) + 0.5)
		var alto := -INF
		for i in ps.size():
			var p := ps[i]
			var u: float = p.z if eslora_z else p.x
			if absf(u - c) <= paso * 0.5 and p.y > alto:
				alto = p.y
		if alto == -INF:
			continue
		var manga := 0.0
		for i in ps.size():
			var p := ps[i]
			var u: float = p.z if eslora_z else p.x
			if absf(u - c) <= paso * 0.5 and p.y > alto - 0.15:
				var lat: float = absf(p.x) if eslora_z else absf(p.z)
				manga = maxf(manga, lat)
		# Altura de cubierta: lo más alto por debajo de la regala y cerca de la crujía.
		var cub := -INF
		for i in ps.size():
			var p := ps[i]
			var u: float = p.z if eslora_z else p.x
			if absf(u - c) > paso * 0.5:
				continue
			var lat2: float = absf(p.x) if eslora_z else absf(p.z)
			if lat2 < manga * 0.6 and p.y < alto - 0.20 and p.y > cub:
				cub = p.y
		centros.append(c)
		altos.append(alto)
		mangas.append(manga)
		cubiertas.append(cub if cub != -INF else alto)
		hechas += 1
	_regala_centros = centros.duplicate()
	_regala_altos = altos.duplicate()
	_regala_eslora_z = eslora_z

	# --- borda (se puede pisar) y barrera invisible por encima
	var suelo_y: float = lo.y
	var mi_cub := _malla(colision_mallas_suelo[0]) if not colision_mallas_suelo.is_empty() else null
	if mi_cub != null and mi_cub.mesh != null:
		suelo_y = (_relativo(mi_cub) * mi_cub.mesh.get_aabb()).position.y
	# Rango que ya cubre la malla de cubierta: fuera de ahí hay que poner suelo.
	var cub_min := INF; var cub_max := -INF
	if mi_cub != null and mi_cub.mesh != null:
		var ab := _relativo(mi_cub) * mi_cub.mesh.get_aabb()
		cub_min = ab.position.z if eslora_z else ab.position.x
		cub_max = cub_min + (ab.size.z if eslora_z else ab.size.x)
	for i in hechas:
		var c: float = centros[i]
		var alto: float = altos[i]
		var manga: float = mangas[i]
		# Suelo donde la malla de cubierta no llega (proa y popa del casco).
		if (c < cub_min or c > cub_max) and manga > colision_grueso_borda:
			var y_cub: float = cubiertas[i]
			var ancho: float = maxf(manga * 2.0 - colision_grueso_borda, 0.2)
			var pos_s := Vector3(0.0, y_cub - 0.05, c) if eslora_z else Vector3(c, y_cub - 0.05, 0.0)
			var tam_s := Vector3(ancho, 0.10, paso) if eslora_z else Vector3(paso, 0.10, ancho)
			_caja(pos_s, tam_s, Basis(), "SueloCasco_%d" % i)
		if manga < colision_grueso_borda:
			continue          # proa y popa: la regala se cierra, no hay banda que levantar
		for lado in [-1.0, 1.0]:
			var lat: float = (manga - colision_grueso_borda * 0.5) * lado
			var pos_borda := Vector3(lat, (alto + suelo_y) * 0.5, c) if eslora_z else Vector3(c, (alto + suelo_y) * 0.5, lat)
			var tam_borda := Vector3(colision_grueso_borda, maxf(alto - suelo_y, 0.05), paso) if eslora_z else Vector3(paso, maxf(alto - suelo_y, 0.05), colision_grueso_borda)
			_caja(pos_borda, tam_borda, Basis(), "Borda_%d_%s" % [i, "b" if lado < 0.0 else "e"])
			var lat2: float = (manga + colision_grueso_borda * 0.5 + colision_margen_barrera) * lado
			var pos_bar := Vector3(lat2, alto + colision_alto_barrera * 0.5, c) if eslora_z else Vector3(c, alto + colision_alto_barrera * 0.5, lat2)
			var tam_bar := Vector3(colision_grueso_borda, colision_alto_barrera, paso) if eslora_z else Vector3(paso, colision_alto_barrera, colision_grueso_borda)
			_caja(pos_bar, tam_bar, Basis(), "Barrera_%d_%s" % [i, "b" if lado < 0.0 else "e"])

	# --- tapones de proa y popa: sin ellos se sale andando por el extremo
	var extremos: Array[int] = []
	for i in hechas:
		if mangas[i] >= colision_grueso_borda:
			extremos.append(i)
	if extremos.size() >= 2:
		for i in [extremos[0], extremos[extremos.size() - 1]]:
			var c: float = centros[i]
			var alto: float = altos[i]
			var manga: float = mangas[i]
			var hacia: float = -1.0 if i == extremos[0] else 1.0
			var cc: float = c + hacia * paso * 0.5
			var y_cub: float = cubiertas[i]
			var h: float = alto + colision_alto_barrera - y_cub
			var pos_t := Vector3(0.0, y_cub + h * 0.5, cc) if eslora_z else Vector3(cc, y_cub + h * 0.5, 0.0)
			var tam_t := Vector3(manga * 2.0, h, colision_grueso_borda) if eslora_z else Vector3(colision_grueso_borda, h, manga * 2.0)
			_caja(pos_t, tam_t, Basis(), "Tapon_%s" % ("proa" if hacia < 0.0 else "popa"))

	print("%s: %d triangulos de suelo, %d secciones, %d cajas (eslora en %s, suelo y=%.2f)"
		% [nombre, suelos, hechas, _cuerpo_colisiones.get_child_count() - colision_mallas_suelo.size(),
			"z" if eslora_z else "x", suelo_y])


## Da a la madera del modelo su relieve. Diferido como todo lo que toca las mallas del `.glb`,
## que no están en el árbol hasta después de `_ready`.
func _montar_acabado() -> void:
	var total := 0
	var mats := 0
	for a in acabado_madera:
		if a == null:
			continue
		var hechos: Dictionary = a.aplicar(self)
		for k in hechos:
			total += int(hechos[k])
		mats += hechos.size()
	if total > 0:
		print("%s: relieve de madera en %d mallas (%d materiales)" % [nombre, total, mats])


## Instancia los bultos del `cargamento` y los cuelga del barco, dentro de un contenedor.
##
## El contenedor no lleva script: solo agrupa, para que la raíz del barco no se llene de
## barriles entre las velas y la cámara. Se cuelgan DEL BARCO (y no del nodo `Modelo`) por lo
## mismo que el jugador al andar por cubierta: así se mueven con el casco al navegar.
##
## Los bultos que no se puedan instanciar se saltan con un aviso; a un barco al que le falte
## un `.glb` de carga le sobra motivo para seguir navegando.
func _montar_carga() -> void:
	var contenedor := get_node_or_null(^"Cargamento") as Node3D
	if contenedor == null:
		contenedor = Node3D.new()
		contenedor.name = "Cargamento"
		add_child(contenedor)
	var puestos := 0
	for c in cargamento:
		if c == null:
			continue
		var bulto := c.instanciar(colision_capa)
		if bulto == null:
			continue
		contenedor.add_child(bulto)
		puestos += 1
	print("%s: %d bultos de carga de %d" % [nombre, puestos, cargamento.size()])


func _caja(centro: Vector3, tam: Vector3, base: Basis, nombre_caja: String) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = tam
	cs.shape = bx
	cs.name = nombre_caja
	cs.transform = Transform3D(base, centro)
	_cuerpo_colisiones.add_child(cs)
	if colision_dibujar:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = tam
		mi.mesh = bm
		mi.transform = cs.transform
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.3, 0.1, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		_cuerpo_colisiones.add_child(mi)


# ── Utilidades ───────────────────────────────────────────────────────────────
## Transform de un nodo respecto al barco, sin depender de global_transform.
func _relativo(n: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != self:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


func _malla(nombre_malla: String) -> MeshInstance3D:
	var l := find_children(nombre_malla, "MeshInstance3D", true, false)
	return l[0] as MeshInstance3D if not l.is_empty() else null


func _buscar_skeleton(raiz: Node) -> Skeleton3D:
	if raiz == null:
		return null
	for c in raiz.find_children("*", "Skeleton3D", true, false):
		return c as Skeleton3D
	return null


func _buscar_camara() -> Camera3D:
	var c := get_node_or_null(camara_path) as Camera3D
	if c != null:
		return c
	var l := find_children("*", "Camera3D", true, false)
	return l[0] as Camera3D if not l.is_empty() else null


func on_interact(_player: Node3D) -> void:
	# Punto de enganche para cuando el jugador suba al timón.
	print("El jugador subió al timón del barco.")


# ── Artillería ───────────────────────────────────────────────────────────────

## Instancia las piezas y las cuelga del barco, dentro de un contenedor, igual que la carga:
## del BARCO y no del nodo `Modelo`, para que naveguen y cabeceen con el casco.
func _montar_artilleria() -> void:
	var contenedor := get_node_or_null(^"Artilleria") as Node3D
	if contenedor == null:
		contenedor = Node3D.new()
		contenedor.name = "Artilleria"
		add_child(contenedor)
	_canones.clear()
	for a in artilleria:
		if a == null:
			continue
		var c := a.instanciar()
		c.altura_mar = _altura_del_mar()
		contenedor.add_child(c)
		_canones.append(c)
	if get_node_or_null(^"GuiaTiro") == null and not _canones.is_empty():
		var g := GuiaTiro.new()
		g.name = "GuiaTiro"
		add_child(g)
	print("%s: %d piezas de artillería (%d por banda)"
		% [nombre, _canones.size(), canones_de("estribor").size()])


## Las piezas de una banda. Se pregunta al cañón en vez de guardar dos listas: una sola fuente.
func canones_de(que_banda: String) -> Array[Canon]:
	var sale: Array[Canon] = []
	for c in _canones:
		if c.banda() == que_banda:
			sale.append(c)
	return sale


## Dispara la banda apuntada. Devuelve cuántas piezas llegaron a responder: las que estén
## recargando no salen, y eso es información para el HUD.
func disparar_banda() -> int:
	var salieron := 0
	for c in canones_de(banda_apuntada):
		if municion <= 0:
			break
		if c.disparar():
			salieron += 1
			municion -= 1
	return salieron


## Altura de la regala bajo un punto del mundo, interpolando la línea que se muestreó al
## levantar las colisiones. Sin colisiones montadas devuelve -INF, que es lo honesto: no se
## sabe, en vez de inventar un cero que pasaría por bueno en una comprobación.
func altura_regala_en(pos_global: Vector3) -> float:
	if _regala_centros.is_empty():
		return -INF
	var p := to_local(pos_global)
	var u: float = p.z if _regala_eslora_z else p.x
	var mejor := 0
	var dist := INF
	for i in _regala_centros.size():
		var d: float = absf(_regala_centros[i] - u)
		if d < dist:
			dist = d
			mejor = i
	# En GLOBAL: los altos se muestrearon en el espacio del barco y quien pregunta trae
	# posiciones del mundo. Devolverlo en local es comparar peras con manzanas.
	return to_global(Vector3(0.0, _regala_altos[mejor], 0.0)).y


## Banda apuntada y fuego. Van por `match` aparte y no dentro del de las velas para que la
## artillería no se mezcle con la maniobra: son dos cosas distintas y se leen mejor separadas.
## Elige a qué batería se apunta: "proa", "popa", "babor" o "estribor".
func apuntar(que_banda: String) -> void:
	if _canones.is_empty():
		return
	banda_apuntada = que_banda


## Puntería fina de la batería apuntada, EN GRADOS: `dgiro` mueve las piezas con el espeque y
## `delev` mete o saca la cuña. Se dan incrementos y no valores absolutos porque así sirve igual
## al ratón (que da movimiento relativo) y a un capitán de IA corrigiendo el tiro.
func apuntar_fino(dgiro: float, delev: float) -> void:
	for c in canones_de(banda_apuntada):
		c.giro_lateral = clampf(c.giro_lateral + dgiro, -15.0, 15.0)
		c.elevacion = clampf(c.elevacion + delev, -3.0, 12.0)


## Puntería de la batería apuntada, para el HUD: grados de espeque y de cuña, y el alcance que
## sale de ellos. Se lee de la PRIMERA pieza; van todas a la vez.
func punteria() -> Dictionary:
	var piezas := canones_de(banda_apuntada)
	if piezas.is_empty():
		return {}
	var p: Canon = piezas[0]
	return {"lateral": p.giro_lateral, "elevacion": p.elevacion,
		"alcance": p.punto_de_caida().distance_to(p.global_position),
		"listas": piezas.filter(func(x: Canon): return x.listo()).size(),
		"total": piezas.size()}


## Dónde está la lámina de agua. Con `altura_mar` puesto a mano manda ese valor; si no, se
## busca el agua en la escena por su grupo o por su nombre. Devolver 0 a ciegas haría que el
## tiro cayese donde no es en cuanto el mar no esté en el cero.
func _altura_del_mar() -> float:
	if is_finite(altura_mar):
		return altura_mar
	var agua := get_tree().get_first_node_in_group("mar") as Node3D
	if agua == null:
		var raiz := get_tree().current_scene
		if raiz != null:
			agua = raiz.find_child("Water", true, false) as Node3D
	if agua != null:
		return agua.global_position.y
	# Devolver 0 en silencio es lo que hace que una herramienta mida OTRO juego: en esta
	# balandra el mar está en −0,882, así que un cero deja la lámina medio metro por encima de
	# la boca y el alcance cae de 62,7 m a 41,9. Se avisa para que se ponga `altura_mar` a mano.
	push_warning("%s: no encuentro el agua; el tiro se calculará con el mar en 0. "
		% nombre + "Pon `altura_mar` a mano si el barco va en una escena sin mar.")
	return 0.0


## Le pone al barco el mando del JUGADOR: teclado y ratón traducidos a órdenes. Lo llama quien
## sabe que este barco es el del jugador —el `GestorBarcos` al instanciarlo, o una herramienta
## de pruebas—, nunca el barco por su cuenta: dos balandras instanciadas a mano entran las dos
## en el grupo "barco_activo", así que ese criterio no distingue.
func tomar_mando_jugador() -> MandoJugador:
	var ya := get_node_or_null(^"MandoJugador") as MandoJugador
	if ya != null:
		return ya
	var m := MandoJugador.new()
	m.name = "MandoJugador"
	add_child(m)
	# El grupo va con el mando: el barco del jugador es el que lleva jugador. Así el mar, el
	# HUD, la cámara y las flechas siguen encontrándolo sin rutas fijas, y ningún enemigo puede
	# reclamar el puesto por el mero hecho de existir.
	add_to_group("barco_activo")
	return m


## Quién lleva el timón, si es que alguien lo lleva. La guía de tiro lo usa para saber si debe
## dibujarse: sin nadie al mando no hay a quien enseñársela.
func hay_mando() -> bool:
	return get_node_or_null(^"MandoJugador") != null

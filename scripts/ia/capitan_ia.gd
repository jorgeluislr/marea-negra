class_name CapitanIA
extends Node

## Quien manda un barco cuando no lo manda una persona. Se cuelga como HIJO del barco y le da
## las mismas órdenes que le daría el jugador: `orden_timon`, las velas, el ancla, la banda
## apuntada y el fuego.
##
## Que sea intercambiable con el jugador es el punto entero de la clase, y es lo que decidió el
## usuario el 11 de septiembre de 2026: **los controles del barco viven en quien lo manda, no en
## el barco.** El humano implementa el teclado; esto no lo implementa y llama a los métodos
## directamente. Así el mismo capitán sirve para un barco enemigo y para el nuestro (piloto
## automático), y el barco no conoce el tipo de ninguno de los dos — igual que no conoce el tipo
## de sus velas, a las que manda por nombre de método.
##
## No lee el teclado. Ni una tecla. El día que haga falta que el jugador le diga algo, va como
## orden desde el jugador.
##
## ── Por qué las tácticas son ESTAS y no otras ─────────────────────────────────
##
## Salen del modelo de navegación que ya tiene el juego, no de un manual:
##
##   · **La zona muerta es real.** `Barco.angulo_muerto` son 40° en la balandra, así que un
##     rumbo dentro de ese cono no se puede navegar: hay que dar BORDADAS. Un capitán que apunte
##     la proa al enemigo cuando el enemigo está a barlovento se queda parado mirando al viento,
##     y eso se ve como un barco tonto.
##   · **Los cañones no giran.** `Canon.elevacion` está en 0 mientras el tubo sea rígido con la
##     cureña, y no hay traversa. Así que **el barco ES la mira**: para disparar hay que poner al
##     enemigo por el COSTADO, y toda la maniobra de combate consiste en eso.
##   · **La recarga son 5 s por pieza** (`Artilleria.recarga`) y hay dos bandas. Girar para
##     presentar la otra banda mientras la primera recarga es lo que se hacía de verdad, y aquí
##     sale de la misma cuenta.
##   · **El barlovento no es adorno.** Desde barlovento eliges la distancia y el momento, y el de
##     sotavento no puede cerrar porque tendría que navegar dentro de su propia zona muerta. Es
##     la única ventaja posicional que este modelo permite de verdad.
##
## ── Lo que necesita del barco ─────────────────────────────────────────────────
##
## Sólo órdenes públicas, y una pregunta: `factor_viento_en(rumbo)`, o sea la propulsión que
## daría un rumbo HIPOTÉTICO. Hace falta para saber si un rumbo es navegable, y **se le pregunta
## al barco a propósito en vez de calcularlo aquí**: la curva de propulsión es del casco (su
## `angulo_muerto` y su `angulo_optimo`), y dos fórmulas para lo mismo es cómo el capitán acaba
## creyendo que ciñe más de lo que el barco ciñe. Es la misma razón por la que la decisión de
## disparar usa `Canon.punto_de_caida()` y no una parábola propia.
##
## Mientras el mando no se haya movido al jugador, `orden_timon` y `factor_viento_en` pueden no
## existir todavía: en ese caso avisa UNA vez y sigue peleando con lo que sí puede (apuntar y
## disparar). Avisa en vez de callar porque un capitán que no gobierna parece un capitán tonto, y
## eso es media sesión perdida buscando la táctica que falla.
##
## SIN MEDIR TODAVÍA: no hay ni un número de esta clase comprobado. Las herramientas que los van
## a dar son `tools/rumbo_ia.tscn` (¿llega a un rumbo a barlovento, en cuántas viradas y con
## cuánto sobrepaso?) y `tools/duelo.tscn` (¿a qué distancia abre fuego, cuántas balas tocan?).

## Bando. Es enemigo de todo barco cuyo bando no sea el suyo; los barcos que no declaran bando se
## toman como del jugador, que es lo que son hoy.
@export var bando := "enemigo"

## 0,1 = grumete, 1 = artillero de escuela. Afecta a DOS cosas, y las dos con sentido físico:
## cada cuánto reacciona (uno malo tarda) y cuánto se conforma al disparar (uno malo suelta la
## andanada cuando el tiro todavía no cubre al enemigo, y falla).
@export_range(0.1, 1.0) var pericia := 1.0

## Cada cuánto DECIDE, en segundos. No cada frame: nadie replantea la táctica 60 veces por
## segundo, cuesta, y decidir cada frame es además lo que hace que un capitán tiemble entre dos
## opciones. El timón sí se corrige todos los frames — eso es la mano, no la cabeza.
@export var periodo := 0.25

## Distancia a la que quiere pelear, en metros, POR SI el barco no monta artillería. Cuando la
## monta no se usa: manda `_alcance_real()`, que se lo pregunta a las piezas.
@export var distancia_combate := 130.0

## Por encima de esto no va al enemigo: va a BARLOVENTO del enemigo. Buscar el barlovento desde
## más cerca es regalar la posición mientras cruzas por delante de sus cañones.
@export var distancia_barlovento := 260.0

## Grados de MAS sobre la zona muerta al cenir, como TOPE de seguridad. El angulo de cenida de
## verdad no se pone aqui: se busca en la polar del casco (`_cenida_maxima`), porque ponerlo a
## mano fue justo el fallo que se midio.
@export var margen_cenida := 40.0

## Cuánto se puede desviar de la línea al blanco antes de virar, en metros. Es el ancho de la
## escalera de bordadas: más estrecho, más viradas (y cada virada cuesta velocidad); más ancho,
## camino más largo.
@export var ancho_bordada := 60.0

## Error de rumbo, en grados, con el que ya pide timón a tope. Por debajo, proporcional.
@export var zona_timon := 30.0

## Propulsión mínima para considerar un rumbo navegable, en la escala de `factor_viento`.
##
## 0,35 y no 0,15, y la diferencia se vio medida: con 0,15 un capitán se plantó en un rumbo a
## 39° del viento —justo en el borde de la zona muerta de 40°— y se quedó **30 s a 0,6 m/s**
## con el timón casi centrado, o sea convencido de que iba bien. Técnicamente propulsaba; en la
## práctica no se movía, y como tampoco estaba parado del todo, el rescate de irons no entraba.
## Un rumbo que no mueve el barco no es un rumbo: mejor ceñir en condiciones.
@export_range(0.0, 1.0) var propulsion_minima := 0.35

enum Maniobra {SIN_BLANCO, BARLOVENTO, CERRAR, ANDANADA}

var _barco: Node3D
var _blanco: Node3D
var _maniobra := Maniobra.SIN_BLANCO
var _rumbo_pedido := Vector3.ZERO
## Bordada actual: +1 y −1 son las dos amuras, 0 = rumbo directo (no hace falta ceñir). Se guarda
## porque **sin memoria el capitán vira cada frame**: en cuanto la bordada elegida deja de ser la
## mejor por un pelo, la otra lo es, y el barco se queda temblando de proa al viento.
var _bordada := 0
var _viradas := 0
var _reloj := 0.0
## Segundos seguidos sin propulsion y sin arrancada. Es lo que detecta quedarse en el ojo.
var _parado := 0.0
## Angulo de cenida real de este casco, buscado una vez en su polar. 0 = aun sin buscar.
var _cenida := 0.0
## Distancia al blanco en la decision anterior. Sirve para saber si se escapa.
var _distancia_previa := INF
## Puesto de tiro que se persigue, como indice del reparto alrededor del enemigo. -1 = ninguno.
var _puesto_idx := -1
## Velocidad de apertura de la distancia al blanco, m/s suavizados. >0 = se escapa.
var _tasa := 0.0
var _aviso_dado := false


## La llama el propio barco sobre sus hijos que tengan este método (ver `Barco._ready`), que es
## por donde el proyecto entrega el barco a sus componentes.
func configurar(barco: Node3D) -> void:
	_barco = barco


func _ready() -> void:
	if _barco == null:
		_barco = get_parent() as Node3D
	if _barco == null:
		push_warning("CapitanIA: no cuelga de un barco; no hay nada que mandar.")
		set_physics_process(false)
		return
	# Diferido: las velas y la artillería del barco se montan en diferido desde su `_ready`, así
	# que una orden dada aquí llegaría antes de que existan.
	_zafarrancho.call_deferred()


func _zafarrancho() -> void:
	# Las velas arriba: un barco de guerra no llega a la cita con el paño recogido.
	if _barco.has_method("set_vela_delantera"):
		_barco.call("set_vela_delantera", true)
		_barco.call("set_vela_trasera", true)
	_fondear(false)


## Atrapado de proa al viento: sin propulsión y sin arrancada. Se exige que dure un poco —no un
## frame— porque al virar se pasa por ahí de forma normal y legítima; lo que es un problema es
## quedarse.
func _en_irons() -> bool:
	return _parado > 1.5


func _lento() -> bool:
	var maxima: float = float(_barco.get("velocidad_max")) if "velocidad_max" in _barco else 9.0
	return absf(float(_barco.get("velocidad"))) < maxima * 0.3


func _physics_process(delta: float) -> void:
	# El contador de "sin arrancada" corre en el reloj de la física, que es donde el casco
	# actualiza su velocidad.
	if float(_barco.call("factor_viento")) < 0.08 and absf(float(_barco.get("velocidad"))) < 1.0:
		_parado += delta
	else:
		_parado = 0.0
	_reloj -= delta
	if _reloj <= 0.0:
		# Un capitán torpe tarda más en reaccionar: con pericia 0,1 el periodo se multiplica por
		# diez, o sea 2,5 s entre decisión y decisión.
		_reloj = periodo / clampf(pericia, 0.1, 1.0)
		_decidir()
	_gobernar()


# ── La cabeza ────────────────────────────────────────────────────────────────
func _decidir() -> void:
	_blanco = _elegir_blanco()
	if _blanco == null:
		_maniobra = Maniobra.SIN_BLANCO
		# Sin nadie a quien perseguir, mantiene el rumbo si es navegable. Así al menos navega en
		# vez de quedarse a la deriva de proa al viento.
		_rumbo_pedido = _rumbo_navegable(_proa())
		return

	var hacia := _horizontal(_blanco.global_position - _barco.global_position)
	var distancia := hacia.length()
	if distancia < 0.01:
		return
	hacia = hacia / distancia

	# Ganar el barlovento sale caro en distancia, y **solo se paga si el enemigo no se esta
	# escapando**. Medido contra un blanco que huia en popa: el capitan cambio a barlovento a
	# los 260 m y la separacion siguio creciendo de 238 a 366 m en 70 s, porque el punto de
	# cita esta a barlovento y el que huye va a sotavento. Contra alguien que abre distancia,
	# lo que toca es cortarle.
	# En VELOCIDAD de apertura (m/s) y no en metros: el capitan decide cada 0,25 s, asi que un
	# enemigo que abre a 1,8 m/s solo separa 0,45 m entre decision y decision. Con el umbral en
	# metros no llegaba al liston y el estado alternaba entre "barlovento" y "cerrando" en
	# decisiones consecutivas — medido, once cambios en 70 s. Suavizado ademas, porque el
	# cabeceo mete ruido en la distancia.
	var intervalo := periodo / clampf(pericia, 0.1, 1.0)
	if is_finite(_distancia_previa):
		_tasa = lerpf(_tasa, (distancia - _distancia_previa) / maxf(intervalo, 0.01), 0.4)
	_distancia_previa = distancia
	var abriendo := _tasa > 0.3
	if distancia > distancia_barlovento and not abriendo:
		_maniobra = Maniobra.BARLOVENTO
		_rumbo_pedido = _rumbo_navegable(_hacia_el_barlovento_del_blanco())
		return

	# ── Ir a por el puesto de tiro ────────────────────────────────────────────
	# Antes esto era una MEZCLA de rumbos: perseguir y ladearse en proporcion al error de
	# distancia. No converge, y se vio medido: los dos capitanes se quedaron dando vueltas a
	# **82 m con el alcance en 68** y no dispararon en 60 s. Es lo que le pasa a una ley que
	# mezcla direcciones en vez de ir a un SITIO — al acercarse el termino perpendicular gana,
	# el barco orbita y la distancia deja de bajar.
	#
	# Ahora se elige un PUESTO DE TIRO concreto y se navega a el. Y se elige por lo que vale,
	# no por gusto: el casco enemigo es una elipse de 6 m de eslora por 1,9 de manga, asi que
	# un tiro que entra por la proa o por la popa atraviesa **3,2 veces mas barco** que uno por
	# el traves. Enfilar —lo que en la vela se llamo siempre cruzar la T— no es una preferencia
	# estetica: es el blanco mas grande que ofrece ese casco, y sale de su propia medida.
	var banda := _banda_cargada()
	var alcance := _alcance_real()
	var puesto := _mejor_puesto(alcance)
	var a_puesto := _horizontal(puesto - _barco.global_position)
	# Para tirar por estribor, el enemigo tiene que caer a estribor: la proa deseada es el rumbo
	# al enemigo girado un cuarto de vuelta. El signo sale de la orientacion del barco (proa en
	# -Z, estribor en +X), no de probar a ver.
	var perpendicular := hacia.rotated(Vector3.UP, PI * 0.5 if banda == "estribor" else -PI * 0.5)
	if a_puesto.length() > alcance * 0.25:
		_maniobra = Maniobra.CERRAR
		_rumbo_pedido = _rumbo_navegable(a_puesto.normalized())
	else:
		# Ya en el puesto: presentar la banda y sostenerla.
		_maniobra = Maniobra.ANDANADA
		_rumbo_pedido = _rumbo_navegable(perpendicular)

	# Apuntar SIEMPRE la banda que va a tirar, aunque todavía no toque disparar: es lo que lee
	# `disparar_banda` y lo que dibuja la guía de tiro, así que sin esto el barco acabaría
	# disparando con la banda contraria a la que ha presentado.
	if _barco.has_method("apuntar"):
		_barco.call("apuntar", banda)
	else:
		_barco.set("banda_apuntada", banda)
	_apuntar_la_bateria(banda)
	if _tiro_cubre_al_blanco(banda):
		_barco.call("disparar_banda")


## El puesto de tiro que mas conviene: un punto a distancia de tiro del enemigo, elegido por
## **cuanto barco ofrece desde alli** y **cuanto se tarda en llegar**, que son las dos unicas
## cosas que importan y las dos se pueden medir.
##
##   · Lo que ofrece = la cuerda de la elipse del casco enemigo en esa direccion. Por la proa o
##     la popa son sus 6 m de eslora; por el traves, 1,9 de manga. No es un peso inventado: es
##     el tamano real del blanco visto desde ahi.
##   · Lo que cuesta = la distancia hasta el puesto dividida por la velocidad que este casco
##     sacaria en ese rumbo, preguntandosela al barco (`factor_viento_en`). Un puesto perfecto
##     al que no se puede ceñir no vale nada, y asi queda descartado solo.
##
## La nota se reparte entre las dos: metros de blanco por segundo de maniobra. Eso es tomar
## riesgos con criterio — se mete por donde mas gana, no por donde mas comodo esta.
func _mejor_puesto(alcance: float) -> Vector3:
	var proa_enemiga := _horizontal(-_blanco.global_transform.basis.z)
	if proa_enemiga.length() < 0.01:
		proa_enemiga = Vector3.FORWARD
	proa_enemiga = proa_enemiga.normalized()
	var semiejes := Vector2(6.0, 6.0)
	if "recorte_radio" in _blanco:
		semiejes = _blanco.get("recorte_radio")
	var maxima: float = float(_barco.get("velocidad_max")) if "velocidad_max" in _barco else 9.0

	var mejor := _blanco.global_position
	var mejor_nota := -INF
	var mejor_i := -1
	var nota_actual := -INF
	var sitio_actual := Vector3.ZERO
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var sitio: Vector3 = _blanco.global_position + proa_enemiga.rotated(Vector3.UP, ang) * alcance
		var camino := _horizontal(sitio - _barco.global_position)
		var d := camino.length()
		if d < 0.01:
			return sitio
		var empuje := _propulsion(camino / d)
		if empuje < propulsion_minima:
			continue    # no se puede llegar: el rumbo cae en la zona muerta
		# Cuerda de la elipse en esa direccion, en metros de barco que atraviesa el tiro.
		var sn := sin(ang)
		var cs := cos(ang)
		var blanco_m := 1.0 / sqrt(sn * sn / (semiejes.x * semiejes.x)
			+ cs * cs / (semiejes.y * semiejes.y))
		var segundos := d / maxf(maxima * empuje, 0.5)
		var nota := blanco_m / maxf(segundos, 1.0)
		if i == _puesto_idx:
			nota_actual = nota
			sitio_actual = sitio
		if nota > mejor_nota:
			mejor_nota = nota
			mejor_i = i
			mejor = sitio
	# Memoria, como en la bordada y en la eleccion de blanco: **no se cambia de puesto por poco**.
	# La nota de un puesto mejora sola segun te acercas a el, asi que sin histeresis el capitan
	# cambia de idea a mitad de camino y se va al de enfrente. Medido contra un blanco fondeado:
	# cerro de 238 a 124 m y se volvio a abrir hasta 250 sin disparar. Hace falta que el nuevo sea
	# claramente mejor —un cuarto— para soltar el que ya persigue.
	if _puesto_idx >= 0 and nota_actual > -INF and mejor_nota < nota_actual * 1.25:
		return sitio_actual
	_puesto_idx = mejor_i
	return mejor


## Lleva la punteria de la bateria: cuna (elevacion) y espeque (giro lateral), que es lo que el
## barco expone como `apuntar_fino`.
##
## Sin esto el capitan solo podia apuntar MANIOBRANDO, y con la cuna a cero el alcance es una
## constante —68 m en esta balandra—, asi que la ventana de tiro eran unos pocos metros de
## distancia Y de demora a la vez. Medido: dos capitanes cerrando bien, orbitando entre 54 y
## 66 m, **cero disparos en 60 s**. Con la cuna (-3 a +12 grados) y el espeque (+-15) la
## ventana se abre y el tiro se corrige en vez de esperar a que la geometria cuadre sola.
##
## **Se apunta PROBANDO, con la propia pieza de oraculo**: se le pone una elevacion, se le
## pregunta `punto_de_caida()` y se compara. Ni se invierte la parabola ni se razonan los signos
## —que dependen de la banda, porque la pieza de estribor va media vuelta girada—, y por tanto
## no hay forma de equivocarse en ellos. Es la misma razon por la que el alcance se pregunta en
## vez de escribirse.
func _apuntar_la_bateria(banda: String) -> void:
	if not _barco.has_method("apuntar_fino"):
		return
	var piezas := _canones(banda)
	if piezas.is_empty() or _blanco == null or not is_instance_valid(_blanco):
		return
	var c = piezas[0]
	var boca: Vector3 = c.call("boca_global")
	# Adonde hay que tirar: donde ESTARA el enemigo cuando llegue la bala.
	var vel := Vector3.ZERO
	if _blanco is CharacterBody3D:
		vel = (_blanco as CharacterBody3D).velocity
	var vuelo := Bala.tiempo_hasta(boca, c.call("velocidad_salida"), float(c.get("altura_mar")))
	var futuro: Vector3 = _blanco.global_position + vel * maxf(vuelo, 0.0)
	var al_blanco := _horizontal(futuro - boca)
	var falta := al_blanco.length()
	if falta < 1.0:
		return

	# ── Cuna: la elevacion cuyo punto de caida cae a la distancia que falta ──
	var e0: float = float(c.get("elevacion"))
	var mejor_e := e0
	var mejor_err := INF
	for i in 16:
		var e: float = lerpf(-3.0, 12.0, float(i) / 15.0)
		c.set("elevacion", e)
		var r := _horizontal(c.call("punto_de_caida") - boca).length()
		var err := absf(r - falta)
		if err < mejor_err:
			mejor_err = err
			mejor_e = e
	c.set("elevacion", e0)

	# ── Espeque: el giro lateral que deja el tubo mirando al blanco ──
	var g0: float = float(c.get("giro_lateral"))
	var mejor_g := g0
	var mejor_ang := INF
	for i in 13:
		var g: float = lerpf(-15.0, 15.0, float(i) / 12.0)
		c.set("giro_lateral", g)
		var d := _horizontal(c.call("direccion_global"))
		if d.length() < 0.01:
			continue
		var ang := absf(_angulo_con_signo(d.normalized(), al_blanco.normalized()))
		if ang < mejor_ang:
			mejor_ang = ang
			mejor_g = g
	c.set("giro_lateral", g0)

	# `apuntar_fino` trabaja con INCREMENTOS y los aplica a toda la bateria, asi que se le pasa
	# la diferencia respecto a lo que ya tenia esta pieza. Todas parten de lo mismo y reciben lo
	# mismo, asi que no se descuadran entre si.
	_barco.call("apuntar_fino", mejor_g - g0, mejor_e - e0)


## El barco enemigo más cercano.
##
## Se buscan por MÉTODO y no por tipo (`canones_de`), igual que el barco recoge sus velas por
## `izar`: así valdrá el día que haya un brulote o una batería de costa que no sean `Barco`.
func _elegir_blanco() -> Node3D:
	var mejor: Node3D = null
	var mejor_d := INF
	for n in _barcos_del_mundo():
		if n == _barco:
			continue
		if _bando_de(n) == bando:
			continue
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d: float = _barco.global_position.distance_to(n3.global_position)
		if d < mejor_d:
			mejor_d = d
			mejor = n3
	# Histeresis: no se cambia de blanco por unos metros. Se conserva el que ya se persigue
	# salvo que otro este MUCHO mas cerca (un 30 %), porque en cuanto dos enemigos quedan a
	# distancia parecida el capitan se pondria a alternar entre los dos y no atacaria a ninguno
	# —el mismo problema que la bordada, y se cura igual: con memoria.
	if _blanco != null and is_instance_valid(_blanco) and _blanco != mejor:
		var d_actual: float = _barco.global_position.distance_to(_blanco.global_position)
		if mejor == null or mejor_d > d_actual * 0.7:
			return _blanco
	return mejor


## De que bando es un barco. **Se le pregunta a quien lleva su timon**, no al barco: el bando es
## de quien manda, igual que el teclado es del jugador y las ordenes son del barco. Un barco sin
## capitan de IA es del jugador, que es lo que hay hoy.
##
## Leer el bando del BARCO fue un fallo real: `Barco` no tiene esa propiedad, asi que todos los
## barcos salian como "jugador" y dos enemigos de la misma escuadra se habrian atacado entre si.
## Con un solo enemigo en escena no se ve; con dos, la escuadra se dispara a si misma.
func _bando_de(barco: Node) -> String:
	for h in barco.get_children():
		if h is CapitanIA:
			return (h as CapitanIA).bando
	return "jugador"


## Todos los barcos de la escena. Por el grupo `barcos` si existe; si no, rastreando el árbol,
## que es lo que hay hasta que el grupo esté puesto.
func _barcos_del_mundo() -> Array[Node]:
	var l := get_tree().get_nodes_in_group("barcos")
	if not l.is_empty():
		return l
	var sale: Array[Node] = []
	var raiz := get_tree().current_scene
	if raiz == null:
		return sale
	for n in raiz.find_children("*", "CharacterBody3D", true, false):
		if n.has_method("canones_de"):
			sale.append(n)
	return sale


# ── La mano: el timón ────────────────────────────────────────────────────────
## Corrige el timón hacia el rumbo pedido, todos los frames. Proporcional al error y saturado: no
## hace falta nada más fino porque la caña ya tiene su propio suavizado (`timon_suavizado`) y la
## eficacia del timón ya escala con la velocidad dentro del barco.
func _gobernar() -> void:
	if _rumbo_pedido.length() < 0.01:
		return
	var error := _angulo_con_signo(_proa(), _rumbo_pedido)
	var orden := clampf(error / deg_to_rad(zona_timon), -1.0, 1.0)

	# ── Quedarse de proa al viento ────────────────────────────────────────────
	# Un velero parado con la proa en el viento no sale solo, y aquí menos: la eficacia del
	# timón escala con la velocidad (`giro_minimo` 0,2 × `velocidad_giro` 0,45 = 0,09 rad/s
	# parado), así que dar media vuelta cuesta 17 s. Medido en el duelo: una balandra se quedó
	# a 0,0-0,3 m/s con el rumbo en el ojo del viento durante 40 de los 60 s, sin disparar una
	# sola vez. Desde fuera es un enemigo tonto.
	#
	# Dos reglas, y las dos son de navegar, no parches:
	#
	#  · **Si ya está atrapado, ABATE**: timón a la banda que aleja la proa del viento, y no se
	#    suelta hasta que el barco vuelve a propulsar. Es lo que hace un patrón con el foque en
	#    facha.
	#  · **Si va lento, no cruza el ojo**: cuando el giro más corto hasta el rumbo pedido
	#    pasaría por la zona muerta, se da la vuelta por la OTRA banda. Es virar en redondo en
	#    vez de por avante, que es justo lo que se hace sin arrancada para no quedarse clavado.
	#    Con arrancada sí se cruza: virar por avante a 9 m/s sale bien y es más corto.
	var origen := _horizontal(-Viento.direccion)
	if origen.length() > 0.01:
		origen = origen.normalized()
		var al_viento := _angulo_con_signo(_proa(), origen)
		if _en_irons():
			# Alejar la proa del viento: si el viento está por babor, timón a estribor.
			orden = -signf(al_viento) if absf(al_viento) > 0.01 else float(_bordada)
		elif _lento() and signf(error) == signf(al_viento) and absf(al_viento) < absf(error):
			orden = -signf(error)
	# El signo está MEDIDO, no deducido (`tools/gira_o_no.tscn`): con `orden_timon` = +1 el
	# casco pasó de 90° a −151° de rumbo en 8 s, o sea que un valor POSITIVO mueve la proa a
	# BABOR. Por eso `_angulo_con_signo` devuelve positivo hacia babor: los dos signos tienen
	# que ser el mismo.
	#
	# Cruzados —que es como nació— el capitán ordena timón al lado contrario, el error crece
	# hasta 180°, ahí envuelve y el signo se invierte: el timón oscila a tope y el rumbo se
	# queda CONGELADO. Medido en el duelo: timón ±1,00 y el rumbo clavado en ±90° durante
	# 90 s, con el barco navegando a 9 m/s. Un timón saturado que no gira es esa firma.
	if "orden_timon" in _barco:
		_barco.set("orden_timon", orden)
	else:
		_avisar("CapitanIA: el barco todavía no expone `orden_timon`, así que este capitán "
			+ "apunta y dispara pero NO gobierna. Falta mover los controles al jugador.")


# ── Geometría de la vela ─────────────────────────────────────────────────────
## Rumbo navegable más parecido al deseado. Si el deseado se puede navegar, ese; si cae en la
## zona muerta, la amura de la bordada que toque.
func _rumbo_navegable(deseado: Vector3) -> Vector3:
	if deseado.length() < 0.01:
		return _proa()
	deseado = deseado.normalized()
	if _propulsion(deseado) >= propulsion_minima:
		_bordada = 0
		return deseado

	# Zona muerta: hay que ceñir. Las dos amuras posibles son el origen del viento girado ±el
	# límite de ceñida.
	var origen := _horizontal(-Viento.direccion).normalized()
	var limite := deg_to_rad(_cenida_maxima())
	var amura_estribor := origen.rotated(Vector3.UP, limite)
	var amura_babor := origen.rotated(Vector3.UP, -limite)

	# Cuánto nos hemos salido de la línea directa al blanco, medido perpendicular al eje del
	# viento (la "escalera" de la ceñida). Es lo que decide cuándo virar, y no el ángulo al
	# blanco: ese cambia solo al acercarse, y haría virar sin motivo.
	var lateral := Vector3.ZERO
	if _blanco != null and is_instance_valid(_blanco):
		var d := _horizontal(_barco.global_position - _blanco.global_position)
		lateral = d - origen * d.dot(origen)

	if _bordada == 0:
		_bordada = 1 if amura_estribor.dot(deseado) >= amura_babor.dot(deseado) else -1
	elif lateral.length() > ancho_bordada:
		# Virar sólo si la bordada actual es la que nos está alejando. Sin esta condición, un
		# barco que ya vuelve hacia la línea viraría igualmente y se quedaría en zigzag corto.
		var actual := amura_estribor if _bordada > 0 else amura_babor
		if actual.dot(lateral) > 0.0:
			_bordada = -_bordada
			_viradas += 1
	return amura_estribor if _bordada > 0 else amura_babor


## Un punto a barlovento del enemigo, a distancia de combate: la posición desde la que se manda
## el encuentro.
func _hacia_el_barlovento_del_blanco() -> Vector3:
	var origen := _horizontal(-Viento.direccion).normalized()
	var cita := _blanco.global_position + origen * distancia_combate
	return _horizontal(cita - _barco.global_position).normalized()


## Propulsión que daría ese rumbo. La pregunta va al BARCO: la curva es de su casco.
func _propulsion(rumbo: Vector3) -> float:
	if _barco.has_method("factor_viento_en"):
		return float(_barco.call("factor_viento_en", rumbo))
	_avisar("CapitanIA: el barco no expone `factor_viento_en(rumbo)`, así que el capitán no "
		+ "sabe qué rumbos puede ceñir y puede quedarse de proa al viento. No se calcula aquí "
		+ "a propósito: la curva de propulsión es del casco, y duplicarla es cómo el capitán "
		+ "acaba creyendo que ciñe más de lo que el barco ciñe.")
	return 1.0


## El angulo mas cerrado al viento con el que este casco AVANZA de verdad, en grados, buscado en
## su propia polar preguntandole `factor_viento_en` rumbo a rumbo.
##
## No es un adorno: nacio como `angulo_muerto + 8` y **a 48 grados del viento esta balandra solo
## da el 0,04 de empuje**. El capitan cenia ahi convencido de que navegaba, y se quedaba 30 s a
## 0,6 m/s. La curva es mucho mas plana de lo que parece desde `angulo_muerto`: con muerto 40 y
## optimo 95, hace falta abrirse a unos 65 grados para sacar el 0,35.
##
## Buscarlo en vez de escribirlo es lo mismo que hace `_alcance_real()` con los canones, y por la
## misma razon: la lancha, la barca y la goleta tienen otra polar y este numero sera otro sin que
## nadie tenga que acordarse de cambiarlo.
func _cenida_maxima() -> float:
	if _cenida > 0.0:
		return _cenida
	var muerto: float = float(_barco.get("angulo_muerto")) if "angulo_muerto" in _barco else 45.0
	var origen := _horizontal(-Viento.direccion)
	if origen.length() < 0.01:
		return muerto + margen_cenida
	origen = origen.normalized()
	var tope := muerto + margen_cenida
	var g := muerto
	while g <= tope:
		if _propulsion(origen.rotated(Vector3.UP, deg_to_rad(g))) >= propulsion_minima:
			_cenida = g
			return g
		g += 1.0
	_cenida = tope
	return tope


# ── Artillería ───────────────────────────────────────────────────────────────
## La banda que puede tirar: la que tenga más piezas cargadas. En empate, estribor.
func _banda_cargada() -> String:
	return "estribor" if _cargadas("estribor") >= _cargadas("babor") else "babor"


func _cargadas(banda: String) -> int:
	var n := 0
	for c in _canones(banda):
		if bool(c.call("listo")):
			n += 1
	return n


## Hasta dónde llega el tiro de verdad, en metros, **preguntándoselo a las piezas**: la distancia
## horizontal de la boca a su propio punto de caída, promediada sobre la banda.
##
## No es un ajuste: es la corrección de un fallo medido. Con la distancia de combate escrita a
## mano en 130 m, los dos capitanes se estabilizaron a **140 m** y no dispararon ni una vez en
## 60 s — y hacían bien, porque el tiro caía 8 m corto y el casco enemigo mide 6 m de semieje.
## Con `elevacion` en 0 el alcance no es una preferencia sino una CONSTANTE del montaje: la boca
## está a 1,77 m sobre el agua, la bala tarda √(2h/g) = 0,60 s en caer y sale a 220 m/s, o sea
## 132 m. El capitán tiene que ir a esa distancia exacta, no a una parecida.
##
## Y sale de `punto_de_caida()`, la misma cuenta que vuela la bala y que dibuja la guía de tiro,
## así que el día que el tubo bascule y la elevación cambie el alcance, esto lo sigue solo.
func _alcance_real() -> float:
	var suma := 0.0
	var n := 0
	for banda in ["estribor", "babor"]:
		for c in _canones(banda):
			# Con la cuna a CERO, y devolviendola despues. Es la distancia de referencia del
			# montaje, no la que tenga apuntada ahora mismo: desde que el capitan layea las
			# piezas para la distancia real, medir "donde cae ahora" hace que el alcance sea
			# igual a la distancia actual, el puesto de tiro caiga donde el barco ya esta y deje
			# de acercarse. Medido: se planto a 130 m y no disparo en 70 s.
			#
			# Y cero no es un valor cualquiera: es el tiro RASANTE, el menos sensible a
			# equivocarse en la distancia, que es la posicion desde la que conviene pelear.
			var e0: float = float(c.get("elevacion"))
			c.set("elevacion", 0.0)
			var boca: Vector3 = c.call("boca_global")
			var caida: Vector3 = c.call("punto_de_caida")
			var d := _horizontal(caida - boca).length()
			c.set("elevacion", e0)
			if d > 1.0:
				suma += d
				n += 1
	return suma / float(n) if n > 0 else distancia_combate


func _canones(banda: String) -> Array:
	if not _barco.has_method("canones_de"):
		return []
	return _barco.call("canones_de", banda)


## ¿Cubre el tiro al enemigo? Se le pregunta a cada pieza DÓNDE va a caer su bala
## (`Canon.punto_de_caida`, la misma fórmula que vuela la bala y que dibuja la guía de tiro) y se
## compara con donde ESTARÁ el enemigo cuando llegue, no con donde está ahora.
##
## El adelanto importa: a 130 m el vuelo dura casi un segundo y una balandra a 9 m/s se ha ido
## 9 m, o sea una eslora y media. Un capitán que dispare al sitio donde ve al enemigo le tira
## siempre a la popa.
##
## El blanco es la ELIPSE del propio casco (`recorte_radio`: los semiejes medidos con que el mar
## recorta el agua, 1,9 × 6 m en la balandra), en el espacio del enemigo. Un radio único diría
## que un tiro 5 m a la banda es un tocado, y por la banda el casco sólo mide 1,9.
func _tiro_cubre_al_blanco(banda: String) -> bool:
	if _blanco == null or not is_instance_valid(_blanco):
		return false
	var vel_blanco := Vector3.ZERO
	if _blanco is CharacterBody3D:
		vel_blanco = (_blanco as CharacterBody3D).velocity
	var semiejes := Vector2(6.0, 6.0)
	if "recorte_radio" in _blanco:
		semiejes = _blanco.get("recorte_radio")
	# Un capitán torpe se conforma con menos: dispara cuando el tiro aún no cubre, y falla.
	semiejes /= clampf(pericia, 0.1, 1.0)

	for c in _canones(banda):
		if not bool(c.call("listo")):
			continue
		var boca: Vector3 = c.call("boca_global")
		var v0: Vector3 = c.call("velocidad_salida")
		var vuelo := Bala.tiempo_hasta(boca, v0, float(c.get("altura_mar")))
		if vuelo <= 0.0:
			continue
		var caida: Vector3 = c.call("punto_de_caida")
		var futuro := _blanco.global_position + vel_blanco * vuelo
		# En los ejes del ENEMIGO, para que la elipse esté orientada con su casco: X es la manga
		# y Z la eslora.
		var d: Vector3 = _blanco.global_transform.basis.inverse() * (caida - futuro)
		if (d.x * d.x) / (semiejes.x * semiejes.x) \
				+ (d.z * d.z) / (semiejes.y * semiejes.y) <= 1.0:
			return true
	return false


# ── Órdenes sueltas ──────────────────────────────────────────────────────────
func _fondear(v: bool) -> void:
	if _barco.has_method("set_ancla"):
		_barco.call("set_ancla", v)
	elif _barco.has_method("_set_ancla"):
		_barco.call("_set_ancla", v)


# ── Utilidades ───────────────────────────────────────────────────────────────
func _proa() -> Vector3:
	return _horizontal(-_barco.global_transform.basis.z).normalized()


func _horizontal(v: Vector3) -> Vector3:
	v.y = 0.0
	return v


## Ángulo con signo de `a` hacia `b` sobre la vertical. Positivo = hacia BABOR, que es el sentido
## en que un `rotate_y` positivo gira el casco (medido con `tools/gira_o_no.tscn`) y por tanto el
## que hay que pedirle a `orden_timon`.
func _angulo_con_signo(a: Vector3, b: Vector3) -> float:
	return atan2(a.z * b.x - a.x * b.z, a.dot(b))


func _avisar(texto: String) -> void:
	if _aviso_dado:
		return
	_aviso_dado = true
	push_warning(texto)


## Qué está haciendo, en una línea, y cuántas viradas lleva. Para el HUD y para las herramientas
## de medida: una máquina de estados que no se puede leer desde fuera se depura a ciegas.
func maniobra_actual() -> String:
	match _maniobra:
		Maniobra.BARLOVENTO:
			return "ganando el barlovento"
		Maniobra.CERRAR:
			return "cerrando la distancia"
		Maniobra.ANDANADA:
			return "banda presentada"
		_:
			return "sin blanco"


func viradas() -> int:
	return _viradas


## El alcance que se cree, en metros. Lo leen las herramientas de medida: un capitan que se
## coloca a la distancia equivocada y uno cuyos canones llegan a otra distancia se ven igual
## desde fuera y se arreglan en sitios distintos.
func alcance() -> float:
	return _alcance_real()


## Segundos que lleva atrapado de proa al viento, 0 si navega. Lo leen las herramientas: un
## capitan parado y uno que decide mal se ven igual en la tabla de distancias.
func parado() -> float:
	return _parado


## La propulsion que el capitan CREE que da el rumbo que ha pedido. Comparada con la que el
## casco tiene de verdad (`factor_viento()`), delata un capitan que se equivoca al elegir frente
## a uno que eligio bien y no puede llegar.
## A quien tiene por blanco, o null. Lo leen el HUD y las herramientas: "ataca" y "no encuentra
## a nadie" se ven igual desde fuera —el barco navega— y se arreglan en sitios distintos.
func blanco() -> Node3D:
	return _blanco


func propulsion_pedida() -> float:
	return _propulsion(_rumbo_pedido) if _rumbo_pedido.length() > 0.01 else -1.0

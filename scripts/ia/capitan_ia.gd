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
##   · **Los cañones apenas giran.** La cuña recorre 15° y el espeque 15° a cada banda, así que
##     **el barco es la mira**: para disparar hay que poner al enemigo por el COSTADO, y toda la
##     maniobra de combate consiste en eso. Lo que la puntería fina añade es la DISTANCIA — con
##     la cuña, de 27 a 490 m en esta balandra—, no la dirección.
##   · **La recarga son 5 s por pieza** (`Artilleria.recarga`) y hay dos bandas, pero presentar
##     la otra mientras la primera recarga NO se hace aquí: es una maniobra de un costado de doce
##     piezas, y con dos por banda arribar y volver a orzar cuesta mucho más que esperar. Se
##     intentó eligiendo la banda por cuál tenía más cargadas, y lo que salió fue un barco
##     apuntando a babor con el enemigo por estribor y dando media vuelta cada 5 s.
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
## ── Qué está medido ──────────────────────────────────────────────────────────
##
## `tools/porque_no_dispara.tscn` mide las tres cosas que este capitán hacía mal —a qué distancia
## se coloca, si su puntería llega a cubrir el blanco y si el timón da volantazos— y
## `tools/duelo.tscn` enfrenta a dos y cuenta disparos, tocados y distancia final. Los números
## que justifican cada decisión están en el comentario de cada método, y el paquete `ia` de la
## batería los vigila.

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

## A qué parte de su alcance máximo se bate, de 0 a 1.
##
## A la MITAD, y no pegado ni al límite, porque es lo que deja corregir a los dos lados: desde la
## mitad de la carrera de la cuña se puede alargar y acortar el tiro, mientras que desde el tope
## de abajo sólo se puede alargar y desde el de arriba no se puede nada. Un artillero se coloca
## donde pueda rectificar, no donde justo llegue.
@export_range(0.1, 1.0) var fraccion_de_alcance := 0.5

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
## Batería presentada. Con memoria por lo mismo que la bordada: un blanco que cruza la línea de
## crujía haría bailar la banda de un lado a otro, y con ella el rumbo de la andanada.
var _banda := "estribor"
## Si el barco va lento AHORA MISMO, con histéresis. Ver `_lento()`.
var _iba_lento := false
## Virada en redondo en curso: 0 = ninguna, ±1 = la banda a la que se lleva la caña. Ver
## `_gobernar()`.
var _redondo := 0
## Virada por avante en curso: 0 = ninguna, ±1 = la banda a la que se lleva la caña. Se guarda
## por lo mismo que `_redondo`: a mitad de cruzar el ojo el barco va lento, y sin memoria la regla
## de "lento, no cruces" la abortaba.
var _avante := 0
## Arribando para coger arrancada antes de virar por avante: 0 = no, ±1 = la banda de la virada
## que viene después. Ver `_gobernar()`.
var _arribando := 0
## Radio al que se está peleando, en metros. 0 = todavía no se está a tiro. Se fija al entrar
## en la andanada y no se recalcula: ver el porqué en `_decidir()`.
var _radio_combate := 0.0
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


## Si el barco va lento, y por tanto no puede cruzar el ojo del viento a la virada.
##
## Con DOS umbrales y memoria, que es lo que faltaba: con uno solo (0,3 × `velocidad_max`), un
## barco navegando justo en él entra y sale de la condición cada frame, y como de ella depende
## qué ley gobierna la caña, el timón salta de banda a banda. Medido con
## `tools/porque_no_dispara.tscn`: **1.176 volantazos en 60 s** a una velocidad media de 2,78 m/s
## con el umbral en 2,70. Un umbral al que se llega navegando —el que da un rumbo ceñido— es
## justo donde un barco se pasa la vida.
##
## Y los dos umbrales salen de `propulsion_minima`, no de números nuevos: esa es la propulsión
## por debajo de la cual el capitán no considera navegable un rumbo, así que la velocidad que le
## corresponde (3,1 m/s en esta balandra) es la frontera entre navegar y no navegar. Lento es ir
## a menos de la MITAD de eso, y se deja de estarlo al llegar a nueve décimas.
##
## Puestos en 0,25 y 0,45 de `velocidad_max` —que fue el primer intento— el barco sale lento
## para siempre: un rumbo ceñido da 3,1 m/s y el umbral alto pedía 4,05, así que la regla de "no
## cruces el ojo" quedaba armada permanentemente y **el capitán dejó de virar por avante**. La
## prueba lo cazó: de una virada a cero.
func _lento() -> bool:
	return _iba_lento


## Si lleva arrancada para cruzar el ojo virando por avante. La cuenta es del casco
## (`Barco.velocidad_para_virar()`): una virada se empieza solo si se puede terminar, y si no se
## vira en redondo, que es lo que hace un patrón con un barco que no tiene arrancada para orzar.
func _arrancada_para_virar() -> bool:
	if not _barco.has_method("velocidad_para_virar"):
		return true
	return float(_barco.get("velocidad")) >= float(_barco.call("velocidad_para_virar"))


func _physics_process(delta: float) -> void:
	# El contador de "sin arrancada" corre en el reloj de la física, que es donde el casco
	# actualiza su velocidad.
	if float(_barco.call("factor_viento")) < 0.08 and absf(float(_barco.get("velocidad"))) < 1.0:
		_parado += delta
	else:
		_parado = 0.0
	var maxima: float = float(_barco.get("velocidad_max")) if "velocidad_max" in _barco else 9.0
	var navegando := maxima * propulsion_minima
	_iba_lento = absf(float(_barco.get("velocidad"))) < navegando * (0.9 if _iba_lento else 0.5)
	_reloj -= delta
	if _reloj <= 0.0:
		# Un capitán torpe tarda más en reaccionar: con pericia 0,1 el periodo se multiplica por
		# diez, o sea 2,5 s entre decisión y decisión.
		_reloj = periodo / clampf(pericia, 0.1, 1.0)
		_decidir()
	_gobernar()
	_puntear()


# ── La cabeza ────────────────────────────────────────────────────────────────
func _decidir() -> void:
	_blanco = _elegir_blanco()
	if _blanco == null:
		_maniobra = Maniobra.SIN_BLANCO
		_radio_combate = 0.0
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
	# El alcance, antes que nada, porque de él sale también hasta dónde vale la pena ganar el
	# barlovento: hacerlo desde DENTRO de la distancia de tiro es dejar de disparar para
	# maniobrar. `distancia_barlovento` queda como suelo para un barco sin artillería.
	var alcance := _alcance_real()
	if distancia > maxf(distancia_barlovento, alcance * 1.5) and not abriendo:
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
	var banda := _banda_que_bate()
	var puesto := _mejor_puesto(alcance)
	var a_puesto := _horizontal(puesto - _barco.global_position)
	# Para tirar por estribor, el enemigo tiene que caer a estribor: la proa deseada es el rumbo
	# al enemigo girado un cuarto de vuelta. El signo sale de la orientacion del barco (proa en
	# -Z, estribor en +X), no de probar a ver.
	#
	# Y QUÉ costado presentar no es lo mismo que en cuál cae el enemigo ahora mismo: para batir
	# por estribor hay que sostener ese rumbo concreto, y ese rumbo puede caer en la zona muerta.
	# Cuando pasa, el barco se va a la ceñida que sí puede navegar, el enemigo se le queda por la
	# aleta y no dispara — medido con el viento de través: de 180 a 256 m en 45 s sin un solo
	# tiro. Se presenta el costado cuya perpendicular se pueda navegar, y en igualdad el que ya
	# batía. Las dos perpendiculares están a 180° una de otra y la zona muerta mide 80°, así que
	# nunca pueden caer las dos dentro.
	var perpendicular := hacia.rotated(Vector3.UP, PI * 0.5 if banda == "estribor" else -PI * 0.5)
	var otra := -perpendicular
	if _propulsion(perpendicular) < propulsion_minima and _propulsion(otra) >= propulsion_minima:
		perpendicular = otra
	# Fuera de alcance se CIERRA hacia el puesto elegido; dentro de alcance no se cierra más: se
	# pelea desde donde se está. Irse a la distancia de libro teniendo ya al enemigo a tiro es
	# pasarse la pelea navegando — medido: naciendo a 180 m con el anillo en 250, el capitán se
	# pasaba media pelea abriéndose y soltaba 4 tiros en 45 s.
	#
	# Y el radio se FIJA al entrar en la andanada en vez de seguir a la distancia del momento.
	# Seguirla se muerde la cola: el anillo pasa siempre por donde está el barco, así que siempre
	# se cree en su puesto y va abriendo sin darse cuenta — medido, de 180 a 256 m en 45 s.
	if distancia > alcance * (1.15 if _radio_combate > 0.0 else 1.0):
		_maniobra = Maniobra.CERRAR
		_radio_combate = 0.0
		_rumbo_pedido = _rumbo_navegable(a_puesto.normalized())
	else:
		# Ya a tiro: sostener la banda presentada RODEANDO al enemigo, no tirando por la
		# perpendicular. Son dos cosas distintas y la diferencia se mide: con rumbo perpendicular
		# el barco se va en línea recta y la distancia crece sola, porque una perpendicular a una
		# demora que cambia no es una circunferencia. Persiguiendo un punto del anillo 45° más
		# allá, el rumbo se curva solo y la distancia se sostiene.
		if _radio_combate <= 0.0:
			_radio_combate = distancia
		_maniobra = Maniobra.ANDANADA
		_rumbo_pedido = _rumbo_navegable(_punto_de_caza(_radio_combate, perpendicular))


# ── La mano: la puntería ─────────────────────────────────────────────────────
## Laya la batería y suelta la andanada en cuanto el tiro cubre. Va en el reloj de los FRAMES y
## no en el de las decisiones, por lo mismo que el timón: es la mano, no la cabeza.
##
## Y no es una cuestión de gusto, es la ola. Entre una decisión y la siguiente pasa un cuarto de
## segundo, y en ese rato el casco sube y baja con la mar: la boca se mueve medio metro y **medio
## metro de ánima son 5-9 m de alcance** a estas distancias (dR/dh ≈ 18 m por metro a 110 m).
## Apuntando cuatro veces por segundo, el residuo del tiro se quedaba en +1 a +5 m de largo —
## sistemáticamente largo, porque se apunta en un instante y se dispara en otro— y el costado
## enemigo mide 1,9 m de manga, así que el tiro no cubría casi nunca. Medido con
## `tools/porque_no_dispara.tscn`. Con la puntería en el frame, se laya y se tira en el mismo
## instante y el residuo es el de la puntería, no el del oleaje.
func _puntear() -> void:
	if _blanco == null or not is_instance_valid(_blanco):
		return
	var banda := _banda_que_bate()
	# Apuntar SIEMPRE la banda que va a tirar, aunque todavía no toque disparar: es lo que lee
	# `disparar_banda` y lo que dibuja la guía de tiro, así que sin esto el barco acabaría
	# disparando con la banda contraria a la que tiene puesta en el blanco.
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
## pregunta `punto_de_caida()` y se compara. Ni se invierte la parabola ni se razonan los signos,
## y por tanto no hay forma de equivocarse en ellos. Es la misma razon por la que el alcance se
## pregunta en vez de escribirse.
##
## (El comentario decía que los signos dependen de la banda porque la pieza de estribor va media
## vuelta girada. No dependen: esa media vuelta es sobre Y y no toca la vertical. Compensarla por
## banda era el fallo que se corrigió en `Canon._aplicar_punteria` el 12 y el 13 de septiembre.)
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
	var mejor_e := _afinar(Canon.ELEVACION_MIN, Canon.ELEVACION_MAX, func(e: float) -> float:
		c.set("elevacion", e)
		return absf(_horizontal(c.call("punto_de_caida") - boca).length() - falta))
	c.set("elevacion", e0)

	# ── Espeque: el giro lateral que deja el tubo mirando al blanco ──
	var g0: float = float(c.get("giro_lateral"))
	var mejor_g := _afinar(-Canon.ESPEQUE_MAX, Canon.ESPEQUE_MAX, func(g: float) -> float:
		c.set("giro_lateral", g)
		var d := _horizontal(c.call("direccion_global"))
		if d.length() < 0.01:
			return INF
		return absf(_angulo_con_signo(d.normalized(), al_blanco.normalized())))
	c.set("giro_lateral", g0)

	# `apuntar_fino` trabaja con INCREMENTOS y los aplica a toda la bateria, asi que se le pasa
	# la diferencia respecto a lo que ya tenia esta pieza. Todas parten de lo mismo y reciben lo
	# mismo, asi que no se descuadran entre si.
	_barco.call("apuntar_fino", mejor_g - g0, mejor_e - e0)


## El valor entre `lo` y `hi` que menos error da, barriendo y ESTRECHANDO la ventana alrededor
## del mejor en cada pasada.
##
## Un barrido suelto no basta, y el número lo dice: la cuña recorre 15° y el tiro va de 27 a
## 490 m, así que con dieciséis puntos el paso es 1° y **1° son 40 m de alcance** a media
## distancia. El espeque recorría 30° en trece puntos, o sea 2,5°, que a 150 m son 6,5 m — y el
## casco enemigo mide 1,9 m de manga. Con esa resolución el tiro casi nunca cubría al blanco por
## mucho que el capitán estuviese bien colocado, y eso se ve como un enemigo que no dispara.
##
## Tres pasadas de nueve puntos dejan la cuña en 0,03° (poco más de un metro de alcance) y el
## espeque en 0,06°, y cuestan 54 evaluaciones cada cuarto de segundo: nada, comparado con no
## poder disparar.
func _afinar(lo: float, hi: float, error: Callable) -> float:
	var mejor := lo
	for pasada in 3:
		var mejor_err := INF
		for i in 9:
			var v: float = lerpf(lo, hi, float(i) / 8.0)
			var err: float = float(error.call(v))
			if err < mejor_err:
				mejor_err = err
				mejor = v
		var paso := (hi - lo) / 8.0
		lo = mejor - paso
		hi = mejor + paso
	return mejor


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
	var error_rumbo := error
	# **Aguantar el giro**: el casco tiene inercia de guiñada (`Barco.inercia_guinada`) y sigue
	# girando un rato después de levantar la caña, así que se gobierna sobre el error que QUEDARÁ
	# cuando suelte el giro que ya lleva, no sobre el de ahora — que es lo que hace un timonel al
	# "aguantar" antes de llegar al rumbo. Sin esto, con la inercia puesta el capitán se pasaba de
	# rumbo en cada corrección y ciñendo ganaba 18,6 m en 40 s en vez de 21,4.
	if _barco.has_method("guinada"):
		error -= float(_barco.call("guinada")) * float(_barco.get("inercia_guinada"))
	var orden := clampf(error / deg_to_rad(zona_timon), -1.0, 1.0)

	# ── Quedarse de proa al viento ────────────────────────────────────────────
	# Un velero parado con la proa en el viento no sale solo, y aquí menos: **el timón no hace
	# nada sin arrancada**, porque lo que gobierna es el agua que pasa por la pala. Medido en el
	# duelo: una balandra se quedó
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
	#
	# Y la segunda hay que TERMINARLA, no replantearla a cada frame: dando la vuelta por
	# sotavento el error de rumbo crece hasta 180° y ahí cambia de signo, así que la condición
	# que disparó la maniobra deja de cumplirse a mitad de ella y el capitán vuelve a meter la
	# proa en el viento — para volver a salir al frame siguiente. Por eso la virada en redondo
	# se guarda (`_redondo`) y no se suelta hasta que la proa llega, igual que la bordada.
	var origen := _horizontal(-Viento.direccion)
	if origen.length() > 0.01:
		origen = origen.normalized()
		var al_viento := _angulo_con_signo(_proa(), origen)
		# Si el giro más corto hasta el rumbo pedido pasa por el ojo del viento.
		var cruza := signf(error_rumbo) == signf(al_viento) and absf(al_viento) < absf(error_rumbo)
		if _avante != 0 and (not cruza or signf(error_rumbo) != float(_avante)):
			_avante = 0
		if _arribando != 0 and (not cruza or signf(error_rumbo) != float(_arribando)):
			_arribando = 0
		if _en_irons():
			# Alejar la proa del viento: si el viento está por babor, timón a estribor.
			orden = -signf(al_viento) if absf(al_viento) > 0.01 else float(_bordada)
			_redondo = 0
			_avante = 0
			_arribando = 0
		elif _avante != 0:
			# **La virada por avante que se empieza con arrancada se TERMINA.** Cruzar el ojo cuesta
			# arrancada siempre —por eso se empieza con ella—, y con la inercia de guiñada el casco
			# llega al ojo ya lento. Si a mitad se le aplicaba la regla de "lento, no cruces", la
			# virada se convertía en una en redondo, el barco recobraba arrancada al arribar y volvía a
			# intentarla: medido, un ciclo de 6 s con la proa entre −114° y −123° sin cruzar nunca.
			# Si de verdad se queda sin arrancada en el ojo —perder la virada, que pasa— lo saca
			# `_en_irons()`, abatiendo, como a cualquier patrón.
			orden = float(_avante)
		elif _redondo != 0:
			# Se suelta al LLEGAR, no al recobrar arrancada: arribando el barco acelera, y si eso la
			# soltaba volvía a intentar la virada por avante desde donde la había dejado.
			if absf(error_rumbo) < deg_to_rad(zona_timon) or not cruza and signf(error_rumbo) != float(_redondo):
				_redondo = 0
			else:
				orden = float(_redondo)
		elif _arribando != 0:
			# **Coger arrancada antes de virar.** Con el casco lento para cruzar el ojo, se arriba al
			# rumbo de máxima propulsión por la amura en que se va, y en cuanto hay arrancada se
			# vira por avante. Virar en redondo en su lugar —270° en vez de 90— le costaba al
			# capitán todo el barlovento: medido, 0 m en 40 s de ceñida.
			if _arrancada_para_virar():
				_avante = _arribando
				_arribando = 0
				orden = float(_avante)
			else:
				var optimo := deg_to_rad(float(_barco.get("angulo_optimo"))) 					if "angulo_optimo" in _barco else PI * 0.5
				var lado := signf(al_viento) if absf(al_viento) > 0.01 else 1.0
				var e_arr := _angulo_con_signo(_proa(), origen.rotated(Vector3.UP, -lado * optimo))
				if _barco.has_method("guinada"):
					e_arr -= float(_barco.call("guinada")) * float(_barco.get("inercia_guinada"))
				orden = clampf(e_arr / deg_to_rad(zona_timon), -1.0, 1.0)
		elif cruza and _lento():
			_redondo = int(-signf(error_rumbo))
			orden = float(_redondo)
		elif cruza and not _arrancada_para_virar():
			_arribando = int(signf(error_rumbo))
		elif cruza:
			_avante = int(signf(error_rumbo))
			orden = float(_avante)
	# El signo está MEDIDO, no deducido (`tools/gira_o_no.tscn`): con `orden_timon` = +1 el
	# casco pasó de 90° a −151° de rumbo en 8 s, o sea que un valor POSITIVO mueve la proa a
	# BABOR. Por eso `_angulo_con_signo` devuelve positivo hacia babor: los dos signos tienen
	# que ser el mismo.
	#
	# Cruzados —que es como nació— el capitán ordena timón al lado contrario, el error crece
	# hasta 180°, ahí envuelve y el signo se invierte: el timón oscila a tope y el rumbo se
	# queda CONGELADO. Medido en el duelo: timón ±1,00 y el rumbo clavado en ±90° durante
	# 90 s, con el barco navegando a 9 m/s. Un timón saturado que no gira es esa firma.
	#
	# **Ciando, este capitán NO invierte la caña, y está medido que es lo que hay que hacer.** El
	# timón del casco ya obra al revés con arrancada atrás —eso es física del timón y está en
	# `Barco`—, y lo suyo sería que el capitán lo tuviera en cuenta. Se probó: invirtiendo la orden
	# cuando la velocidad es negativa, el enemigo pasó de mantener la banda presentada a 85-89° de
	# demora a írsele a 38° con la caña a tope, y de **18 disparos en 45 s a 2**
	# (`tools/porque_no_dispara.tscn`).
	#
	# Dicho claro: **este capitán no sabe maniobrar dando atrás.** Su ley de caña es proporcional al
	# error de rumbo y da por supuesta la marcha avante; darle la vuelta al signo sin rehacer la
	# ley no arregla nada, la descuadra. Salir del ojo del viento ciando —dar atrás y meter la caña
	# al contrario, que es lo que hace un patrón— sigue pendiente, y mientras tanto sale de ahí
	# abatiendo, con `_en_irons()`.
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
## El rumbo que sostiene la banda presentada: hacia un punto del anillo de tiro 45° más allá, en
## el sentido en el que el barco ya está rodeando al enemigo.
##
## Rodear no es ir perpendicular. La perpendicular es la tangente en ESTE instante y en cuanto se
## navega un metro ya no lo es, así que un rumbo perpendicular sostenido es una recta y la
## distancia crece sola. Persiguiendo un punto del anillo el rumbo se curva solo, y de paso vale
## para las dos cosas: desde fuera del anillo tira hacia dentro y desde dentro hacia fuera.
##
## El SENTIDO no se razona, se prueba: de los dos puntos posibles se toma el que cae del lado al
## que ya apunta la perpendicular de esta banda. Así no hay signo que equivocar, que es la misma
## regla con la que se apuntan las piezas.
func _punto_de_caza(radio: float, perpendicular: Vector3) -> Vector3:
	var u := _horizontal(_barco.global_position - _blanco.global_position)
	if u.length() < 0.01:
		return perpendicular
	u = u.normalized()
	var mejor := Vector3.ZERO
	var mejor_dot := -INF
	for giro in [PI * 0.25, -PI * 0.25]:
		var sitio: Vector3 = _blanco.global_position + u.rotated(Vector3.UP, giro) * radio
		var rumbo := _horizontal(sitio - _barco.global_position)
		if rumbo.length() < 0.01:
			continue
		rumbo = rumbo.normalized()
		var d := rumbo.dot(perpendicular)
		if d > mejor_dot:
			mejor_dot = d
			mejor = rumbo
	return mejor if mejor_dot > -INF else perpendicular


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
## La batería que BATE al blanco: la del costado por el que cae.
##
## Se elegía por cuál tenía más piezas cargadas, y eso era un fallo con dos caras. En cuanto
## disparaba la banda buena se pasaba a la otra, así que **apuntaba a babor con el enemigo por
## estribor**: el espeque saturaba en sus 15°, el tiro caía entre 120 y 320 m del blanco y
## durante los 5 s de recarga no había forma de que cubriera. Medido con
## `tools/porque_no_dispara.tscn`: 4 de 6 distancias con la batería equivocada.
##
## Y la otra cara es la maniobra: el rumbo que se sostiene en la andanada es el perpendicular
## elegido POR esta banda, así que cambiarla le daba media vuelta al barco. Eso es un volantazo,
## y volvía cada 5 s con la recarga.
##
## Presentar la otra banda mientras la primera recarga es cierto que se hacía, pero es una
## MANIOBRA de un barco con costados de doce piezas, no un cambio de puntería: con dos por banda
## y 5 s de recarga, arribar y volver a orzar cuesta mucho más que esperar.
##
## Con histéresis de 10° sobre la crujía: sin ella, el blanco cruzando la línea de proa hace
## bailar la batería de una banda a otra, y con ella baila también el rumbo de la andanada.
func _banda_que_bate() -> String:
	if _blanco == null or not is_instance_valid(_blanco):
		return _banda
	var local := _barco.global_transform.basis.inverse() \
		* (_blanco.global_position - _barco.global_position)
	var d := Vector2(local.x, local.z).length()
	if d > 0.01 and absf(local.x) / d > sin(deg_to_rad(10.0)):
		_banda = "estribor" if local.x > 0.0 else "babor"
	return _banda


## A qué distancia pelea, en metros, **preguntándoselo a las piezas**: el alcance del montaje a
## tope de cuña, por la fracción de él a la que este capitán quiere batirse.
##
## Nació midiendo con la cuña a CERO, y eso era el fallo: el tiro rasante de esta balandra son
## 59 m y con la cuña arriba llega a 490, así que el capitán se colocaba al **15 % de su
## alcance** — pegado al enemigo, cañoneando a quemarropa un barco al que podía batir desde diez
## veces más lejos. Desde fuera se ve como un enemigo que se echa encima en vez de cañonear, y no
## lo delata nada más: navega bien y apunta bien. Medido con `tools/porque_no_dispara.tscn`.
##
## Lo que sigue siendo cierto de aquel comentario, y por lo que se mide a una cuña FIJA y no a la
## que la batería tenga puesta: desde que el capitán laya las piezas para la distancia real,
## medir "dónde cae ahora" hace que el alcance sea igual a la distancia actual, el puesto de tiro
## caiga donde el barco ya está y deje de acercarse. Medido: se plantó a 130 m y no disparó en
## 70 s. El tope de la cuña es una constante del afuste y lo pone la PIEZA (`Canon.ELEVACION_MAX`),
## así que el día que el afuste admita más cuña esto lo sigue solo.
func _alcance_real() -> float:
	var suma := 0.0
	var n := 0
	for banda in ["estribor", "babor"]:
		for c in _canones(banda):
			# `alcance_a` pone la cuña, mide y se la devuelve: la misma cuenta que vuela la bala
			# y que dibuja la guía de tiro, así que no pueden discrepar.
			var d: float = float(c.call("alcance_a", Canon.ELEVACION_MAX))
			if d > 1.0:
				suma += d
				n += 1
	if n == 0:
		return distancia_combate
	return (suma / float(n)) * fraccion_de_alcance


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
	return bool(_residuo_de_tiro(banda)["cubre"])


## Dónde cae el tiro de la banda respecto al blanco, en metros, y si lo cubre. Es lo que decide
## disparar, sacado aparte para que se pueda PREGUNTAR: un capitán que no dispara porque no
## llega y uno que no dispara porque la puntería no afina se ven igual desde fuera —ninguno
## dispara— y se arreglan en sitios distintos.
##
##   · `largo` — metros de más (+) o de menos (−) sobre la línea de tiro: lo corrige la cuña.
##   · `traves` — metros a la banda: lo corrige el espeque.
##   · `cubre` — si la bala cae dentro de la elipse del casco enemigo.
##   · `listas` — piezas cargadas de esa banda. Con 0, los otros números no dicen nada.
##
## Se queda con la pieza cuyo tiro pasa más cerca, que es la que decide el fuego.
func _residuo_de_tiro(banda: String) -> Dictionary:
	var sale := {"largo": INF, "traves": INF, "cubre": false, "listas": 0}
	if _blanco == null or not is_instance_valid(_blanco):
		return sale
	var vel_blanco := Vector3.ZERO
	if _blanco is CharacterBody3D:
		vel_blanco = (_blanco as CharacterBody3D).velocity
	var semiejes := Vector2(6.0, 6.0)
	if "recorte_radio" in _blanco:
		semiejes = _blanco.get("recorte_radio")
	# Un capitán torpe se conforma con menos: dispara cuando el tiro aún no cubre, y falla.
	semiejes /= clampf(pericia, 0.1, 1.0)

	var mejor := INF
	for c in _canones(banda):
		if not bool(c.call("listo")):
			continue
		sale["listas"] = int(sale["listas"]) + 1
		var boca: Vector3 = c.call("boca_global")
		var v0: Vector3 = c.call("velocidad_salida")
		var vuelo := Bala.tiempo_hasta(boca, v0, float(c.get("altura_mar")))
		if vuelo <= 0.0:
			continue
		var caida: Vector3 = c.call("punto_de_caida")
		var futuro := _blanco.global_position + vel_blanco * vuelo
		# ── ¿Cubre? ───────────────────────────────────────────────────────────
		# No es que la bala CAIGA dentro de la elipse del casco: eso trata al enemigo como una
		# mancha plana sobre el agua, y un barco tiene ALTO. Una bala cuyo punto de caída quede
		# veinte metros más allá pasa por encima del blanco a dos metros de altura, o sea por
		# dentro de su casco, y la `Bala` de verdad choca con él — vuela tirando un rayo contra
		# la caja de cada barco, no mirando dónde tocará el agua. Con el criterio plano esos
		# tiros se descartaban.
		#
		# Y eso es justo lo que la mar se llevaba por delante: con el casco cabeceando, el punto
		# de caída se va metros arriba y abajo entre apuntar y disparar, y casi nunca caía en
		# una elipse de 1,9 m de manga. Medido: en el mundo con mar el capitán disparaba 4 veces
		# en 45 s y en una escena sin mar, 12 (`tools/porque_no_dispara.tscn`).
		#
		# Así que se comprueba lo que de verdad decide el impacto: dónde va la bala AL LLEGAR al
		# blanco, y si eso cae dentro de su casco — en planta, su elipse; en alto, entre el agua
		# y su regala. La regala se le pregunta al barco (`altura_regala_en`), que la muestreó
		# de su propio casco.
		var agua := float(c.get("altura_mar"))
		var horizontal := _horizontal(futuro - boca)
		var falta := horizontal.length()
		var vh := _horizontal(v0).length()
		if falta > 0.01 and vh > 0.01:
			var al_llegar := Bala.punto(boca, v0, falta / vh)
			var techo := agua + 1000.0
			if _blanco.has_method("altura_regala_en"):
				var r := float(_blanco.call("altura_regala_en", futuro))
				if is_finite(r):
					techo = r
			# En los ejes del ENEMIGO, para que la elipse esté orientada con su casco: X es la
			# manga y Z la eslora.
			var p: Vector3 = _blanco.global_transform.basis.inverse() * (al_llegar - futuro)
			if (p.x * p.x) / (semiejes.x * semiejes.x) \
					+ (p.z * p.z) / (semiejes.y * semiejes.y) <= 1.0 \
					and al_llegar.y >= agua and al_llegar.y <= techo:
				sale["cubre"] = true
		# Y el error repartido en las DOS correcciones que el artillero tiene en la mano, que no
		# son los ejes del enemigo: a lo largo de la línea de tiro lo arregla la cuña, y al
		# través de ella el espeque. Así el número dice qué mando se queda corto.
		var linea := _horizontal(futuro - boca)
		if linea.length() < 0.01:
			continue
		linea = linea.normalized()
		var err := _horizontal(caida - futuro)
		var largo := err.dot(linea)
		var traves := err.dot(linea.rotated(Vector3.UP, PI * 0.5))
		if absf(largo) + absf(traves) < mejor:
			mejor = absf(largo) + absf(traves)
			sale["largo"] = largo
			sale["traves"] = traves
	return sale


## El tiro de la banda que va a disparar, para las herramientas de medida y las pruebas. Ver
## `_residuo_de_tiro`.
func residuo_de_tiro() -> Dictionary:
	return _residuo_de_tiro(_banda_que_bate())


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

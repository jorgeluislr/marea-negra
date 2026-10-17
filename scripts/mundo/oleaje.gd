extends Node
## Estado de la mar (autoload "Oleaje"): olas de Gerstner, y el ESPEJO en GDScript de lo que
## dibuja `assets/shaders/oleaje.gdshaderinc`.
##
## Existe porque la altura de la lámina hace falta en los dos sitios: el shader deforma la
## malla del agua y el barco (y el tiro, y lo que flote) pregunta desde GDScript. Si cada uno
## tuviera sus olas, el barco flotaría sobre un mar distinto del que se ve. Los coeficientes se
## calculan aquí una sola vez y se envían al material con `aplicar()`, así que lo único que se
## duplica es la suma de senos; `tools/espejo_oleaje.tscn` la compara punto a punto.
##
## El RELOJ también es uno solo (`t`, acumulado aquí y enviado como uniform) en vez de usar el
## `TIME` del shader: `TIME` corre por su cuenta y no se puede leer desde GDScript, con lo que
## las dos olas irían desfasándose sin que nada lo avisara.
##
## Cuatro trenes cruzados. Uno solo da un mar de corrugado de cartón —crestas rectas
## infinitas—, y con cuatro en abanico las crestas se cortan entre sí y aparecen los montes y
## los senos que se ven en el mar de verdad.

## Longitud de onda de cada tren, en metros. Se ELIGEN (a escala de juego: un barco de 12 m con
## olas de 200 m no vería nada); lo que no se elige es su velocidad, que sale de la relación de
## dispersión de aguas profundas. Por eso el movimiento resulta creíble aunque el tamaño no sea
## el que le tocaría al viento que sopla.
##
## **Son OCHO y sus longitudes no guardan relación entre sí a propósito.** Con cuatro, el mar
## salía casi idéntico a sí mismo corrido veinte metros —autocorrelación de **0,997**, medida con
## `tools/patron_del_mar.tscn`— y eso el ojo lo caza aunque no sepa decir qué está viendo: sumar
## unas pocas ondas planas siempre deja un desplazamiento en el que todas vuelven a encajar a la
## vez, y cuantas menos sean, más cerca cae. Ni una es múltiplo ni divisor aproximado de otra, y
## no siguen una progresión: una progresión geométrica tiene la razón constante y vuelve a
## producir encajes. La más corta no baja de 7 m porque por debajo la malla del agua ya no la
## resuelve junto a la cámara, y una ola que la rejilla no puede dibujar no sale como ola: sale
## como el patrón que hace con la rejilla. Ese detalle lo pone el rizado del shader, que va en la
## normal y no depende del mallado.
const LARGOS := [53.0, 41.0, 28.3, 22.7, 15.1, 11.9, 8.6, 6.9]
## Ángulo de cada tren respecto al viento, en grados. En abanico ancho y sin ninguno repetido ni
## simétrico: dos trenes a ±α dan un patrón de rejilla que se nota enseguida.
const ANGULOS := [3.0, -41.0, 22.0, -68.0, 55.0, -14.0, 74.0, -33.0]
## Reparto de amplitud entre los trenes. Decreciente con la longitud, como el espectro real.
const PESOS := [1.0, 0.78, 0.60, 0.46, 0.35, 0.27, 0.20, 0.15]
## Tamaño del GRUPO de cada tren, en metros: cada cuánto ese tren sube y baja de fuerza a lo
## largo del mar. Ninguno relacionado con otro ni con las longitudes de ola, por lo mismo.
const GRUPOS := [260.0, 190.0, 310.0, 145.0, 230.0, 175.0, 290.0, 205.0]
## Cuánto se hunde la amplitud de un tren en el hueco entre grupos, de 0 a 1.
const HONDURA_GRUPO := 0.55
const G := 9.81

## Altura pico a pico NOMINAL de la mar con el viento a fuerza 1, en metros. Es EL número del
## estado de la mar
##
## Ojo, la mar de verdad sale más baja que este número: los ocho trenes van cruzados y se
## cancelan entre sí, y encima cada uno se hunde en el hueco entre sus grupos. Con 1,9 aquí, bajo
## el barco se miden **1,29 m** pico a pico. Lo que se mira para saber qué tiempo hace es lo
## medido, no esto y se queda corto a propósito respecto a la realidad: con `Viento.velocidad_m_s` a 16
## (31 nudos, fuerza 7) a la mar le tocarían 5,5 m de altura significativa por Pierson-Moskowitz,
## que sobre una balandra de 12 m es un temporal permanente. Aquí manda el juego.
@export var altura_viento := 1.9
## Mar de fondo: lo que ondula aunque no sople nada. Sin esto, en calma el mar queda liso como
## una mesa, que es lo que no se quería arreglar.
@export var altura_fondo := 0.18
## Cuánto se afilan las crestas, 0 a 1. Por encima de 1 la ola se cruza consigo misma y la malla
## se pliega. 0,75 deja margen para que la suma de los cuatro trenes no llegue a hacerlo.
@export_range(0.0, 1.0) var pendiente := 0.75
## Constante de tiempo con la que la mar sigue al viento, en segundos. La mar no responde a una
## racha: tarda en levantarse y en calmarse. Sin este filtro el mar "respira" al ritmo de las
## ráfagas de `Viento` (0,1-0,5 Hz) y se ve como un latido, no como una mar.
@export var inercia := 25.0
## Constante de tiempo con la que la mar ROLA, en segundos. Mucho más larga que la de la fuerza:
## una mar levantada tarda muchísimo más en cambiar de dirección que en crecer o amainar.
##
## **Y hay una razón mecánica además de la física.** Girar el campo de olas corre la fase de cada
## punto en `k·D·Δángulo`, donde D es su distancia al PIVOTE del giro: la cresta se desplaza a
## `D·Δángulo/s` ENCIMA de su velocidad propia, y si el giro es de ida y vuelta el mar avanza y
## retrocede. Medido siguiendo una cresta con `tools/velocidad_de_las_olas.tscn`, tomando la
## dirección instantánea del viento —que bambolea 0,12 rad a 0,08 Hz—: en el pivote la cresta iba
## a sus 6 m/s, a 100 m oscilaba entre 0 y 12, y a 300 m entre **−6 y +18**, o sea que retrocedía
## a seis metros por segundo. Es un artefacto geométrico: solo se puede rolar despacio y con el
## pivote donde se mira. El pivote era el origen del mundo, que a 50 km del barco lo convertía en
## un mar corriendo a cientos de metros por segundo; desde el origen flotante es el BARCO (ver
## `_girar_en_el_pivote()`).
@export var inercia_rumbo := 90.0

## Y del plano de agua en reposo. La pone `mar.gd` desde su propio nodo, porque el agua de este
## mundo no está en el cero (está en −0,882) y devolver alturas relativas obligaría a que cada
## quien se acordara de sumarla.
var nivel := 0.0
## Reloj del oleaje. Se acumula aquí y se envía al shader: ver la nota de arriba.
var t := 0.0
## Altura pico a pico actual de la mar, en metros. Es lo que se mira para saber qué tiempo hace.
var altura := 0.0

## Entre qué distancias de la cámara se APAGA cada tren, en metros (x = empieza a perder
## amplitud, y = apagada del todo). Lo rellena `mar.gd`, que es quien conoce el tamaño de celda
## de su malla; mientras nadie lo toque no hay LOD ninguno.
##
## Es solo para lo que se ve: `altura_en()` y `normal_en()` devuelven siempre la ola entera, y
## el shader la atenúa a cero metros de la cámara en ningún grado, así que el barco y el mar
## que pisa coinciden exactamente.
var alcances := PackedVector2Array()

var _dirs: Array[Vector2] = []
var _coef: Array[Vector4] = []
var _grupo: Array[Vector4] = []
## Fase añadida de cada tren, en radianes y en DOBLE precisión: la de la ola y la de su grupo.
## Ver `_girar_en_el_pivote()` y `_al_recentrar()`.
var _fase_ola := PackedFloat64Array()
var _fase_grupo := PackedFloat64Array()
## Lo que el pivote ha recorrido EN ABSOLUTO, proyectado sobre el viento y su perpendicular (doble
## precisión). Es lo que lleva el ruido del relieve fino y de la espuma: ver `aplicar()`.
var _ruido_v := 0.0
var _ruido_l := 0.0
## Dónde estaba el pivote, en absoluto, la última vez.
var _pivote_x := 0.0
var _pivote_z := 0.0
var _pivote := Vector2.ZERO
var _con_pivote := false
var _fuerza_suave := 1.0
var _eje := Vector2.RIGHT


func _ready() -> void:
	for i in LARGOS.size():
		_dirs.append(Vector2.RIGHT)
		_coef.append(Vector4.ZERO)
		_grupo.append(Vector4.ZERO)
		_fase_ola.append(0.0)
		_fase_grupo.append(0.0)
		# Sin LOD mientras nadie lo fije: ver `alcances`.
		alcances.append(Vector2(1e9, 1e9))
	_fuerza_suave = Viento.fuerza
	_eje = _rumbo_del_viento()
	_recalcular()
	_conectar_origen.call_deferred()


func _conectar_origen() -> void:
	var o := get_node_or_null("/root/Origen")
	if o != null and not o.recentrado.is_connected(_al_recentrar):
		o.recentrado.connect(_al_recentrar)


## El mundo local se ha corrido `-d` (origen flotante) y la ola tiene que seguir donde estaba EN
## ABSOLUTO. La fase es lineal: `k·dir·(p + d) + φ = k·dir·p + (φ + k·dir·d)`, así que basta
## sumarle a cada tren `k·dir·d`, en doble y reducido a una vuelta. Sumar el origen dentro del
## shader, en cambio, daría a 50 km fases de 45.000 radianes, donde la precisión simple solo da
## pasos de 0,004: el espejo dejaría de cuadrar con GDScript y la ola corta temblaría.
##
## Se hace en el acto y no en el `_process` siguiente: el recentrado ocurre en el reloj de la
## física y el barco pregunta la ola en ese mismo paso.
func _al_recentrar(d: Vector3) -> void:
	for i in _coef.size():
		var di: Vector2 = _dirs[i]
		var g: Vector4 = _grupo[i]
		_fase_ola[i] = fposmod(_fase_ola[i] + _coef[i].x * (float(di.x) * d.x + float(di.y) * d.z), TAU)
		_fase_grupo[i] = fposmod(_fase_grupo[i] + float(g.x) * d.x + float(g.y) * d.z, TAU)
	_pivote -= Vector2(d.x, d.z)


func _process(delta: float) -> void:
	t += delta
	# La mar sigue al viento con retraso (filtro de primer orden), no a la racha.
	var k := 1.0 - exp(-delta / maxf(inercia, 0.001))
	_fuerza_suave += (Viento.fuerza - _fuerza_suave) * k
	# La mar rola hacia el viento de fondo, no hacia el de este instante: ver `inercia_rumbo`.
	var objetivo := _rumbo_del_viento()
	_eje = _eje.rotated(_eje.angle_to(objetivo)
		* (1.0 - exp(-delta / maxf(inercia_rumbo, 0.001)))).normalized()
	_recalcular()


## Hacia dónde sopla el viento DE FONDO, en planta. `Viento.direccion_base` y no
## `Viento.direccion`: la segunda lleva el bamboleo de las rachas (0,12 rad a 0,08 Hz), y una
## mar no cambia de dirección con cada racha — ni puede, sin barrer el mar entero de lado.
func _rumbo_del_viento() -> Vector2:
	var e := Vector2(Viento.direccion_base.x, Viento.direccion_base.z)
	return e.normalized() if e.length() > 0.001 else Vector2.RIGHT


## Coeficientes de los cuatro trenes a partir del viento de este instante.
func _recalcular() -> void:
	# La ola crece con el CUADRADO del viento (Pierson-Moskowitz), no en proporción: doblar el
	# viento cuadruplica la mar, y es lo que hace que una racha se note y una calma se vea.
	altura = altura_fondo + altura_viento * _fuerza_suave * _fuerza_suave
	var eje := _eje
	var suma_pesos := 0.0
	for p in PESOS:
		suma_pesos += p
	var n := LARGOS.size()
	var dirs_antes := _dirs.duplicate()
	var grupo_antes := _grupo.duplicate()
	for i in n:
		var largo: float = LARGOS[i]
		var k_ola: float = TAU / largo
		var a: float = 0.5 * altura * PESOS[i] / suma_pesos
		# Q es CUÁNTO se afila la cresta, de 0 a 1, y el límite de GPU Gems (1, cap. 1) es solo
		# un TOPE por encima del cual la ola se cruza consigo misma y la malla se pliega.
		#
		# Tomar el tope como valor —`Q = 1/(k·A·N)`— fue un error medido: Q·A es lo que el agua
		# se corre en horizontal, y con esa fórmula la amplitud se cancela y el arrastre sale
		# constante. Medido: 3,605 m de vaivén horizontal, el MISMO número con el viento a 0,15
		# que a 1,0. En calma, un mar de 21 cm de ola deslizándose tres metros y medio de un lado
		# a otro, que es lo que se veía desde cubierta como si el barco avanzase y retrocediera.
		var q: float = 0.0
		if a > 0.0001:
			q = minf(pendiente, 1.0 / (k_ola * a * float(n)))
		_dirs[i] = eje.rotated(deg_to_rad(ANGULOS[i]))
		_coef[i] = Vector4(k_ola, a, q, sqrt(G * k_ola))
		# El grupo viaja en diagonal respecto a su tren (37° fijo, para que no se confunda con
		# él) y a la VELOCIDAD DE GRUPO, que en agua profunda es la mitad de la de fase: así los
		# grupos se desplazan por dentro de sus propias olas, como en el mar.
		var k_g: float = TAU / float(GRUPOS[i])
		var d_g := _dirs[i].rotated(deg_to_rad(37.0))
		_grupo[i] = Vector4(d_g.x * k_g, d_g.y * k_g,
			k_g * 0.5 * sqrt(G / k_ola), HONDURA_GRUPO)
	_girar_en_el_pivote(dirs_antes, grupo_antes)


## Hace que el campo de olas role alrededor del BARCO y no del cero del mundo.
##
## La fase de un tren es `k·dir·p + φ`. Si `dir` cambia y φ no, todo punto a una distancia D del
## cero corre su fase `k·D·Δángulo`: el mar entero gira alrededor del cero, y cuanto más lejos,
## más deprisa barre. Con el cero en el puerto y el barco a 50 km eso es un mar resbalando a
## cientos de metros por segundo, y basta el redondeo de `dir` en precisión simple (6·10⁻⁸) por
## esos 50 km para que la ola tiemble milímetros bajo el casco cada frame.
##
## Así que a cada giro se corrige φ para que la fase EN EL PIVOTE no cambie:
## `φ' = φ − k·(dir' − dir)·pivote`. El mar sigue rolando, pero alrededor de donde se mira, como
## antes del origen flotante pasaba alrededor del barco porque el barco estaba junto al cero.
##
## Y la misma cuenta lleva el ruido del relieve fino y de la espuma, que se orienta con el viento:
## lo que se acumula es el camino del pivote proyectado sobre el viento de cada instante, y el
## shader dibuja el ruido relativo al pivote más eso (`ruido_ref`, `ruido_acum`).
func _girar_en_el_pivote(dirs_antes: Array, grupo_antes: Array) -> void:
	var piv := _pivote_actual()
	var o := get_node_or_null("/root/Origen")
	var ax: float = float(piv.x) + (o.x if o != null else 0.0)
	var az: float = float(piv.y) + (o.z if o != null else 0.0)
	if _con_pivote:
		for i in _coef.size():
			var a: Vector2 = dirs_antes[i]
			var b: Vector2 = _dirs[i]
			var ga: Vector4 = grupo_antes[i]
			var gb: Vector4 = _grupo[i]
			_fase_ola[i] = fposmod(_fase_ola[i] - _coef[i].x
				* ((float(b.x) - float(a.x)) * piv.x + (float(b.y) - float(a.y)) * piv.y), TAU)
			_fase_grupo[i] = fposmod(_fase_grupo[i]
				- ((float(gb.x) - float(ga.x)) * piv.x + (float(gb.y) - float(ga.y)) * piv.y), TAU)
		var v: Vector2 = _dirs[0]
		var dx := ax - _pivote_x
		var dz := az - _pivote_z
		_ruido_v += dx * float(v.x) + dz * float(v.y)
		_ruido_l += -dx * float(v.y) + dz * float(v.x)
	_pivote = piv
	_pivote_x = ax
	_pivote_z = az
	_con_pivote = true


## El barco activo, o la cámara si no hay barco, en coordenadas locales.
func _pivote_actual() -> Vector2:
	if not is_inside_tree():
		return _pivote
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b != null:
		return Vector2(b.global_position.x, b.global_position.z)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return Vector2(cam.global_position.x, cam.global_position.z)
	return _pivote


## Pone la mar al día con el viento de este instante, sin esperar la `inercia`.
##
## Para herramientas y pruebas: con 25 s de constante de tiempo, mirar cómo queda el mar con
## viento fuerte costaría dos minutos de espera por cada medida.
##
## Y pone a cero la fase acumulada (`_girar_en_el_pivote`), para que lo que se mide no dependa de
## lo navegado antes: esa fase sale del camino del barco y de cada rolada, así que sin esto la
## misma prueba veía otro trozo de mar según qué paquetes hubieran corrido delante — `mundo` /
## "la cresta se aclara" cayó en un trozo de mar bajo (crestas de 0,27 m, tono 0,198 contra 0,2)
## en la batería entera y daba 0,450 corrido solo. Con la fase a cero el mar es el mismo que había
## antes del origen flotante. Es un salto del mar, pero esta función ya lo es.
func asentar() -> void:
	_fuerza_suave = Viento.fuerza
	_eje = _rumbo_del_viento()
	_fase_ola.fill(0.0)
	_fase_grupo.fill(0.0)
	_ruido_v = 0.0
	_ruido_l = 0.0
	_con_pivote = false
	_recalcular()


## Desplazamiento del punto de superficie que en reposo estaba en `p` (x,z de mundo).
## y = cuánto sube, xz = cuánto se corre hacia la cresta. Espejo de `oleaje_desplaz()`.
func desplazamiento(p: Vector2, reloj := -1.0) -> Vector3:
	var tt: float = t if reloj < 0.0 else reloj
	var d := Vector3.ZERO
	for i in _coef.size():
		var c: Vector4 = _coef[i]
		if c.x <= 0.0 or c.y <= 0.0:
			continue
		var a: float = _amplitud(i, p, tt)
		var f: float = c.x * _dirs[i].dot(p) + _fase_ola[i] - c.w * tt
		d.y += a * sin(f)
		var lat: float = c.z * a * cos(f)
		d.x += _dirs[i].x * lat
		d.z += _dirs[i].y * lat
	return d


## Normal de la superficie en el punto de reposo `p`. Espejo de `oleaje_normal()`.
func normal(p: Vector2, reloj := -1.0) -> Vector3:
	var tt: float = t if reloj < 0.0 else reloj
	var n := Vector3(0.0, 1.0, 0.0)
	for i in _coef.size():
		var c: Vector4 = _coef[i]
		if c.x <= 0.0 or c.y <= 0.0:
			continue
		var f: float = c.x * _dirs[i].dot(p) + _fase_ola[i] - c.w * tt
		var ka: float = c.x * _amplitud(i, p, tt)
		n.x -= _dirs[i].x * ka * cos(f)
		n.z -= _dirs[i].y * ka * cos(f)
		n.y -= c.z * ka * sin(f)
	return n.normalized()


## Amplitud del tren `i` en el punto `p`: la suya, hundida por su grupo. Espejo de la parte de
## `oleaje_amp()` que no es LOD — el LOD no se refleja aquí a propósito, porque lo que responde
## este autoload es la ola entera (ver `alcances`).
func _amplitud(i: int, p: Vector2, tt: float) -> float:
	var g: Vector4 = _grupo[i]
	if g.w <= 0.0:
		return _coef[i].y
	return _coef[i].y * (1.0 - g.w * (0.5 + 0.5 * sin(Vector2(g.x, g.y).dot(p) + _fase_grupo[i]
		- g.z * tt)))


## Altura ABSOLUTA de la lámina de agua sobre el punto `q` del mundo (x,z), con `nivel` sumado.
##
## No es `desplazamiento(q).y`: en Gerstner el punto que acaba SOBRE `q` no salió de `q`, salió
## de más atrás porque la ola lo arrastró hacia la cresta. Hay que buscar ese origen, y se hace
## por punto fijo —tres vueltas bastan mientras `pendiente` no pase de 1—. Ignorarlo desplaza la
## lectura media longitud de onda en la cara de la ola, justo donde más se nota.
func altura_en(q: Vector2, reloj := -1.0) -> float:
	var p := q
	for _i in 3:
		var d := desplazamiento(p, reloj)
		p = q - Vector2(d.x, d.z)
	return nivel + desplazamiento(p, reloj).y


## Normal de la lámina sobre el punto `q` del mundo, con la misma corrección que `altura_en`.
func normal_en(q: Vector2, reloj := -1.0) -> Vector3:
	var p := q
	for _i in 3:
		var d := desplazamiento(p, reloj)
		p = q - Vector2(d.x, d.z)
	return normal(p, reloj)


## La ola más corta de la mar, en metros. Es la que decide cuánto hay que mallar el agua: si la
## celda no la resuelve, no se ve la mar sino un serrucho.
## Pendiente cuadrática media que pide a la superficie el viento que ha levantado esta mar
## (Cox y Munk, 1954: `0,003 + 0,00512·U`, U en m/s). Es la cifra que separa un mar de un
## cristal, y el shader la reparte entre la ola, el detalle de la normal y la rugosidad.
func pendiente_del_viento() -> float:
	return 0.003 + 0.00512 * _fuerza_suave * Viento.velocidad_m_s


## Viento que levantaría ESTA mar (Pierson-Moskowitz, mar hecha: `Hs = 0,21·U²/g`), en m/s.
##
## No es `Viento.velocidad_m_s`: la mar de este mundo está a propósito por debajo de su viento
## —a 16 m/s una mar de verdad tendría 5,5 m, y aquí tiene 2—, y la espuma tiene que ir con la
## mar que se VE. Con el viento nominal salía un 5 % de mar blanca con brisa y un 48 % con mar
## dura, y se veía exagerado.
func viento_de_la_mar() -> float:
	return sqrt(maxf(altura, 0.0) * G / 0.21)


## Fracción del mar cubierta de borreguillos (Monahan y O'Muircheartaigh, 1980:
## `3,84·10⁻⁶ · U^3,41`, U en m/s), con el viento que levanta esta mar.
func cobertura_espuma() -> float:
	return clampf(3.84e-6 * pow(viento_de_la_mar(), 3.41), 1e-7, 0.5)


## Cuánto ruido se suma a la cresta para romper la espuma, en desviaciones de lo que se pica.
const ESPUMA_RUIDO := 1.0
## Varianza de `n` en `agua_espuma()` (dos octavas de `ruido_d`), MEDIDA con la batería.
const RUIDO_VALOR2 := 0.08
## Qué parte de una mancha de espuma es blanca (el encaje deja huecos), MEDIDA con la batería.
const ESPUMA_RELLENO := 0.33


## Umbral, ancho de la transición y peso del ruido de la espuma (x, y, z) para que cubra
## `cobertura_espuma()`.
##
## Lo que se compara en el shader es lo que se PICA la cresta, `Σ Q·k·A·sin`, más un ruido; una
## suma de muchos senos de fase independiente es casi gaussiana, así que la fracción que pasa de
## un umbral sale de su desviación y del cuantil normal. Los grupos hunden cada tren entre
## `1` y `1 − HONDURA_GRUPO`, y eso le quita varianza: `E[(1 − h·s)²]` con s entre 0 y 1.
func umbral_espuma() -> Vector3:
	var s2 := 0.0
	for c in _coef:
		var j: float = c.z * c.x * c.y
		s2 += 0.5 * j * j
	var h := HONDURA_GRUPO
	s2 *= 1.0 - h + h * h * 0.375
	var ruido := ESPUMA_RUIDO * sqrt(s2)
	var total := sqrt(s2 + ruido * ruido * RUIDO_VALOR2)
	# La espuma es encaje: dentro de la mancha solo `ESPUMA_RELLENO` es blanco, así que la mancha
	# tiene que cubrir más para que el blanco medio sea el que pide el viento.
	var mancha := clampf(cobertura_espuma() / ESPUMA_RELLENO, 1e-7, 0.95)
	return Vector3(total * _cuantil_normal(1.0 - mancha), 0.15 * total, ruido)


## Inversa de la normal tipificada (Abramowitz y Stegun 26.2.23, error < 4,5·10⁻⁴).
static func _cuantil_normal(p: float) -> float:
	var q := p if p < 0.5 else 1.0 - p
	var t := sqrt(-2.0 * log(maxf(q, 1e-12)))
	var arriba := 2.515517 + 0.802853 * t + 0.010328 * t * t
	var abajo := 1.0 + 1.432788 * t + 0.189269 * t * t + 0.001308 * t * t * t
	var z := t - arriba / abajo
	return z if p >= 0.5 else -z


func longitud_mas_corta() -> float:
	var l := INF
	for x in LARGOS:
		l = minf(l, x)
	return l


## Empuja los coeficientes y el reloj a un material que incluya `oleaje.gdshaderinc`.
##
## Existe para que NADIE vuelva a escribir estos uniformes a mano: el mar que se ve y el que
## se calcula tienen que salir de los mismos números, y esta es la única forma de garantizarlo.
func aplicar(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	# COPIAS empaquetadas, no los `Array`: un `Array` va por referencia, el material se queda con
	# él y lo lee cuando dibuja, y aquí se reescribe en el sitio cada frame. Así el shader pintaba
	# las direcciones del frame en que dibujaba con la fase del frame en que se le aplicó: con el
	# barco a 1,4 km del cero local y el shader tardando 0,23 s en compilarse, 12-20 cm de ola de
	# diferencia en el espejo (paquete `origen`).
	mat.set_shader_parameter("ola_dir", PackedVector2Array(_dirs))
	mat.set_shader_parameter("ola_coef", PackedVector4Array(_coef))
	mat.set_shader_parameter("ola_grupo", PackedVector4Array(_grupo))
	var fases := PackedVector2Array()
	for i in _coef.size():
		fases.append(Vector2(_fase_ola[i], _fase_grupo[i]))
	mat.set_shader_parameter("ola_fase", fases)
	mat.set_shader_parameter("ruido_ref", _pivote)
	mat.set_shader_parameter("ruido_acum", Vector2(_ruido_v, _ruido_l))
	mat.set_shader_parameter("ola_t", t)
	mat.set_shader_parameter("ola_alcance", alcances)
	mat.set_shader_parameter("ola_altura", altura)
	mat.set_shader_parameter("pendiente_viento", pendiente_del_viento())
	var esp := umbral_espuma()
	mat.set_shader_parameter("espuma_umbral", esp.x)
	mat.set_shader_parameter("espuma_ancho", esp.y)
	mat.set_shader_parameter("espuma_ruido", esp.z)

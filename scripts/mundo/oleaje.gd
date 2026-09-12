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
## punto en `k·D·Δángulo`, donde D es su distancia al origen del mundo: la cresta se desplaza a
## `D·Δángulo/s` ENCIMA de su velocidad propia, así que el mar se mueve cada vez más rápido según
## te alejas navegando, y si el giro es de ida y vuelta el mar avanza y retrocede. Medido
## siguiendo una cresta con `tools/velocidad_de_las_olas.tscn`, tomando la dirección instantánea
## del viento —que bambolea 0,12 rad a 0,08 Hz—: en el origen la cresta iba a sus 6 m/s, a 100 m
## oscilaba entre 0 y 12, y a 300 m entre **−6 y +18**, o sea que retrocedía a seis metros por
## segundo. Es un artefacto geométrico, no se puede arreglar: solo se puede rolar despacio.
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
var _fuerza_suave := 1.0
var _eje := Vector2.RIGHT


func _ready() -> void:
	for i in LARGOS.size():
		_dirs.append(Vector2.RIGHT)
		_coef.append(Vector4.ZERO)
		_grupo.append(Vector4.ZERO)
		# Sin LOD mientras nadie lo fije: ver `alcances`.
		alcances.append(Vector2(1e9, 1e9))
	_fuerza_suave = Viento.fuerza
	_eje = _rumbo_del_viento()
	_recalcular()


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


## Pone la mar al día con el viento de este instante, sin esperar la `inercia`.
##
## Para herramientas y pruebas: con 25 s de constante de tiempo, mirar cómo queda el mar con
## viento fuerte costaría dos minutos de espera por cada medida.
func asentar() -> void:
	_fuerza_suave = Viento.fuerza
	_eje = _rumbo_del_viento()
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
		var f: float = c.x * _dirs[i].dot(p) - c.w * tt
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
		var f: float = c.x * _dirs[i].dot(p) - c.w * tt
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
	return _coef[i].y * (1.0 - g.w * (0.5 + 0.5 * sin(Vector2(g.x, g.y).dot(p) - g.z * tt)))


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
	mat.set_shader_parameter("ola_dir", _dirs)
	mat.set_shader_parameter("ola_coef", _coef)
	mat.set_shader_parameter("ola_grupo", _grupo)
	mat.set_shader_parameter("ola_t", t)
	mat.set_shader_parameter("ola_alcance", alcances)

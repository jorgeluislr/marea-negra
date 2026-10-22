class_name ClimaCaribe
extends RefCounted
## De dónde sopla el alisio en las Islas Vírgenes según la fecha. Solo funciones puras: la misma
## fecha da siempre el mismo viento, se puede probar y no hay nada que guardar.
##
## **La climatología.** El alisio del Caribe oriental sopla del E-NE todo el año, con dos
## estaciones:
## - de diciembre a abril, más del NE y más fuerte: son los "Christmas winds", el refuerzo de
##   finales de diciembre y enero, cuando el anticiclón de las Azores-Bermudas baja hacia el sur;
## - de junio a agosto, del E al ESE, con un segundo máximo en julio (el chorro de bajo nivel del
##   Caribe tiene dos picos, febrero y julio, y dos mínimos, primavera y otoño);
## - septiembre y octubre son lo más flojo y lo más del sur; de junio a noviembre es temporada de
##   huracanes (`Calendario.temporada_huracanes()`).
## Fuentes: Chris Tibbs, "Caribbean Winter Weather" (weather.mailasail.com); "Understanding Wind
## in the West Indies", Cruising World; Muñoz, Busalacchi, Nigam y Ruiz-Barradas, "Winter and
## summer structure of the Caribbean low-level jet", J. Climate 21 (2008); Wang, "Variability of
## the Caribbean Low-Level Jet", Climate Dynamics 29 (2007).
##
## **Solo la dirección.** La fuerza del viento no sale de aquí (decisión del usuario, 18-10-2026):
## el juego está afinado a `Viento.fuerza_base` y eso no se toca.
##
## **Ejes.** El rumbo es de dónde VIENE, en grados desde el norte en sentido horario, como lo da
## una carta. El mundo tiene el norte en −Z y el este en +X (`Archipielago.de_lat_lon`), y
## `Viento.direccion_base` es hacia dónde VA, así que es el opuesto: `(−sen θ, 0, cos θ)`.

## Rumbo medio de cada mes, a mediados de mes, en grados (de dónde viene).
const RUMBO_MES := [65.0, 68.0, 75.0, 82.0, 90.0, 98.0, 100.0, 102.0, 105.0, 98.0, 82.0, 68.0]

## Variación por días, en dos capas de ruido de valor sembrado por la fecha: una de "tiempo" que
## cambia cada `PERIODO_SINOPTICO` días (un frente que pasa, una vaguada) y otra día a día.
## Cada capa es un azar uniforme en ±amplitud, enlazado entre claves con un `smoothstep`.
##
## **Y tiene que rolar DESPACIO.** El mar sigue a `direccion_base` con un filtro de 90 s y, al
## girar, desplaza cada cresta en proporción a su distancia al pivote (ver `Oleaje.inercia_rumbo`).
## El `smoothstep` rola a 1,5 veces el ritmo medio en el centro del tramo: con estas cifras lo
## peor son 1,5·38°/4 días + 1,5·20°/1 día = 44° por día de juego, 0,031 °/s reales. Lo comprueba
## `clima/lento`.
const PERIODO_SINOPTICO := 4.0
const AMPLITUD_SINOPTICA := 19.0
const AMPLITUD_DIARIA := 10.0


## Rumbo (de dónde viene, grados) en el instante dado: día juliano cronológico con su fracción
## (`Calendario.instante`).
static func rumbo(instante: float) -> float:
	return rumbo_medio(fraccion_del_anio(instante)) \
		+ AMPLITUD_SINOPTICA * _ruido(instante, PERIODO_SINOPTICO, 1) \
		+ AMPLITUD_DIARIA * _ruido(instante, 1.0, 2)


## Hacia dónde sopla, en ejes del mundo: lo que va en `Viento.direccion_base`.
static func direccion(instante: float) -> Vector3:
	var r := deg_to_rad(rumbo(instante))
	return Vector3(-sin(r), 0.0, cos(r))


## Rumbo climatológico, sin variación, para una fracción del año (0 = 1 de enero).
## Interpola entre los meses de forma periódica: diciembre enlaza con enero.
static func rumbo_medio(fraccion: float) -> float:
	var x := fposmod(fraccion * 12.0 - 0.5, 12.0)
	var i := floori(x)
	return lerpf(RUMBO_MES[i], RUMBO_MES[(i + 1) % 12], x - i)


## Qué parte del año ha pasado en ese instante, de 0 a 1.
static func fraccion_del_anio(instante: float) -> float:
	var anio := Calendario.fecha_de(floori(instante)).x
	var a := Calendario.dia_juliano(anio, 1, 1)
	var b := Calendario.dia_juliano(anio + 1, 1, 1)
	return (instante - a) / float(b - a)


## Ruido de valor en [−1, 1], con claves cada `periodo` días y enlazado con `smoothstep`.
static func _ruido(instante: float, periodo: float, capa: int) -> float:
	var x := instante / periodo
	var k := floori(x)
	var f := x - k
	return lerpf(_azar(k, capa), _azar(k + 1, capa), f * f * (3.0 - 2.0 * f))


## Azar en [−1, 1] determinista para cada clave y capa: un hash entero de 32 bits, no un
## `RandomNumberGenerator`, para que la misma fecha dé lo mismo en cualquier versión de Godot.
static func _azar(k: int, capa: int) -> float:
	var h := (k * 374761393 + capa * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h) / 4294967295.0 * 2.0 - 1.0

extends Node
## Curvatura de la Tierra (autoload "Horizonte"): cuánto se hunde lo que está lejos.
##
## Sirve para dos cosas que son la misma:
##
## - **Que el mar no se acabe en un borde.** El agua es un disco de radio finito y, subiendo la
##   cámara, se veía su canto y detrás el azul plano con que el cielo pinta por debajo del
##   horizonte. Curvada, el canto cae por debajo de la línea del horizonte y deja de verse sin
##   necesidad de hacer el disco infinito.
## - **Que un barco lejano se hunda de abajo arriba**, que es como desaparece un barco de
##   verdad: primero el casco, luego las velas, y el tope del palo lo último.
##
## La caída es `d²/2R` con `d` la distancia HORIZONTAL a la cámara. Es la aproximación
## parabólica de la esfera, exacta a menos de un milímetro hasta bastante más allá del
## horizonte, y la misma fórmula que da la distancia al horizonte: se ve hasta `d = √(2Rh)`
## desde una altura `h`, o sea 1,60 km desde cubierta y 6,2 desde el tope de un palo de 30 m,
## con el radio que lleva este mundo (ver `radio_tierra`).
##
## Es un autoload y no una constante suelta porque lo tienen que usar a la vez el shader del
## agua (que hunde sus vértices) y todo lo que flote (que se hunde en GDScript): si cada uno
## llevara su número, un barco lejano acabaría flotando por encima de su propia agua.

## Radio del planeta en metros. **Una décima parte del de la Tierra**, elegido el 12 de
## septiembre de 2026 con la tabla de `tools/tras_el_horizonte.tscn` delante.
##
## Con el radio de verdad la curvatura no llega nunca a ser lo que esconde un barco: a 5 km ya
## mide 1,7 píxeles de alto a 1080p, así que desaparece por pequeño mucho antes que por
## hundirse. Encogiendo el planeta el efecto entra en las distancias a las que se navega aquí —
## el horizonte se acerca como √R y el hundimiento crece como 1/R:
##
##     Tierra × 1,00   horizonte 5,05 km   casco a 4,79 km   barco entero a 11,42 km
##     Tierra × 0,25   horizonte 2,52 km   casco a 2,39 km   barco entero a  5,71 km
##     Tierra × 0,10   horizonte 1,60 km   casco a 1,51 km   barco entero a  3,61 km   ← este
##     Tierra × 0,04   horizonte 1,01 km   casco a 958 m     barco entero a  2,28 km
##
## («casco» = cuándo se esconde el francobordo, 1,8 m; «barco entero» = los 10,24 m de la
## balandra, medidos de sus mallas.)
@export var radio_tierra := 637100.0
## Con `false` el mundo vuelve a ser plano. Está para poder medir con y sin, no para jugar.
@export var activa := true


## Cuánto se hunde algo que está a `distancia` metros en horizontal, en metros.
##
## Con el radio de este mundo (la Tierra entre diez):
##
##     500 m → 19 cm     1 km → 78 cm     2 km → 3,13 m     5 km → 19,6 m
func caida(distancia: float) -> float:
	if not activa:
		return 0.0
	return distancia * distancia / (2.0 * radio_tierra)


## Lo que se hunde el punto `p` visto desde `ojo`. Solo cuenta la separación horizontal: la
## curvatura no depende de lo alto que esté ninguno de los dos.
func caida_entre(p: Vector3, ojo: Vector3) -> float:
	return caida(Vector2(p.x - ojo.x, p.z - ojo.z).length())


## A qué distancia está el horizonte para un ojo a `altura` metros sobre el agua.
func distancia_al_horizonte(altura: float) -> float:
	return sqrt(2.0 * radio_tierra * maxf(altura, 0.0))

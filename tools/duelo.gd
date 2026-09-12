extends Node

## Dos balandras mandadas por `CapitanIA`, una contra otra, y lo que pasa contado en números.
##
## Es la herramienta que dice si la táctica sirve, y mide lo único que la juzga:
##
##   · **La distancia**, cada segundo. Un capitán que funciona la cierra hasta rondar su
##     `distancia_combate` y se queda ahí; uno que no, o se aleja, o se pega y se abordan.
##   · **A qué distancia abre fuego cada uno.** Es la prueba de que dispara por la cuenta del
##     tiro (`Canon.punto_de_caida`) y no porque el enemigo esté "cerca".
##   · **Balas tiradas y balas que TOCAN.** El porcentaje es la puntería de verdad; sin él, un
##     capitán que dispare sin parar parece agresivo y es sólo ruido.
##   · **Viradas**, para ver si la ceñida zigzaguea o navega. Un número alto con el enemigo a
##     barlovento es normal; alto con el enemigo a sotavento es que la histéresis no agarra.
##   · **La maniobra en curso**, por nombre, para poder leer la máquina de estados desde fuera.
##
## No mide tela, así que vale con `--headless`:
##     godot --path . --headless tools/duelo.tscn

const SEPARACION := 300.0   ## Metros entre las dos al empezar: lejos, para que haya que navegar.
const ESPERA := 4.0         ## Que carguen el modelo y monten la artillería (es diferida).
const DURACION := 60.0
const INFORME := 5.0        ## Cada cuánto se imprime una línea.
## Altura de la lámina de agua, la del `Water` de `main_world.tscn`.
##
## Hay que dársela a mano porque esta escena NO tiene mar: `Barco._altura_del_mar()` busca el
## agua por grupo o por nombre y, al no encontrarla, devuelve 0 — y 0 está medio metro por
## ENCIMA de la boca de los cañones, porque la balandra flota en −1,35. Con esa mentira el tiro
## caía a 41,9 m en vez de a su alcance real, y el capitán se pegaba al enemigo hasta 15 m
## creyendo que era la distancia de tiro. Una herramienta sin mar mide otro juego.
const MAR := -0.8820801

var _barcos: Array[Node3D] = []
var _capitanes: Array[Node] = []
var _tiros := {}
var _tocados := {}
var _primer_fuego := {}


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	for i in 2:
		var b := esc.instantiate() as Node3D
		b.name = "Balandra%d" % i
		# El capitán se cuelga ANTES de meter el barco en el árbol: `Barco._ready` recorre sus
		# hijos y llama a `configurar` sobre los que lo tengan, que es por donde el proyecto le
		# entrega el barco a sus componentes. Añadido después, se quedaría sin barco.
		b.set("altura_mar", MAR)
		var cap := CapitanIA.new()
		cap.name = "Capitan"
		cap.bando = "azul" if i == 0 else "rojo"
		b.add_child(cap)
		add_child(b)
		# De proa la una a la otra, separadas en X, con el viento cruzado.
		b.global_position = Vector3(SEPARACION * float(i), b.global_position.y, 0.0)
		b.rotation.y = deg_to_rad(90.0) if i == 0 else deg_to_rad(-90.0)
		_barcos.append(b)
		_capitanes.append(cap)
		_tiros[b] = 0
		_tocados[b] = 0
		_primer_fuego[b] = -1.0

	await get_tree().create_timer(ESPERA).timeout
	_enganchar_canones()
	_viento_fijo()

	_ficha_de_la_pieza()
	print("═══ Duelo: dos capitanes de IA ═══")
	print("separación inicial %.0f m, viento del +X, %.0f s\n" % [SEPARACION, DURACION])
	print(" %5s %8s  %-22s %-22s" % ["t", "dist", _barcos[0].name, _barcos[1].name])

	var t := 0.0
	var siguiente := 0.0
	while t < DURACION:
		_viento_fijo()
		if t >= siguiente:
			siguiente += INFORME
			_linea(t)
		t += get_process_delta_time()
		await get_tree().process_frame

	_resumen()
	get_tree().quit(0)


## Que dice de si misma una pieza: es lo que decide el alcance, y por tanto la distancia a la
## que el capitan se coloca. Si el tubo va inclinado, el alcance se desploma y el capitan se
## pega al enemigo sin que nada mas lo delate.
func _ficha_de_la_pieza() -> void:
	for n in _barcos[0].find_children("*", "", true, false):
		if not n.has_method("punto_de_caida"):
			continue
		var boca: Vector3 = n.call("boca_global")
		var v0: Vector3 = n.call("velocidad_salida")
		var caida: Vector3 = n.call("punto_de_caida")
		var horiz := Vector2(caida.x - boca.x, caida.z - boca.z).length()
		print("barco y=%.2f (flotacion %.2f), canon local y=%.2f, boca global y=%.2f"
			% [_barcos[0].global_position.y, float(_barcos[0].get("altura_flotacion")),
			(n as Node3D).position.y, boca.y])
		print("pieza %s: elevacion %.2f grados, mar y=%.2f, velocidad_bala %.0f" % [n.name,
			float(n.get("elevacion")), float(n.get("altura_mar")),
			float(n.get("velocidad_bala"))])
		print("  velocidad de salida (%.1f, %.1f, %.1f) = %.0f m/s, inclinada %.2f grados"
			% [v0.x, v0.y, v0.z, v0.length(), rad_to_deg(asin(v0.normalized().y))])
		print("  cae a %.1f m de la boca
" % horiz)
		return


## Se cuenta por las señales de la propia pieza: `disparo` cuando escupe e `impacto` cuando la
## bala llega. Contar `disparar_banda` no valdría — las piezas recargando no salen — y buscar
## las balas por el árbol tampoco: se borran al tocar.
func _enganchar_canones() -> void:
	for b in _barcos:
		for n in b.find_children("*", "", true, false):
			if not (n.has_method("disparar") and n.has_signal("disparo")):
				continue
			n.connect("disparo", func(_d: Vector3, _h: Vector3): _tiros[b] += 1)
			n.connect("impacto", func(_donde: Vector3, contra: Node):
				if contra != null and _barco_de(contra) != null and _barco_de(contra) != b:
					_tocados[b] += 1)


## De qué barco es un colisionador. La bala choca contra la caja del casco, que puede ser el
## propio barco o un cuerpo colgado de él, así que se sube por los padres hasta encontrar algo
## que sepa de cañones.
func _barco_de(n: Node) -> Node:
	var p := n
	while p != null:
		if p.has_method("canones_de"):
			return p
		p = p.get_parent()
	return null


func _viento_fijo() -> void:
	# Asignar `Viento.direccion` no fija nada: el autoload la recalcula cada frame desde la BASE.
	Viento.direccion_base = Vector3(1, 0, 0)
	Viento.bamboleo_dir = 0.0
	Viento.variacion_fuerza = 0.0
	Viento.fuerza_base = 1.0


func _linea(t: float) -> void:
	var d := _barcos[0].global_position.distance_to(_barcos[1].global_position)
	for i in 2:
		if _tiros[_barcos[i]] > 0 and _primer_fuego[_barcos[i]] < 0.0:
			_primer_fuego[_barcos[i]] = d
	print(" %5.1f %8.1f  %-22s %-22s" % [t, d,
		_estado(0), _estado(1)])


## Además de la maniobra, el TIMÓN que está pidiendo y el rumbo que lleva. Sin esas dos
## columnas no se distingue un capitán que decide mal de uno cuya orden no llega al casco, que
## son fallos distintos y en ficheros distintos.
func _estado(i: int) -> String:
	var cap := _capitanes[i]
	var b := _barcos[i]
	var timon: float = float(b.get("orden_timon")) if "orden_timon" in b else NAN
	return "%s t%+.2f r%+4.0f v%4.1f p%.2f/%.2f %d/%d" % [String(cap.call("maniobra_actual")).left(8),
		timon, rad_to_deg(b.global_rotation.y), float(b.get("velocidad")),
		float(cap.call("propulsion_pedida")), float(b.call("factor_viento")),
		_tocados[b], _tiros[b]]


func _resumen() -> void:
	print("\n── resumen ──")
	for i in 2:
		var b := _barcos[i]
		var tiros: int = _tiros[b]
		var tocados: int = _tocados[b]
		var pct := 100.0 * float(tocados) / float(tiros) if tiros > 0 else 0.0
		print("  %-10s %3d disparos, %3d tocados (%.0f %%), %d viradas, abrió fuego a %s"
			% [b.name, tiros, tocados, pct, int(_capitanes[i].call("viradas")),
			"%.0f m" % _primer_fuego[b] if _primer_fuego[b] >= 0.0 else "nunca"])
	print("  distancia final %.1f m" % _barcos[0].global_position.distance_to(_barcos[1].global_position))

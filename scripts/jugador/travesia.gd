class_name Travesia
extends Node

## Navegación rápida: la T del jugador recorre ×1 → ×2 → ×4 → ×1 y el juego entero corre N veces
## más deprisa —barco, mar, telas, calendario y el viento que sale de la fecha—.
##
## **Es `Engine.time_scale` con la física a 60·N Hz**, para que cada paso siga siendo de 1/60 s
## de juego. Con solo `time_scale` Godot da los mismos pasos por segundo real, cada uno N veces
## más largo, y las telas no lo aguantan: medido con `tools/coste_tiempo.tscn` navegando de través,
## a ×2 ya hay 48 aristas por encima del 25 %, a ×4 160 y a ×8 420, con 30 cm de estiramiento.
## Con el paso fino aguantan como a ×1 (8 aristas y 18 mm a ×4, igual que la base).
##
## **Y por eso no pasa de ×4.** La máquina da unos 460 pasos de física por segundo: a ×8 con el paso
## fino el juego cae a 7 fps y se queda en ×7,7. `max_physics_steps_per_frame` se deja en 8: si un
## frame va lento, el juego pierde tiempo en vez de encadenar pasos y hundirse más.
## Decidido con el usuario el 18-10-2026, frente a un avance «abstracto» que llegaba a ×32.
##
## El modo se corta solo, y no se enciende, con lo que pide atención: el ancla, el modo batalla,
## bajar a cubierta, la carta abierta, las dos velas arriadas, un barco de otro bando cerca, tierra
## o bajío a proa y un cambio de tiempo. `motivo` dice el último corte; el HUD lo enseña.
##
## Cuelga del `MandoJugador`: es una orden del jugador, no del barco, y el tiempo es global. Si el
## mando desaparece (cambio de barco con TAB) el tiempo vuelve a ×1.

signal cambiada(multiplicador: int)
signal cortada(motivo: String)

const NIVELES: Array[int] = [1, 2, 4]
## Pasos de física por segundo de JUEGO. El proyecto va a 60 Hz (ver `tela-anclas-y-60hz`).
const HZ := 60

## Un barco de otro bando a menos de esto, en metros, corta el modo.
@export var distancia_enemigo := 800.0
## Fondo por encima de esta cota (metros, negativo es fondo) cuenta como bajío.
@export var fondo_minimo := -3.0
## Cuánto se sondea por delante: lo que el barco recorrería en estos segundos REALES al
## multiplicador pedido, y nunca menos de `anticipacion_min` metros.
@export var anticipacion := 10.0
@export var anticipacion_min := 150.0
@export var paso_sondeo := 20.0
## Un viento que rola más deprisa que esto, en grados por segundo REAL, es un cambio de tiempo.
## El alisio del calendario rola 0,031 °/s reales a ×1, o sea 0,12 a ×4.
@export var rolar_maximo := 2.0
## Un cambio de `Viento.fuerza_base` mayor que esto desde que se encendió el modo lo corta.
@export var refresco_maximo := 0.1
## Cada cuánto se revisa, en segundos reales.
@export var cada := 0.25
## Cuánto se enseña el aviso de un corte, en segundos reales.
@export var duracion_aviso := 4.0

var barco: Barco
var multiplicador := 1
## Por qué se cortó (o no se encendió) la última vez.
var motivo := ""

var _usec_revision := 0
var _usec_aviso := -1
var _dir_prev := Vector3.ZERO
var _fuerza0 := 1.0


func _exit_tree() -> void:
	if multiplicador != 1:
		poner(1)


## La T: el multiplicador siguiente. Desde ×1 solo si nada lo impide.
func siguiente() -> void:
	var i := NIVELES.find(multiplicador)
	var n: int = NIVELES[(i + 1) % NIVELES.size()]
	if multiplicador == 1:
		var m := impedimento(n)
		if m != "":
			_avisar(m)
			return
	poner(n)


func poner(n: int) -> void:
	var antes := multiplicador
	multiplicador = n
	Engine.time_scale = float(n)
	Engine.physics_ticks_per_second = HZ * n
	if n > 1 and antes == 1:
		motivo = ""
		_usec_aviso = -1
		_dir_prev = Viento.direccion_base.normalized()
		_fuerza0 = Viento.fuerza_base
		_usec_revision = Time.get_ticks_usec()
	if n != antes:
		cambiada.emit(n)


## El motivo del último corte mientras dura el aviso; "" después.
func aviso() -> String:
	if _usec_aviso < 0 or Time.get_ticks_usec() - _usec_aviso > int(duracion_aviso * 1e6):
		return ""
	return motivo


func _process(_delta: float) -> void:
	if multiplicador == 1 or barco == null:
		return
	var ahora := Time.get_ticks_usec()
	var dt := (ahora - _usec_revision) / 1e6
	if dt < cada:
		return
	_usec_revision = ahora
	var m := impedimento(multiplicador)
	if m == "":
		m = _cambio_de_tiempo(dt)
	if m != "":
		poner(1)
		_avisar(m)
		cortada.emit(m)


func _avisar(m: String) -> void:
	motivo = m
	_usec_aviso = Time.get_ticks_usec()


## Lo que impide navegar a ×`n` ahora mismo, o "" si nada.
func impedimento(n: int) -> String:
	if barco == null:
		return "sin barco"
	if barco.anclado:
		return "ancla echada"
	if barco.modo_battle:
		return "modo batalla"
	if not barco.gobierno:
		return "en cubierta"
	var carta := get_tree().get_first_node_in_group("carta")
	if carta != null and bool(carta.get("abierta")):
		return "carta abierta"
	if not barco.vela_delantera and not barco.vela_trasera:
		return "velas arriadas"
	var e := _enemigo_cerca()
	if e >= 0.0:
		return "enemigo a la vista (%d m)" % roundi(e)
	var t := _tierra_a_proa(n)
	if t >= 0.0:
		return "tierra a proa (%d m)" % roundi(t)
	return ""


## El viento que rola de golpe o refresca. No va en `impedimento` porque necesita la historia
## desde la revisión anterior: al encender el modo no hay de qué comparar.
func _cambio_de_tiempo(dt_real: float) -> String:
	var d := Viento.direccion_base.normalized()
	var rola := rad_to_deg(_dir_prev.angle_to(d)) / maxf(dt_real, 0.001)
	_dir_prev = d
	if rola > rolar_maximo or absf(Viento.fuerza_base - _fuerza0) > refresco_maximo:
		return "cambio de tiempo"
	return ""


## Distancia al barco más cercano de otro bando, o −1 si no hay ninguno a menos de
## `distancia_enemigo`.
func _enemigo_cerca() -> float:
	var mio := _bando_de(barco)
	var mejor := -1.0
	var vistos := {}
	for grupo in ["barcos", "barco_activo"]:
		for n in get_tree().get_nodes_in_group(grupo):
			if n == barco or vistos.has(n) or not n is Node3D:
				continue
			vistos[n] = true
			if _bando_de(n) == mio:
				continue
			var d := (n as Node3D).global_position.distance_to(barco.global_position)
			if d < distancia_enemigo and (mejor < 0.0 or d < mejor):
				mejor = d
	return mejor


## El bando lo lleva el capitán que gobierna el barco (`CapitanIA.bando`); un barco sin capitán es
## del jugador. Es la misma regla que usa el propio capitán (`CapitanIA._bando_de`).
static func _bando_de(n: Node) -> String:
	for h in n.get_children():
		if "bando" in h:
			return String(h.get("bando"))
	return "jugador"


## Distancia al primer punto con fondo por encima de `fondo_minimo` en el rumbo que lleva el barco,
## o −1. Se sondea en ABSOLUTO, que es como está el relieve (el barco se recentra cada 2 km).
func _tierra_a_proa(n: int) -> float:
	var g := get_tree().get_first_node_in_group("tierra")
	var rel: Relieve = g.get("relieve") if g != null else null
	if rel == null or not rel.listo():
		return -1.0
	var v := Vector2(barco.velocity.x, barco.velocity.z)
	var rumbo := v.normalized()
	if v.length() < 0.5:
		var proa := -barco.global_transform.basis.z
		rumbo = Vector2(proa.x, proa.z).normalized()
	var alcance := maxf(anticipacion_min, v.length() * n * anticipacion)
	var o := Origen.a_global(barco.global_position)
	var aqui := Vector2(o.x, o.z)
	var s := 0.0
	while s < alcance:
		s = minf(s + paso_sondeo, alcance)
		if rel.altura_en(aqui + rumbo * s) > fondo_minimo:
			return s
	return -1.0

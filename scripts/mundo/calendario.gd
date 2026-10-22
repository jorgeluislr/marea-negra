extends Node
## Reloj y calendario del juego (autoload "Calendario").
##
## El tiempo de juego corre a 60 veces el real: un día dura 24 minutos. La fecha es gregoriana
## (la de España y sus Indias desde 1582) y una partida nueva empieza el 1 de marzo de 1715, en
## plena edad de oro pirata.
##
## `instante` es el día juliano CRONOLÓGICO: la parte entera es el día (`dia_juliano()`) y la
## fracción la hora desde la medianoche. Es un `float` de 64 bits, así que a 2,35 millones de días
## distingue fracciones de microsegundo.
##
## El reloj corre siempre, pero solo se GUARDA si alguien lo pide (`persistente`): lo enciende el
## nodo `Clima` de la escena principal. Las pruebas y las herramientas cargan el mismo mundo y no
## deben tocar el calendario guardado del jugador.

const INICIO := Vector3i(1715, 3, 1)
## Hora a la que empieza una partida nueva.
const HORA_INICIO := 8.0
## Segundos reales que dura un día de juego.
const SEGUNDOS_POR_DIA := 1440.0
## Cada cuánto se guarda mientras se juega, en segundos reales. Además se guarda al salir.
const GUARDAR_CADA := 30.0

var instante := 0.0
var ruta := "user://calendario.cfg"
var persistente := false
var _desde_guardado := 0.0


func _ready() -> void:
	nueva_partida()


func _process(delta: float) -> void:
	avanzar(delta)
	if persistente:
		_desde_guardado += delta
		if _desde_guardado >= GUARDAR_CADA:
			guardar()


func _notification(que: int) -> void:
	if (que == NOTIFICATION_WM_CLOSE_REQUEST or que == NOTIFICATION_EXIT_TREE) and persistente:
		guardar()


func avanzar(segundos_reales: float) -> void:
	instante += segundos_reales / SEGUNDOS_POR_DIA


func nueva_partida() -> void:
	poner(INICIO.x, INICIO.y, INICIO.z, HORA_INICIO)


func poner(anio: int, mes: int, dia: int, hora_del_dia := 12.0) -> void:
	instante = dia_juliano(anio, mes, dia) + hora_del_dia / 24.0


## Año, mes y día de hoy.
func fecha() -> Vector3i:
	return fecha_de(floori(instante))


## Hora del día, de 0 a 24.
func hora() -> float:
	return (instante - floorf(instante)) * 24.0


## De junio a noviembre, ambos incluidos (la temporada oficial del Atlántico).
func temporada_huracanes() -> bool:
	var m := fecha().y
	return m >= 6 and m <= 11


func guardar() -> bool:
	_desde_guardado = 0.0
	var cfg := ConfigFile.new()
	cfg.set_value("reloj", "instante", instante)
	return cfg.save(ruta) == OK


## Lee la fecha guardada. Devuelve false, sin tocar nada, si no había archivo.
func cargar() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(ruta) != OK or not cfg.has_section_key("reloj", "instante"):
		return false
	instante = float(cfg.get_value("reloj", "instante"))
	return true


## Número de día juliano de una fecha gregoriana (Fliegel y Van Flandern, 1968).
static func dia_juliano(anio: int, mes: int, dia: int) -> int:
	var a := (14 - mes) / 12
	var y := anio + 4800 - a
	var m := mes + 12 * a - 3
	return dia + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045


## Fecha gregoriana (año, mes, día) de un número de día juliano. Inversa de `dia_juliano()`.
static func fecha_de(j: int) -> Vector3i:
	var a := j + 32044
	var b := (4 * a + 3) / 146097
	var c := a - 146097 * b / 4
	var d := (4 * c + 3) / 1461
	var e := c - 1461 * d / 4
	var m := (5 * e + 2) / 153
	return Vector3i(100 * b + d - 4800 + m / 10, m + 3 - 12 * (m / 10), e - (153 * m + 2) / 5 + 1)

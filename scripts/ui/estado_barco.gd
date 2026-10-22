class_name EstadoBarco
extends HBoxContainer

## Fila de iconos de estado: las dos velas, el ancla, timón o cubierta y el modo batalla. Las
## teclas se leen del `MandoJugador` del barco, no se escriben aquí: si cambian, el rótulo sigue.
##
## Con el jugador andando por cubierta el teclado es del personaje, y la línea `Ayuda` lo dice.

var barco: Node

@onready var _proa := $VelaProa as IconoEstado
@onready var _popa := $VelaPopa as IconoEstado
@onready var _ancla := $Ancla as IconoEstado
@onready var _timon := $Timon as IconoEstado
@onready var _batalla := $Batalla as IconoEstado
@onready var _travesia := $Travesia as IconoEstado
## El motivo de un corte de la navegación rápida, unos segundos.
@onready var _aviso := get_node_or_null(^"../AvisoTravesia") as Label
@onready var _ayuda := get_node_or_null(^"../Ayuda") as Label


func _process(_delta: float) -> void:
	visible = barco != null
	if barco == null:
		return
	var mando := barco.get_node_or_null(^"MandoJugador")
	var gobierno := bool(barco.get("gobierno"))
	_proa.activo = bool(barco.get("vela_delantera"))
	_popa.activo = bool(barco.get("vela_trasera"))
	_ancla.activo = bool(barco.get("anclado"))
	_batalla.activo = bool(barco.get("modo_battle"))
	_timon.activo = gobierno
	_proa.poner("foque", _tecla(mando, "tecla_vela_delantera") if gobierno else "")
	_popa.poner("mayor", _tecla(mando, "tecla_vela_trasera") if gobierno else "")
	_ancla.poner("ancla", _tecla(mando, "tecla_ancla") if gobierno else "")
	_batalla.poner("batalla", _tecla(mando, "tecla_battle") if gobierno else "")
	_timon.poner("timón" if gobierno else "cubierta", _tecla(barco, "tecla_paseo"))
	if _ayuda != null:
		_ayuda.visible = not gobierno
	var tr := mando.get_node_or_null(^"Travesia") if mando != null else null
	var n := int(tr.get("multiplicador")) if tr != null else 1
	_travesia.activo = n > 1
	_travesia.triangulos = n
	_travesia.poner("×%d" % n, _tecla(mando, "tecla_travesia") if gobierno else "")
	if _aviso != null:
		var a := String(tr.call("aviso")) if tr != null else ""
		_aviso.visible = a != ""
		_aviso.text = "Travesía: %s" % a


static func _tecla(n: Node, propiedad: String) -> String:
	if n == null or not propiedad in n:
		return ""
	var k := OS.get_keycode_string(int(n.get(propiedad))).to_upper()
	return "[%s]" % _NOMBRES.get(k, k)


const _NOMBRES := {"SPACE": "ESP", "SHIFT": "MAYÚS", "UP": "↑", "DOWN": "↓",
	"LEFT": "←", "RIGHT": "→"}

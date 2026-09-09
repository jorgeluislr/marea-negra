extends CanvasLayer
## HUD provisional: muestra el barco actual y las teclas de sus acciones con su estado
## (activo/inactivo). Encuentra el barco por el grupo "barco_activo" y se reengancha
## solo cuando cambias de embarcación en runtime.
##
## Andando por cubierta (`gobierno == false` en el barco) las teclas del barco no hacen nada,
## así que en vez de anunciarlas muestra las del personaje.

var _barco: Node
var _titulo: Label
var _p1: PanelContainer
var _l1: Label
var _p2: PanelContainer
var _l2: Label
var _pa: PanelContainer
var _la: Label
var _pf: PanelContainer
var _lf: Label
var _gobierno := true


func _ready() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.position = Vector2(16, 16)
	add_child(vb)

	_titulo = Label.new()
	_titulo.add_theme_font_size_override("font_size", 20)
	_titulo.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_titulo.add_theme_constant_override("outline_size", 5)
	vb.add_child(_titulo)

	var chip1 := _crear_chip(vb); _p1 = chip1[0]; _l1 = chip1[1]
	var chip2 := _crear_chip(vb); _p2 = chip2[0]; _l2 = chip2[1]
	var chipa := _crear_chip(vb); _pa = chipa[0]; _la = chipa[1]
	var chipf := _crear_chip(vb); _pf = chipf[0]; _lf = chipf[1]


func _process(_delta: float) -> void:
	var b := get_tree().get_first_node_in_group("barco_activo")
	if b != _barco:
		_barco = b
		_conectar()
		_actualizar()
	# El paso de timón a cubierta no emite señal, así que se vigila aquí.
	var g: bool = bool(_barco.get("gobierno")) if _barco != null and "gobierno" in _barco else true
	if g != _gobierno:
		_gobierno = g
		_actualizar()


func _conectar() -> void:
	if _barco and _barco.has_signal("vela_delantera_cambiada"):
		if not _barco.vela_delantera_cambiada.is_connected(_actualizar):
			_barco.vela_delantera_cambiada.connect(_actualizar)
			_barco.vela_trasera_cambiada.connect(_actualizar)
			_barco.ancla_cambiada.connect(_actualizar)


func _crear_chip(padre: Node) -> Array:
	var panel := PanelContainer.new()
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 12)
	mc.add_theme_constant_override("margin_right", 12)
	mc.add_theme_constant_override("margin_top", 6)
	mc.add_theme_constant_override("margin_bottom", 6)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	mc.add_child(lbl)
	panel.add_child(mc)
	padre.add_child(panel)
	return [panel, lbl]


func _estilo(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	return sb


func _actualizar(_estado = null) -> void:
	if _barco == null:
		_titulo.text = "(sin barco)"
		return
	var nombre := str(_barco.nombre) if "nombre" in _barco else "Barco"
	if not _gobierno:
		# En cubierta: el barco sigue como estaba, pero el teclado es del personaje.
		_titulo.text = "%s · en cubierta" % nombre
		_set_info(_p1, _l1, "[WASD] Andar   [MAYUS] Correr")
		_set_info(_p2, _l2, "[ESPACIO] Saltar   [E] Interactuar")
		_set_info(_pa, _la, "El barco sigue con las velas puestas")
		_set_info(_pf, _lf, "[F] Volver al timon")
		return
	_titulo.text = nombre
	_set_chip(_p1, _l1, "[W] Vela proa", _barco.vela_delantera, false)
	_set_chip(_p2, _l2, "[S] Vela popa", _barco.vela_trasera, false)
	_set_chip(_pa, _la, "[ESP] Ancla", _barco.anclado, true)
	_set_info(_pf, _lf, "[F] Bajar a cubierta")


## Chip sin estado, solo informativo.
func _set_info(panel: PanelContainer, lbl: Label, texto: String) -> void:
	lbl.text = texto
	lbl.add_theme_color_override("font_color", Color(0.82, 0.84, 0.9))
	panel.add_theme_stylebox_override("panel", _estilo(Color(0.14, 0.15, 0.2, 0.7)))


func _set_chip(panel: PanelContainer, lbl: Label, nombre: String, activo: bool, es_ancla: bool) -> void:
	var estado := ""
	var col: Color
	if es_ancla:
		estado = "ANCLADO" if activo else "libre"
		col = Color(0.65, 0.25, 0.2, 0.9) if activo else Color(0.14, 0.15, 0.2, 0.7)
	else:
		estado = "abierta" if activo else "cerrada"
		col = Color(0.2, 0.55, 0.3, 0.9) if activo else Color(0.14, 0.15, 0.2, 0.7)
	lbl.text = "%s: %s" % [nombre, estado]
	lbl.add_theme_color_override("font_color", Color(1, 1, 1) if activo else Color(0.6, 0.62, 0.68))
	panel.add_theme_stylebox_override("panel", _estilo(col))

class_name CartaNautica
extends CanvasLayer

## La carta del archipiélago: un marco fijo en pantalla y, dentro, una ventana a la carta que se
## arrastra con el ratón y se acerca o aleja con la rueda. Se abre y se cierra con una tecla y se
## abre siempre centrada en el barco.
##
## Dentro de la ventana todo se dibuja en coordenadas de MUNDO llevadas a pantalla con la vista
## (`vista_centro`, `metros_por_pixel`): el papel es una baldosa anclada al mundo —por eso se
## desliza con la carta—, las costas se entintan desde los contornos del `Archipielago`, los mismos
## de los que salió el relieve, y la marca del barco va donde está el barco. Nada de eso es una
## imagen fija, así que el mundo puede crecer sin rehacer la carta.
##
## La tecla va por `_unhandled_input` y no por el Input Map, como el resto del proyecto. El ratón
## lo recoge la ventana (`gui_input`), así que mientras arrastras la carta no le llega a la cámara
## ni al personaje.

@export var carta: Carta
@export var archipielago: Archipielago
@export var tecla := KEY_M
## Cuánto margen deja la carta hasta el borde de la pantalla, en fracción de su alto.
@export_range(0.0, 0.2) var margen_pantalla := 0.03
@export var color_tinta := Color(0.24, 0.16, 0.09)
@export var color_marca := Color(0.6, 0.06, 0.04)

var abierta := false
## Qué punto del mundo (x, z) está en el centro de la ventana.
var vista_centro := Vector2.ZERO
## La escala de la ventana.
var metros_por_pixel := 6.0
## La marca del barco: su posición es la del barco en pantalla y su giro el de su proa.
var marca: Control
## La rosa de los vientos, quieta en la esquina inferior izquierda de la ventana.
var rosa: TextureRect
## Toda la tierra, en una malla en metros de mundo que la vista escala y desplaza.
var costas: MeshInstance2D

var _raiz: Control
var _ventana: Control
var _lienzo: Control
var _marco: NinePatchRect
var _raton_antes := Input.MOUSE_MODE_VISIBLE
var _arrastrando := false
var _nombres: Control


func _ready() -> void:
	add_to_group("carta")
	layer = 20
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_raiz)
	var velo := ColorRect.new()
	velo.color = Color(0, 0, 0, 0.55)
	velo.set_anchors_preset(Control.PRESET_FULL_RECT)
	velo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(velo)

	# La ventana recorta: lo que se arrastra fuera de ella no se pinta sobre el marco.
	_ventana = Control.new()
	_ventana.clip_contents = true
	_ventana.mouse_filter = Control.MOUSE_FILTER_STOP
	_ventana.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_ventana.gui_input.connect(_raton)
	_raiz.add_child(_ventana)
	_lienzo = Control.new()
	_lienzo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lienzo.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_lienzo.draw.connect(_dibujar_lienzo)
	_ventana.add_child(_lienzo)
	costas = MeshInstance2D.new()
	if carta != null:
		costas.mesh = carta.costas
	_ventana.add_child(costas)
	# Los nombres van encima de la tierra y debajo de la marca.
	var nombres := Control.new()
	nombres.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nombres.set_anchors_preset(Control.PRESET_FULL_RECT)
	nombres.draw.connect(_dibujar_nombres.bind(nombres))
	_ventana.add_child(nombres)
	_nombres = nombres
	marca = Control.new()
	marca.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marca.draw.connect(_dibujar_marca)
	_ventana.add_child(marca)

	rosa = TextureRect.new()
	rosa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rosa.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rosa.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rosa.modulate = Color(1, 1, 1, 0.9)
	if carta != null:
		rosa.texture = carta.rosa
	rosa.visible = rosa.texture != null
	_raiz.add_child(rosa)

	# El marco, encima de todo y sin centro: solo su borde.
	_marco = NinePatchRect.new()
	_marco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marco.draw_center = false
	if carta != null and carta.marco != null:
		_marco.texture = carta.marco
		var mg := carta.margenes()
		_marco.patch_margin_left = mg[0]
		_marco.patch_margin_top = mg[1]
		_marco.patch_margin_right = mg[2]
		_marco.patch_margin_bottom = mg[3]
		# Los lados se REPITEN en vez de estirarse: son volutas, y estiradas se deforman.
		_marco.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
		_marco.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
	_raiz.add_child(_marco)
	_raiz.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == tecla:
		abrir(not abierta)


func abrir(si: bool) -> void:
	if si == abierta:
		return
	abierta = si
	_raiz.visible = si
	_arrastrando = false
	if si:
		# Con la carta abierta hace falta el puntero, y al cerrarla se deja como estaba.
		_raton_antes = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if carta != null:
			metros_por_pixel = carta.metros_por_pixel
		var b := _barco()
		if b != null:
			vista_centro = _absoluta(b)
		_limitar()
		_colocar()
	else:
		Input.mouse_mode = _raton_antes


## La ventana de la carta en pantalla: el interior del marco.
func interior() -> Rect2:
	if carta == null:
		return _raiz.get_viewport_rect()
	var mg := carta.margenes()
	var r := _rect_marco()
	return Rect2(r.position + Vector2(mg[0], mg[1]),
		r.size - Vector2(mg[0] + mg[2], mg[1] + mg[3]))


## Punto del mundo (x, z) llevado a la pantalla.
func mundo_a_pantalla(p: Vector2) -> Vector2:
	return interior().get_center() + (p - vista_centro) / metros_por_pixel


## Punto de la pantalla llevado al mundo (x, z).
func pantalla_a_mundo(s: Vector2) -> Vector2:
	return vista_centro + (s - interior().get_center()) * metros_por_pixel


func _process(_delta: float) -> void:
	if abierta:
		_colocar()


func _raton(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_LEFT:
			_arrastrando = e.pressed
		elif e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom(e.global_position, e.button_index == MOUSE_BUTTON_WHEEL_UP)
		_ventana.accept_event()
	elif event is InputEventMouseMotion:
		if _arrastrando:
			# La carta va con el ratón: arrastrar a la derecha trae lo que había a la izquierda.
			vista_centro -= (event as InputEventMouseMotion).relative * metros_por_pixel
			_limitar()
		_ventana.accept_event()


## Acerca o aleja dejando quieto el punto del mundo que está bajo el ratón.
func _zoom(raton: Vector2, acercar: bool) -> void:
	if carta == null:
		return
	var bajo := pantalla_a_mundo(raton)
	var k := 1.0 / carta.paso_zoom if acercar else carta.paso_zoom
	metros_por_pixel = clampf(metros_por_pixel * k, carta.metros_por_pixel_min,
		carta.metros_por_pixel_max)
	vista_centro = bajo - (raton - interior().get_center()) * metros_por_pixel
	_limitar()


func _limitar() -> void:
	if archipielago == null:
		return
	var m := archipielago.mundo
	vista_centro = vista_centro.clamp(m.position, m.end)


func _rect_marco() -> Rect2:
	var vp := _raiz.get_viewport_rect().size
	var borde := vp.y * margen_pantalla
	return Rect2(Vector2(borde, borde), vp - Vector2(borde, borde) * 2.0)


func _colocar() -> void:
	_marco.position = _rect_marco().position
	_marco.size = _rect_marco().size
	var ven := interior()
	_ventana.position = ven.position
	_ventana.size = ven.size
	_lienzo.position = Vector2.ZERO
	_lienzo.size = ven.size
	_lienzo.queue_redraw()
	# La tierra: metros de mundo llevados a la ventana. Una malla y un transform, nada que rehacer.
	costas.scale = Vector2.ONE / metros_por_pixel
	costas.position = ven.size * 0.5 - vista_centro / metros_por_pixel
	_nombres.size = ven.size
	_nombres.queue_redraw()
	if rosa.texture != null:
		var alto := ven.size.y * carta.rosa_alto
		var t := rosa.texture.get_size()
		rosa.size = Vector2(alto * t.x / t.y, alto)
		var hueco := ven.size.y * 0.03
		rosa.position = Vector2(ven.position.x + hueco, ven.end.y - hueco - alto)
	var b := _barco()
	marca.visible = b != null
	if b == null:
		return
	# La marca es hija de la ventana: su posición va relativa a ella.
	marca.position = mundo_a_pantalla(_absoluta(b)) \
		- ven.position
	# Se dibuja apuntando arriba (norte) y se gira hasta la proa. En la carta +X es la derecha y +Z
	# abajo, igual que la pantalla, así que la proa (x, z) es ya una dirección de pantalla.
	var proa := -b.global_transform.basis.z
	marca.rotation = Vector2(0, -1).angle_to(Vector2(proa.x, proa.z))
	marca.queue_redraw()


func _barco() -> Node3D:
	return get_tree().get_first_node_in_group("barco_activo") as Node3D


## Dónde está el barco en el MAPA (x, z). Su posición en el árbol es LOCAL: el origen flotante
## recentra el mundo cada 2 km y la devuelve cerca de cero, y leída tal cual la carta "volvía" a la
## salida al rato de navegar (lo vio el usuario el 18-10-2026).
func _absoluta(n: Node3D) -> Vector2:
	var o := get_node_or_null("/root/Origen")
	var g: Vector3 = o.a_global(n.global_position) if o != null else n.global_position
	return Vector2(g.x, g.z)


func _dibujar_lienzo() -> void:
	var tam := _lienzo.size
	var origen := _ventana.position
	# El papel, anclado al mundo: la región de la baldosa que cae en la ventana, repetida.
	#
	# Dos capas de la misma baldosa a escalas que no encajan entre sí (razón áurea): una sola se
	# repetía en cuadrícula —el pliegue y las manchas cada ~250 px—, y con dos el patrón conjunto
	# no se repite a ninguna escala que se vea.
	if carta != null and carta.papel != null:
		var t := carta.papel.get_size()
		var arriba_izq := pantalla_a_mundo(origen)
		for capa in [[carta.papel_metros, Vector2.ZERO, 1.0], [carta.papel_metros * 1.618, Vector2(0.37, 0.71), 0.45]]:
			var metros: float = capa[0]
			var region := Rect2(arriba_izq / metros * t + (capa[1] as Vector2) * t,
				tam * metros_por_pixel / metros * t)
			_lienzo.draw_texture_rect_region(carta.papel, Rect2(Vector2.ZERO, tam), region,
				Color(1, 1, 1, capa[2]))
	else:
		_lienzo.draw_rect(Rect2(Vector2.ZERO, tam), Color(0.86, 0.78, 0.6))


## Los nombres de las islas que tienen nombre y se ven lo bastante grandes como para llevarlo.
func _dibujar_nombres(lienzo: Control) -> void:
	if archipielago == null:
		return
	var fuente := ThemeDB.fallback_font
	var origen := _ventana.position
	var vista := Rect2(Vector2.ZERO, lienzo.size)
	for isla in archipielago.islas:
		if isla.nombre == "":
			continue
		var r := isla.limites()
		if maxf(r.size.x, r.size.y) / metros_por_pixel < 12.0:
			continue
		# La tierra firme ocupa medio mapa: el centro de su rectángulo cae en mitad del Caribe, junto
		# a Haití, y su nombre ahí confunde más que ayuda.
		if r.size.x > archipielago.mundo.size.x * 0.5:
			continue
		var centro := mundo_a_pantalla(r.get_center()) - origen
		if not vista.grow(80.0).has_point(centro):
			continue
		lienzo.draw_string(fuente, centro + Vector2(-80, 5), isla.nombre,
			HORIZONTAL_ALIGNMENT_CENTER, 160, 15, color_tinta)


func _dibujar_marca() -> void:
	var p := PackedVector2Array([Vector2(0, -12), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)])
	marca.draw_colored_polygon(p, color_marca)
	var c := p.duplicate()
	c.append(p[0])
	marca.draw_polyline(c, color_tinta, 1.5, true)

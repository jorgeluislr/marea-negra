class_name GuiaTiro
extends MeshInstance3D

## La línea de puntería: por dónde va a pasar el tiro de la banda apuntada y dónde va a caer.
##
## Dibuja la parábola de CADA pieza de la banda y las cierra por sus puntos de caída, así que
## se ve de un vistazo la franja de mar que barre la andanada — que es lo que decide si vale
## la pena disparar o hay que seguir cayendo.
##
## Los puntos los pide a cada `Canon` (`trayectoria`), que los saca de la misma fórmula con la
## que vuela la bala. No se recalculan aquí: dos fórmulas para lo mismo es cómo una mira acaba
## mintiendo sin que se note.
##
## Se redibuja en `_process` y no cuando cambia algo, porque cambia continuamente: el barco
## está girando y cabeceando todo el rato.

@export var color_linea := Color(1.0, 0.85, 0.35, 0.55)
@export var color_caida := Color(1.0, 0.45, 0.2, 0.85)
@export var pasos := 24
@export var radio_marca := 1.2   ## Radio del círculo que marca cada punto de caída.

var _barco: Barco
var _malla: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	_malla = ImmediateMesh.new()
	mesh = _malla
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _mat
	# La guía se dibuja en coordenadas de MUNDO: los puntos de la parábola son globales y este
	# nodo cuelga del barco, que va girando. Sin esto la línea giraría dos veces.
	top_level = true
	_barco = get_parent() as Barco


func _process(_delta: float) -> void:
	_malla.clear_surfaces()
	# Se dibuja solo si hay alguien al timon y ha entrado en modo battle. Antes preguntaba por
	# `gobierno`, que era el flag con que el BARCO se silenciaba a si mismo al leer teclado;
	# con el mando fuera del barco, la pregunta correcta es si hay mando y si esta en combate.
	if _barco == null or not _barco.hay_mando() or not _barco.modo_battle or not _barco.gobierno:
		visible = false
		return
	var piezas: Array = _barco.call("canones_de", _barco.get("banda_apuntada"))
	if piezas.is_empty():
		visible = false
		return
	visible = true
	global_transform = Transform3D.IDENTITY
	_malla.surface_begin(Mesh.PRIMITIVE_LINES, _mat)
	var caidas: Array[Vector3] = []
	for c in piezas:
		var pts: PackedVector3Array = c.call("trayectoria", pasos)
		if pts.size() < 2:
			continue
		for i in pts.size() - 1:
			_segmento(pts[i], pts[i + 1], color_linea)
		caidas.append(pts[pts.size() - 1])
		_circulo(pts[pts.size() - 1], radio_marca, color_caida)
	# La franja batida: une los puntos de caída de la banda.
	for i in maxi(caidas.size() - 1, 0):
		_segmento(caidas[i], caidas[i + 1], color_caida)
	_malla.surface_end()


func _segmento(a: Vector3, b: Vector3, col: Color) -> void:
	_malla.surface_set_color(col)
	_malla.surface_add_vertex(a)
	_malla.surface_set_color(col)
	_malla.surface_add_vertex(b)


func _circulo(centro: Vector3, r: float, col: Color, lados := 20) -> void:
	var previo := centro + Vector3(r, 0, 0)
	for i in range(1, lados + 1):
		var a := TAU * float(i) / float(lados)
		var p := centro + Vector3(cos(a) * r, 0.0, sin(a) * r)
		_segmento(previo, p, col)
		previo = p

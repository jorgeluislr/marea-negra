extends Node

## Graba el vídeo de fondo del menú principal: la balandra fondeada, con el trapo aferrado y la mar
## moviéndose, en un bucle que no se nota al empalmar. Dos pasadas con el Movie Maker de Godot:
##
##     # 1) el mundo, a fotogramas PNG (cámara fija, sin HUD)
##     godot --path . --windowed --fixed-fps 30 --max-fps 60 \
##           --write-movie C:\tmp\portada\f.png tools/grabar_portada.tscn
##     # 2) el bucle, a Ogg Theora
##     godot --path . --windowed --fixed-fps 30 --max-fps 60 \
##           --write-movie res://assets/video/portada.ogv tools/grabar_portada.tscn -- montar C:\tmp\portada
##
## **La resolución no la da `--resolution`**: el Movie Maker graba al tamaño de ventana del proyecto
## y con eso salió a 1152×648. Mientras se graba hay que poner un `override.cfg` en la raíz con
## `window/size/window_width_override=1920` y `window_height_override=1080` en `[display]`, y
## BORRARLO al acabar: lo lee cualquier Godot que se abra en el proyecto, el editor incluido.
## Unos 5 min la primera pasada (a un 12 % del tiempo real) y 1 min la segunda.
##
## Y `-- foto C:\ruta` saca una sola captura del encuadre, para elegirlo sin grabar.
##
## **El empalme es un fundido.** La mar suma ocho trenes de olas de periodos que no casan, y el
## casco se mueve con su propia física, así que ningún largo de vídeo vuelve exactamente al primer
## fotograma. La primera pasada graba `BUCLE + FUNDIDO` segundos y la segunda, en los primeros
## `FUNDIDO` segundos, funde lo que vino DESPUÉS del final con el principio: al acabar el bucle se
## salta a lo que seguía de verdad, y de ahí se va pasando al principio poco a poco.

## Segundos de margen para que el barco se asiente, las telas se monten y el trapo se aferre.
const ASIENTO := 10.0
const BUCLE := 20.0
const FUNDIDO := 3.0
const FPS := 30
## Cámara en ejes del barco (x a estribor, y arriba, −z a proa) y punto al que mira. Por la aleta
## de babor mirando a proa, que es donde quedan las islas; el barco cae a la derecha del encuadre
## porque a la izquierda va la lista del menú.
const OJO := Vector3(-19.0, 3.0, 17.0)
const MIRA := Vector3(-7.5, 4.5, -3.0)

var _modo := "grabar"
var _carpeta := ""
var _cuadro := 0
var _lienzo: TextureRect
var _mezcla: ShaderMaterial


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_modo = String(args[0])
	if args.size() >= 2:
		_carpeta = String(args[1])
	if _modo == "montar":
		_montar()
		return
	get_tree().create_timer(200.0, true, false, true).timeout.connect(func():
		push_error("grabar_portada: se acabó el tiempo"); get_tree().quit(1))
	var mundo := (load("res://scenes/world/main_world.tscn") as PackedScene).instantiate()
	add_child(mundo)
	for oculto in ["HUD", "FlechasViento"]:
		var n := mundo.get_node_or_null(oculto)
		if n != null:
			n.set("visible", false)
	var musica := mundo.get_node_or_null("Musica") as AudioStreamPlayer
	if musica != null:
		musica.queue_free()
	Viento.variacion_fuerza = 0.2
	await get_tree().create_timer(2.0).timeout
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		push_error("grabar_portada: no hay barco")
		get_tree().quit(1)
		return
	b.call("set_ancla", true)
	b.call("set_vela_delantera", false)
	b.call("set_vela_trasera", false)
	var cam := Camera3D.new()
	cam.fov = 50.0
	mundo.add_child(cam)
	await get_tree().create_timer(ASIENTO - 2.5).timeout
	# Fija: si siguiera al barco el cabeceo no se vería. Se coloca con el barco ya asentado.
	var x := b.global_transform
	x.basis = Basis(Vector3.UP, x.basis.get_euler().y)
	cam.global_position = x * OJO
	cam.look_at(x * MIRA)
	cam.make_current()
	if _modo == "foto":
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_carpeta.path_join("encuadre.png"))
		get_tree().quit(0)
		return
	await get_tree().create_timer(BUCLE + FUNDIDO + 1.0).timeout
	get_tree().quit(0)


## Segunda pasada: lee los PNG de la primera y escribe el bucle con el fundido del empalme.
func _montar() -> void:
	_lienzo = TextureRect.new()
	_lienzo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lienzo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mezcla = ShaderMaterial.new()
	_mezcla.shader = Shader.new()
	_mezcla.shader.code = """
shader_type canvas_item;
uniform sampler2D despues;
uniform float peso;
void fragment() {
	COLOR = mix(texture(despues, UV), texture(TEXTURE, UV), peso);
}
"""
	_lienzo.material = _mezcla
	var capa := CanvasLayer.new()
	capa.add_child(_lienzo)
	add_child(capa)
	_poner(0)


func _process(_delta: float) -> void:
	if _modo != "montar":
		return
	_cuadro += 1
	if _cuadro >= int(BUCLE * FPS):
		get_tree().quit(0)
		return
	_poner(_cuadro)


func _poner(k: int) -> void:
	var inicio := int(ASIENTO * FPS)
	_lienzo.texture = _leer(inicio + k)
	var n_fundido := int(FUNDIDO * FPS)
	if k < n_fundido:
		_mezcla.set_shader_parameter("despues", _leer(inicio + int(BUCLE * FPS) + k))
		_mezcla.set_shader_parameter("peso", smoothstep(0.0, 1.0, float(k) / n_fundido))
	else:
		_mezcla.set_shader_parameter("peso", 1.0)


func _leer(i: int) -> Texture2D:
	var ruta := _carpeta.path_join("f%08d.png" % i)
	var img := Image.load_from_file(ruta)
	if img == null:
		push_error("grabar_portada: falta %s" % ruta)
		get_tree().quit(1)
		return null
	return ImageTexture.create_from_image(img)

extends Node

## Tiro completo de verdad: se apunta a una boya usando la GUÍA, se dispara y se mira si acusa
## el impacto. Es la comprobación de que todo el sistema encaja —cuña, guía, bala y blanco— y de
## que la guía sirve para lo que dice servir: apuntar.
##
## La elevación se busca como lo haría el jugador: subiendo la cuña hasta que el punto de caída
## que dibuja la guía se pone encima de la boya. No se calcula la parábola aparte.

@export var carpeta := ""
@export var distancia := 120.0

var _barco: Node3D
var _campo: CampoTiro
## De instancia y no local: una lambda de GDScript captura las locales POR VALOR, así que
## `tocada = true` dentro del callback no se veía fuera y el tiro bueno salía como fallo.
var _tocada := false


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	_barco.set("anclado", true)
	# Declararla del jugador: desde que el barco no se auto-anuncia, el grupo "barco_activo"
	# lo pone quien le sube el jugador a bordo, y el campo de tiro lo busca por ahí.
	# El mar de main_world. Sin esto el barco lo toma como 0, que en esta balandra queda medio
	# metro por ENCIMA de la boca: el tiro caería a 41,9 m en vez de a 62,7 y estaríamos
	# apuntando en otro juego. El campo de tiro lleva el mismo valor más abajo.
	(_barco as Barco).altura_mar = -0.882
	(_barco as Barco).tomar_mando_jugador()
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-48, 30, 0)
	luz.light_energy = 2.0
	add_child(luz)
	var ent := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.45, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.56, 0.62)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ent.environment = e
	add_child(ent)
	await get_tree().create_timer(4.5).timeout

	_campo = CampoTiro.new()
	_campo.distancias = [distancia]
	_campo.altura_mar = -0.882
	_campo.sesgo = 0.0
	add_child(_campo)
	await get_tree().create_timer(1.0).timeout

	_barco.set("modo_battle", true)
	_barco.set("banda_apuntada", "estribor")
	var piezas: Array = _barco.call("canones_de", "estribor")
	var boya: Boya = null
	for b in _campo.boyas():
		if b.global_position.x > 0.0:
			boya = b
			break
	var objetivo := boya.global_position
	print("boya de estribor a %.1f m" % Vector2(objetivo.x - _barco.global_position.x,
		objetivo.z - _barco.global_position.z).length())

	# Subir la cuña hasta que la guía ponga el impacto sobre la boya.
	var mejor := 0.0
	var mejor_err := INF
	var g := 0.0
	while g <= 12.0:
		for p in piezas:
			p.elevacion = g
		await get_tree().process_frame
		var cae: Vector3 = piezas[0].punto_de_caida()
		var err: float = Vector2(cae.x - objetivo.x, cae.z - objetivo.z).length()
		if err < mejor_err:
			mejor_err = err
			mejor = g
		g += 0.02
	for p in piezas:
		p.elevacion = mejor
	await get_tree().process_frame
	print("cuña a %.2f°, la guía dice que cae a %.2f m de la boya" % [mejor, mejor_err])

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50.0
	cam.make_current()
	cam.global_position = _barco.global_position + Vector3(-7.0, 5.0, 9.0)
	cam.look_at(_barco.global_position + Vector3(12.0, 0.0, 0.0), Vector3.UP)

	boya.tocada.connect(func(_d: Vector3, _n: int): _tocada = true)
	# Esperar a que la guía esté SOBRE la boya y disparar en ese mismo frame, que es lo que hace
	# el jugador: la línea se redibuja cada frame y refleja el cabeceo del casco en ese instante.
	# Apuntar y disparar unos frames después es tirar con datos viejos — el barco se ha movido.
	var espera := 0
	while espera < 400:
		var cae: Vector3 = piezas[0].punto_de_caida()
		if Vector2(cae.x - boya.global_position.x, cae.z - boya.global_position.z).length() < 0.90:
			break
		await get_tree().process_frame
		espera += 1
	print("disparo tras %d frames de espera al cabeceo" % espera)
	_barco.call("disparar_banda")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_foto(cam, "tiro_fogonazo.png")
	for i in 240:
		await get_tree().process_frame
		if i == 60:
			_foto(cam, "tiro_vuelo.png")
	print("ACIERTO" if _tocada else "fallo")
	cam.global_position = objetivo + Vector3(-9.0, 6.0, 9.0)
	cam.look_at(objetivo, Vector3.UP)
	_foto(cam, "tiro_boya.png")
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0 if _tocada else 1)


func _foto(_c: Camera3D, nombre: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(carpeta.path_join(nombre))
	print("FOTO %s" % nombre)

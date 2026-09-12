extends Node

## Dónde han quedado las piezas de artillería en la balandra, en foto y en números.
##
## Instancia la balandra sola (sin mar ni HUD) con su propia luz, para que la cubierta se vea:
## lo que se comprueba es si las cureñas apoyan, si la boca sale por fuera del costado y si el
## ánima pasa por encima de la regala, que es lo que hace que el montaje sea a barbeta.

@export var carpeta := ""
@export var espera := 5.0

var _barco: Node3D


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	_barco.set("anclado", true)
	# Declararla del jugador: desde que el barco no se auto-anuncia, el grupo "barco_activo"
	# lo pone quien le sube el jugador a bordo, y el campo de tiro lo busca por ahí.
	(_barco as Barco).altura_mar = -0.882   # el mar de main_world; sin esto se calcula con 0
	(_barco as Barco).tomar_mando_jugador()

	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-52, 38, 0)
	luz.light_energy = 2.2
	add_child(luz)
	var ent := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.16, 0.20)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.50, 0.58)
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ent.environment = e
	add_child(ent)

	await get_tree().create_timer(espera).timeout

	var canones: Array[Node] = []
	for h in _barco.find_children("*", "", true, false):
		if h.has_method("disparar") and h.has_method("banda"):
			canones.append(h)
	print("piezas: %d" % canones.size())
	for c in canones:
		var n3 := c as Node3D
		var boca: Vector3 = n3.call("boca_global")
		var reg: float = float(_barco.call("altura_regala_en", n3.global_position))
		print("  %-22s banda=%-9s local=%s  ánima_y=%.3f regala_y=%.3f  sobre=%+.3f"
			% [n3.name, String(c.call("banda")), str(n3.position), boca.y, reg, boca.y - reg])

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 55.0
	cam.make_current()
	var centro: Vector3 = _barco.global_position + Vector3(0, 2.0, 0)

	await _tirar(cam, centro + Vector3(9.0, 4.2, 7.0), centro, "canones_3q.png")
	await _tirar(cam, centro + Vector3(0.0, 12.0, 0.01), centro, "canones_planta.png")
	# La popa desde FUERA y a ras de agua: es donde se ve si la cureña asoma por el forro.
	var popa_e: Vector3 = _barco.to_global(Vector3(1.20, 2.0, 2.5))
	await _tirar(cam, popa_e + Vector3(3.4, -0.2, 0.6), popa_e, "popa_fuera.png")
	await _tirar(cam, popa_e + Vector3(2.0, 2.4, 1.2), popa_e, "popa_alto.png")
	var media_e: Vector3 = _barco.to_global(Vector3(1.32, 2.0, 0.6))
	await _tirar(cam, media_e + Vector3(3.4, -0.2, 0.6), media_e, "media_fuera.png")
	get_tree().quit(0)


func _tirar(cam: Camera3D, desde: Vector3, mira: Vector3, nombre: String) -> void:
	cam.global_position = desde
	cam.look_at(mira, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(carpeta.path_join(nombre))
	print("FOTO %s" % nombre)

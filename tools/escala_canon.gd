extends Node

## ¿Qué tamaño tiene que tener el cañón para esta balandra? Compara las tres escalas
## candidatas con una figura humana de 1,75 m al lado, que es la única referencia que no
## engaña: en fotos del barco solo, cualquier pieza parece del tamaño que uno espera.

@export var carpeta := ""
@export var espera := 4.0

## Calibre real de cada pieza en mm. El modelo está hecho a 84 (a 4 libras).
const CALIBRES := {"a4_libras": 84.0, "a3_libras": 76.0, "a2_libras": 64.0}

var _barco: Node3D


func _ready() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	_barco = esc.instantiate() as Node3D
	add_child(_barco)
	_barco.set("anclado", true)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-50, 35, 0)
	luz.light_energy = 2.2
	add_child(luz)
	var ent := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.16, 0.20)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.50, 0.58)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	ent.environment = e
	add_child(ent)
	await get_tree().create_timer(espera).timeout

	# Figura de referencia: 1,75 m, puesta sobre la cubierta junto a la pieza de popa.
	var pieza := _barco.find_child("canon_popa_estribor", true, false) as Node3D
	if pieza == null:
		print("no encuentro la pieza"); get_tree().quit(1); return
	var hombre := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 1.75
	hombre.mesh = cap
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.85, 0.78, 0.62)
	hombre.material_override = mm
	_barco.add_child(hombre)
	# A un metro hacia crujía de la pieza, con los pies en la cubierta (1,640 local).
	hombre.position = pieza.position + Vector3(-1.0, 0.0, 0.0)
	hombre.position.y = 1.640 + 1.75 * 0.5

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 45.0
	cam.make_current()
	for nom in CALIBRES:
		var f: float = CALIBRES[nom] / 84.0
		for c in _barco.find_children("*", "", true, false):
			if c.has_method("disparar") and c is Node3D:
				(c as Node3D).scale = Vector3.ONE * f
		print("%-10s factor %.3f  tubo %.3f m  cureña %.3f × %.3f  alto %.3f"
			% [nom, f, 2.055 * f, 1.159 * f, 0.690 * f, 0.790 * f])
		var foco := pieza.global_position
		cam.global_position = foco + Vector3(2.2, 1.5, 3.4)
		cam.look_at(foco + Vector3(-0.4, -0.2, 0), Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(carpeta.path_join("escala_%s.png" % nom))
		print("FOTO escala_%s.png" % nom)
	get_tree().quit(0)

extends Node

## Si los paños aguantan un rato LARGO navegando y virando, o se van descomponiendo.
##
## El usuario vio las velas "moviéndose sin control" en una prueba que llevaba mucho tiempo
## abierta, y hay dos explicaciones posibles que había que separar: que sea la escena parada en
## un estado raro —una herramienta que dejó el timón metido y el barco dando vueltas—, o que el
## paño se degrade de verdad con el tiempo, que sería un defecto.
##
## Se mide el estiramiento al principio y al final de un rato navegando en zigzag, con el casco
## escorando por el viento y por los virajes. Si los números del final son los del principio, el
## paño no se descompone y lo que se vio era la escena.
##
##     godot --path . tools/velas_a_la_larga.tscn

## Cuánto se navega, en segundos, y cada cuánto se cambia el timón de banda.
@export var minutos := 2.0
@export var cada_virada := 14.0


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	Viento.direccion_base = Vector3(-1, 0, -0.4)
	await get_tree().create_timer(8.0).timeout
	Oleaje.asentar()

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco")
		get_tree().quit(1)
		return
	b.set("anclado", false)

	print("\n─── las velas a la larga ───")
	await _informe(b, "al empezar")

	var t := 0.0
	var estribor := true
	var k := KEY_D
	_tecla(k, true)
	while t < minutos * 60.0:
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		if fmod(t, cada_virada) < 1.0 / 60.0:
			_tecla(k, false)
			estribor = not estribor
			k = KEY_D if estribor else KEY_A
			_tecla(k, true)
	_tecla(k, false)
	# Un respiro para que el paño se asiente antes de la foto final: lo que se busca es si quedó
	# roto, no si estaba en pleno tirón.
	for i in 180:
		await get_tree().physics_frame
	await _informe(b, "tras %.0f min" % minutos)
	get_tree().quit(0)


func _informe(b: Node3D, cuando: String) -> void:
	print("  %s:" % cuando)
	for tela in b.get_children():
		if not tela.has_method("datos_depuracion"):
			continue
		var e: Dictionary = await UtilesPruebas.estiramiento(get_tree(), tela)
		if e.is_empty():
			continue
		var c: Dictionary = await UtilesPruebas.costura(get_tree(), tela, 1.0)
		print("     %-12s estira %.4f (peor %.3f), %d aristas pasadas, costura %.4f m"
			% [str(tela.get("nombre_malla")), e["medio"], e["peor"], e["malas"], c["peor"]])


func _tecla(k: int, pulsada: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pulsada
	Input.parse_input_event(e)

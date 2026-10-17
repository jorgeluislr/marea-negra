extends Node

## Cuánto se tumba el barco, y por qué: la ola, el viento en las velas y el giro.
##
## Son tres causas distintas y hay que poder separarlas, porque se suman en el mismo ángulo. Cada
## situación deja viva UNA:
##
## - **solo ola**: en calma y anclado. Oscila alrededor de cero, así que su MEDIA debe ser ~0.
## - **de través**: navegando con el viento por el costado. Un velero se tumba a sotavento, y eso
##   es una media distinta de cero y con signo.
## - **en popa**: el viento por detrás. Empuja igual o más, pero NO tumba, porque el empuje va en
##   el plano de crujía. Es el control: si aquí sale escora, el cálculo del través está mal.
## - **virando en popa**: timón a tope con el viento por detrás, para que lo único que quede sea
##   la fuerza centrífuga. Virando de través no se puede medir: al cambiar el rumbo cambia
##   también el ángulo del viento, y lo que se lee es la mezcla de las dos.
##
## Se mide la MEDIA y no el máximo: la ola mete ±3° de vaivén que taparían lo que se busca.
##
##     godot --path . tools/escora.tscn
##
## Con ventana y sobre el mundo real: lo que se mide es el barco del juego.

const SEGUNDOS := 12.0
const ASENTARSE := 7.0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco")
		get_tree().quit(1)
		return

	print("\n─── escora ───  (positiva = estribor arriba, o sea tumbado a babor)")
	print("%-18s %13s %11s %11s %10s"
		% ["situación", "escora media", "mínima", "máxima", "cabeceo"])
	# El barco navega hacia −Z. Viento hacia −X = le entra por estribor y lo tumba a babor.
	await _medir(b, "solo ola", true, 0.0, 0.0, Vector3(-1, 0, 0))
	await _medir(b, "de través", false, 0.0, 1.0, Vector3(-1, 0, 0))
	await _medir(b, "en popa", false, 0.0, 1.0, Vector3(0, 0, -1))
	await _medir(b, "virando en popa", false, 1.0, 1.0, Vector3(0, 0, -1))
	# En popa cerrada esta balandra apenas anda, y la centrífuga va con la velocidad: la medida
	# de arriba sale casi en cero por eso y no por el cálculo. A un largo sí corre.
	await _medir(b, "a un largo", false, 0.0, 1.0, Vector3(-0.7, 0, -0.7))
	await _medir(b, "virando de largo", false, 1.0, 1.0, Vector3(-0.7, 0, -0.7))
	# SOLO EL GIRO: se apaga la escora del viento y se deja el viento propulsando. Es la única
	# forma de leer el signo del giro sin que lo tape el del viento — virando cambia el rumbo, y
	# con él la banda por la que entra el viento, así que comparar antes y después mide las dos
	# cosas mezcladas y puede salir con el signo cambiado.
	b.set("brazo_velico", 0.0)
	await _medir(b, "solo giro estribor", false, 1.0, 1.0, Vector3(-0.7, 0, -0.7))
	await _medir(b, "solo giro babor", false, -1.0, 1.0, Vector3(-0.7, 0, -0.7))
	get_tree().quit(0)


func _medir(b: Node3D, que: String, anclado: bool, timon: float, fuerza: float,
		dir: Vector3) -> void:
	Viento.fuerza_base = fuerza
	Viento.direccion_base = dir
	# Un rato antes de contar, para que coja velocidad y el filtro del casco se asiente.
	# El timón se mete con la TECLA y no escribiendo `orden_timon`: el mando del jugador la
	# reescribe en cada paso de física a partir del teclado, así que ponerla a mano no dura ni un
	# frame — medido, el giro salía en 0,00° con el timón supuestamente a tope.
	if timon != 0.0:
		_tecla(KEY_D if timon > 0.0 else KEY_A, true)
	var t := 0.0
	while t < ASENTARSE:
		b.set("anclado", anclado)
		# El barco se pasó una vez al modo "a cubierta" en mitad de una medida y dejó de
		# gobernar, así que la escora del giro salió en casi cero sin que nada lo avisara.
		b.set("gobierno", true)
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)

	var suma := 0.0
	var lo := INF
	var hi := -INF
	var cab := 0.0
	var n := 0
	t = 0.0
	while t < SEGUNDOS:
		b.set("anclado", anclado)
		b.set("gobierno", true)
		await get_tree().physics_frame
		t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		var eu := b.global_transform.basis.get_euler()
		var e := rad_to_deg(eu.z)
		suma += e
		lo = minf(lo, e)
		hi = maxf(hi, e)
		cab += rad_to_deg(eu.x)
		n += 1
	if timon != 0.0:
		_tecla(KEY_D if timon > 0.0 else KEY_A, false)
	print("%-18s %12.2f° %10.2f° %10.2f° %9.2f°"
		% [que, suma / float(maxi(n, 1)), lo, hi, cab / float(maxi(n, 1))])


func _tecla(k: int, pulsada: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pulsada
	Input.parse_input_event(e)

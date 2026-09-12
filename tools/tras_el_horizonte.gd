extends Node

## Cuánto se hunde un barco al alejarse, y a qué distancia deja de verse.
##
## La curvatura hunde lo lejano `d²/2R`, así que un barco desaparece de abajo arriba —primero
## el casco, luego las velas, el tope del palo lo último—, que es como desaparece un barco de
## verdad. Aquí se comprueba que pasa, midiendo la Y del barco en el juego y no la fórmula, y
## se ve **a qué distancias** pasa, que es lo que hay que decidir.
##
## El radio del planeta es la única palanca, y la escala real es enorme para un juego: con la
## Tierra, un barco de 10 m tarda **11,4 km** en esconderse del todo y el horizonte queda a 5 km
## desde cubierta. Si se quiere que el efecto se vea en las distancias a las que se navega aquí
## —cientos de metros, un par de kilómetros— hay que encoger el planeta, y eso acerca el
## horizonte en la misma proporción. La tabla de abajo es para elegir con números.
##
##     godot --path . tools/tras_el_horizonte.tscn
##
## Con ventana: en `--headless` no hay cámara ni render y el barco no se entera de nada.

const DISTANCIAS := [100.0, 500.0, 1000.0, 2000.0, 5000.0, 11000.0, 20000.0]
## Radios de planeta que se comparan, como fracción del de la Tierra.
const ESCALAS := [1.0, 0.25, 0.1, 0.04]


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit(1))

	var cam := Camera3D.new()
	cam.far = 25000.0
	add_child(cam)
	cam.global_position = Vector3(0, 2.0, 0)
	cam.make_current()

	var b := (load("res://scenes/barcos/balandra.tscn") as PackedScene).instantiate() as Node3D
	add_child(b)
	b.set("anclado", true)
	# Su cámara estorba: se pelea por el visor y, con el barco a 20 km, `look_at` se queja de
	# vectores colineales en cada frame.
	for c in b.find_children("*", "Camera3D", true, false):
		c.queue_free()
	await get_tree().create_timer(4.0).timeout
	cam.make_current()

	var alto: float = b.get("_alto")
	print("\n─── tras el horizonte ───")
	print("la balandra mide %.2f m del casco al tope" % alto)
	print("ojo de la cámara a %.1f m sobre el agua" % cam.global_position.y)

	# --- Medido en el juego: se aleja el barco y se mira dónde acaba.
	print("\n%-12s %12s %12s %10s %12s"
		% ["distancia", "caída m", "asoma m", "se ve", "alto en px"])
	for d in DISTANCIAS:
		b.global_position = Vector3(float(d), 0, 0)
		# El reloj del bamboleo a cero antes de cada medida: si no, los 15 cm del balanceo se
		# suman a la caída y a 100 m —donde la curvatura vale ocho décimas de milímetro— lo que
		# se mide es el bamboleo entero.
		b.set("time", 0.0)
		# Dos vueltas: la Y la fija el barco en su `_physics_process`.
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().process_frame
		var caida: float = b.get("base_y") - b.global_position.y
		var asoma: float = alto - caida
		# Lo que mide en pantalla a 1080p con 60° de campo: por debajo de un par de píxeles da
		# igual lo que haga, no se ve.
		var px: float = maxf(asoma, 0.0) / float(d) / deg_to_rad(60.0) * 1080.0
		print("%-12s %12.2f %12.2f %10s %12.1f"
			% ["%.0f m" % d, caida, asoma, "sí" if b.visible else "NO", px])

	# --- La tabla para elegir el tamaño del planeta.
	print("\nsi se encoge el planeta (la caída va con 1/R, el horizonte con √R):")
	print("%-16s %14s %16s %18s"
		% ["radio", "horizonte", "se hunde el casco", "desaparece entera"])
	var real: float = Horizonte.radio_tierra
	for e in ESCALAS:
		Horizonte.radio_tierra = real * float(e)
		# Dónde se hunde 1,8 m (el francobordo, o sea cuando el casco empieza a esconderse) y
		# dónde se hunden los 10,24 m enteros.
		print("%-16s %14s %16s %18s"
			% ["Tierra × %.2f" % e,
				_km(Horizonte.distancia_al_horizonte(2.0)),
				_km(sqrt(2.0 * Horizonte.radio_tierra * 1.8)),
				_km(sqrt(2.0 * Horizonte.radio_tierra * alto))])
	Horizonte.radio_tierra = real
	get_tree().quit(0)


func _km(m: float) -> String:
	return "%.2f km" % (m / 1000.0) if m >= 1000.0 else "%.0f m" % m

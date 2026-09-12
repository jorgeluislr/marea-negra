extends Node

## ¿Detecta el capitán de IA al barco del JUGADOR, y lo ataca? Medido sobre la escena de juego
## de verdad (`scenes/world/escaramuza.tscn`), no sobre un montaje aparte.
##
## Se mide sobre la escena real a propósito. En `tools/duelo.tscn` los dos barcos los instancia
## la propia herramienta y les cuelga el capitán a mano; aquí el barco del jugador lo pone
## `GestorBarcos` y el enemigo lo pone `Escuadra`, que es la cadena que corre cuando el usuario
## le da al play. Un capitán que funcione en el duelo y no encuentre a nadie en el juego es
## exactamente el fallo que esta herramienta existe para cazar.
##
## El jugador NO toca las teclas: su balandra navega sola con el viento. Así se ve lo que hace
## el enemigo contra un blanco que se mueve, que es el caso difícil.
##
##     godot --path . --headless tools/ve_al_jugador.tscn

const ESPERA := 6.0
const DURACION := 150.0
const INFORME := 15.0
## Con el jugador FONDEADO se mide el otro caso, y es el que se ve al jugar: te paras a pelear.
## Hacen falta los dos. Huyendo en popa a la misma velocidad que el enemigo la caza no se cierra
## nunca —eso es fisica, no tonteria de la IA— y el unico caso donde se puede juzgar la punteria
## es con el blanco quieto o maniobrando.
const JUGADOR_FONDEADO := true

var _mundo: Node
var _tiros := 0
var _tocados := 0


func _ready() -> void:
	var esc := load("res://scenes/world/escaramuza.tscn") as PackedScene
	_mundo = esc.instantiate()
	add_child(_mundo)
	await get_tree().create_timer(ESPERA).timeout

	var jugador := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var enemigo := _enemigo()
	if jugador == null or enemigo == null:
		print("FALLO: jugador=%s enemigo=%s" % [jugador, enemigo])
		get_tree().quit(1)
		return
	var cap := enemigo.get_node_or_null(^"Capitan")
	_enganchar(enemigo)
	if JUGADOR_FONDEADO:
		jugador.set("anclado", true)

	print("═══ ¿Ve el enemigo al jugador? ═══")
	print("jugador: %s   enemigo: %s" % [jugador.name, enemigo.name])
	print(" %5s %8s  %-22s %-8s %s" % ["t", "dist", "maniobra", "tiros", "blanco"])

	var t := 0.0
	var siguiente := 0.0
	while t < DURACION:
		if t >= siguiente:
			siguiente += INFORME
			var d: float = enemigo.global_position.distance_to(jugador.global_position)
			var b: Node3D = cap.call("blanco")
			# Lo que decide la pregunta: que el blanco sea EL BARCO DEL JUGADOR y no otro nodo.
			var quien := "(ninguno)" if b == null else \
				("EL JUGADOR" if b == jugador else String(b.name))
			print(" %5.1f %8.1f  %-22s %-8s %s"
				% [t, d, String(cap.call("maniobra_actual")), "%d/%d" % [_tocados, _tiros], quien])
		t += get_process_delta_time()
		await get_tree().process_frame

	print("\n── resumen ──")
	print("  el enemigo disparó %d veces y acertó %d" % [_tiros, _tocados])
	print("  distancia final %.1f m"
		% _enemigo().global_position.distance_to(jugador.global_position))
	get_tree().quit(0)


## El barco enemigo: el que lleva un capitán de IA. No por nombre, que lo pone la escuadra y
## podría cambiar.
func _enemigo() -> Node3D:
	for n in _mundo.find_children("*", "CharacterBody3D", true, false):
		if n.get_node_or_null(^"Capitan") != null:
			return n as Node3D
	return null


func _enganchar(enemigo: Node3D) -> void:
	for n in enemigo.find_children("*", "", true, false):
		if not (n.has_method("disparar") and n.has_signal("disparo")):
			continue
		n.connect("disparo", func(_d: Vector3, _h: Vector3): _tiros += 1)
		n.connect("impacto", func(_donde: Vector3, contra: Node):
			if contra != null:
				_tocados += 1)

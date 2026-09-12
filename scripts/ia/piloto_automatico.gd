extends Node
## Le pone un `CapitanIA` al barco DEL JUGADOR, para verlo pelear sin tocar el teclado.
##
## Es la otra mitad de lo que el capitán prometía: el mismo que lleva un enemigo puede llevar un
## barco nuestro. Aquí sirve para mirar un duelo entre dos IA desde la cámara de siempre; el día
## que haga falta un piloto automático de verdad —tener el timón mientras andas por cubierta—
## este es el nodo.
##
## Convive con `MandoJugador`: el mando del teclado sigue puesto y no se quita. Si tocas las
## teclas, tus órdenes y las del capitán se pisan (gana la última del frame), así que mientras
## esto esté activo lo suyo es mirar. Quitarlo sería peor: dejaría el barco sin teclado para el
## resto de la partida.
##
## El barco del jugador no existe al arrancar —lo instancia `GestorBarcos` en diferido—, así que
## hay que esperarlo en vez de buscarlo una vez y rendirse.

@export var activo := true
@export var bando := "jugador"
@export_range(0.1, 1.0) var pericia := 1.0
## Segundos que se espera al barco antes de darse por vencido.
@export var espera_max := 5.0

var _esperado := 0.0
var _puesto := false


func _process(delta: float) -> void:
	if not activo or _puesto:
		set_process(false)
		return
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		_esperado += delta
		if _esperado > espera_max:
			push_warning("PilotoAutomatico: no apareció ningún barco del jugador.")
			set_process(false)
		return
	if b.get_node_or_null(^"Capitan") != null:
		_puesto = true
		return
	var cap := CapitanIA.new()
	cap.name = "Capitan"
	cap.bando = bando
	cap.pericia = pericia
	# `configurar` no se le va a llamar —el barco ya hizo su `_ready` hace rato—, así que el
	# capitán se busca el barco solo por su padre. Por eso `CapitanIA` admite las dos vías.
	b.add_child(cap)
	_puesto = true
	print("PilotoAutomatico: %s queda al mando de %s (bando %s)" % [cap.name, b.name, bando])

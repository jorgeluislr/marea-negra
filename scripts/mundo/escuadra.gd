extends Node3D
## Suelta una escuadra de barcos mandados por IA alrededor de este punto.
##
## Es el equivalente de `GestorBarcos` para el otro bando: aquel instancia el barco del JUGADOR
## y le pone el mando del teclado (`tomar_mando_jugador`), y éste instancia los enemigos y les
## pone un `CapitanIA`. Los dos hacen lo mismo —poner a alguien al timón— y por eso ninguno de
## los dos vive dentro de `Barco`: quién manda un barco no lo decide el barco.
##
## Los barcos se cuelgan del PADRE y no de este nodo, igual que hace `GestorBarcos`, para que
## sus transforms sean de mundo. Si colgaran de aquí, moverlo en el editor arrastraría la
## escuadra entera y las posiciones dejarían de querer decir lo que dicen.

## Qué barco sale. Vacío, no sale ninguno y este nodo no cuesta nada.
@export var barco: PackedScene

## Cuántos. Se reparten en línea de fila separados `separacion` metros, que es como navegaba
## una división: uno detrás de otro y no en racimo.
@export var cuantos := 1

## Bando al que pertenecen. Tiene que ser DISTINTO del del jugador (`jugador`, que es lo que
## `CapitanIA` supone para todo barco que no declare bando) o no se atacarán.
@export var bando := "enemigo"

## Pericia de sus capitanes: 0,1 grumete, 1 artillero de escuela. Ver `CapitanIA.pericia`.
@export_range(0.1, 1.0) var pericia := 1.0

## A qué distancia de este nodo aparece el primero, y hacia dónde. El rumbo inicial se les pone
## mirando al punto de origen, que es donde estará el jugador: así el encuentro empieza de cara
## y no con los dos buscándose.
@export var distancia := 220.0
@export var demora := 45.0        ## Grados desde +X, en el plano del agua.
@export var separacion := 60.0

## Con esto puesto, los enemigos salen ya con blanco y no hay que esperar a que se busquen.
@export var anunciar := true


func _ready() -> void:
	if barco == null or cuantos <= 0:
		return
	_soltar.call_deferred()


func _soltar() -> void:
	var dir := Vector3(cos(deg_to_rad(demora)), 0.0, sin(deg_to_rad(demora)))
	for i in cuantos:
		var b := barco.instantiate() as Node3D
		if b == null:
			continue
		b.name = "Enemigo%d" % (i + 1)
		var cap := CapitanIA.new()
		cap.name = "Capitan"
		cap.bando = bando
		cap.pericia = pericia
		# El capitán se cuelga ANTES de entrar al árbol: `Barco._ready` recorre sus hijos y
		# llama a `configurar` sobre los que lo tengan. Puesto después, se queda sin barco.
		b.add_child(cap)
		if "bando" in b:
			b.set("bando", bando)
		get_parent().add_child(b)
		# Sólo x y z: la Y la gobierna el propio barco (`altura_flotacion` y el balanceo), y
		# pisársela lo deja flotando a otra altura que el del jugador.
		var sitio := global_position + dir * (distancia + separacion * float(i))
		b.global_position = Vector3(sitio.x, b.global_position.y, sitio.z)
		# De cara al punto de encuentro. `look_at` mira con −Z, que es justo la proa.
		var hacia := global_position - b.global_position
		hacia.y = 0.0
		if hacia.length() > 0.01:
			b.look_at(b.global_position + hacia, Vector3.UP)
		if anunciar:
			print("Escuadra: %s (%s, pericia %.1f) a %.0f m" % [b.name, bando, pericia,
				global_position.distance_to(b.global_position)])

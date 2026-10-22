class_name Hud
extends CanvasLayer

## HUD de navegación y combate. Busca el barco del jugador y se lo pasa a cada pieza; ninguna
## guarda estado propio del barco: todo se lee de él cada frame.
##
##   Arriba-izquierda  `Danos`    silueta tumbada con la integridad por zonas.
##   Arriba-centro     `Cartela`  nombre y tipo; a su derecha `Corredera`, los nudos.
##   Abajo-izquierda   `Rosa`     rumbo y viento.
##   Abajo-centro      `Estado`   velas, ancla, timón/cubierta, batalla, con su tecla.
##   Abajo-derecha     `Bateria`  solo en modo batalla: cada cañón en su sitio y su carga.

var barco: Node


func _process(_delta: float) -> void:
	var b := _buscar_barco()
	if b == barco:
		return
	barco = b
	for hijo in get_children():
		if "barco" in hijo:
			hijo.set("barco", b)


## El barco que lleva el MANDO del jugador. En combate puede haber más de uno en el grupo, y el
## HUD es del que gobierna el jugador.
func _buscar_barco() -> Node:
	var primero: Node = null
	for b in get_tree().get_nodes_in_group("barco_activo"):
		if primero == null:
			primero = b
		if b.has_method("hay_mando") and b.call("hay_mando"):
			return b
	return primero

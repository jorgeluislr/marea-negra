class_name CampoTiro
extends Node3D

## Siembra boyas a distancias conocidas del barco y lleva la cuenta de los impactos.
##
## Las pone a una distancia MEDIDA y no repartidas a ojo porque su razón de ser es calibrar: con
## la cuña a tanto, la bala cae a tanto. Van a una banda y a la otra para poder practicar el
## viraje entre andanadas.

@export var distancias: Array[float] = [60.0, 120.0, 200.0, 320.0]
@export var altura_mar := INF
## Cuánto se separan en el eje del barco, para que no queden todas en fila india.
@export var sesgo := 40.0

var _boyas: Array[Boya] = []
var aciertos := 0


func _ready() -> void:
	call_deferred("_sembrar")


func _sembrar() -> void:
	var barco := get_tree().get_first_node_in_group("barco_activo") as Node3D
	var origen := barco.global_position if barco != null else Vector3.ZERO
	var mar := altura_mar
	if not is_finite(mar):
		var agua := get_tree().current_scene.find_child("Water", true, false) as Node3D
		mar = agua.global_position.y if agua != null else 0.0
	var i := 0
	for d in distancias:
		for lado in [1.0, -1.0]:
			var b := Boya.new()
			b.name = "Boya_%s_%dm" % ["e" if lado > 0.0 else "b", int(d)]
			b.altura_mar = mar
			add_child(b)
			b.global_position = Vector3(origen.x + lado * d, mar, origen.z + sesgo * (float(i) - 1.5))
			b.tocada.connect(_apuntar_acierto.bind(b))
			_boyas.append(b)
		i += 1
	print("campo de tiro: %d boyas a %s m" % [_boyas.size(), str(distancias)])


func _apuntar_acierto(_donde: Vector3, _total: int, b: Boya) -> void:
	aciertos += 1
	print("¡TOCADA! %s (aciertos: %d)" % [b.name, aciertos])


## Las boyas sembradas, para que las pruebas y el HUD no tengan que buscarlas por el árbol.
func boyas() -> Array[Boya]:
	return _boyas

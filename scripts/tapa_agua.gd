extends MeshInstance3D
## "Cubierta/sentina": tapa opaca que oculta el plano de agua que se ve dentro del
## casco semisumergido. Sigue al barco en horizontal (por ser hija suya) y se fija
## en vertical al nivel del mar, así siempre queda justo en la línea de flotación
## aunque muevas o subas/bajes el barco.

@export var altura_agua := 0.0  # Y del plano de agua en el mundo (el mar está en y=0)


func _process(_delta: float) -> void:
	var p := global_position
	p.y = altura_agua
	global_position = p

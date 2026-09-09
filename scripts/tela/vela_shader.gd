class_name VelaShader
extends TelaShader

## Vela dibujada por el shader de tela: ondea con `TelaShader` y, además, se IZA y se TRIMA
## como cualquier vela, moviendo los huesos de su aparejo.
##
## Es la vela de la lancha, la barca y la goleta. En esos tres el casco y la vela son UNA sola
## malla (`Mesh_0`, 444.835 vértices en la lancha) y qué parte ondea lo decide el canal ROJO de
## `Col`, no la separación en mallas — por eso este nodo anima la malla entera y aun así es "la
## vela": lo que la hace una vela es su aparejo, no de qué trozo de geometría se dibuja.
##
## Se iza y se trima exactamente igual que una `VelaFisica` porque comparten el mismo `Aparejo`;
## lo único distinto es cómo se pinta el paño.

## A qué orden del barco responde esta vela. El barco abre y cierra "la de proa" y "la de popa"
## (W y S); cada vela sabe cuál es.
@export_enum("Delantera", "Trasera", "Ambas") var mando := 1

## Sus drizas y su trimado. Cada vela necesita el SUYO: el recurso guarda estado.
@export var aparejo: Aparejo


func _montado(barco: Node3D) -> void:
	if aparejo != null:
		aparejo.preparar(_skel, barco)


## Sube el paño. Con `inmediato` se planta arriba sin animación (al arrancar la escena).
func izar(inmediato := false) -> void:
	if aparejo != null:
		aparejo.izar(inmediato)


## Baja el paño.
func arriar(inmediato := false) -> void:
	if aparejo != null:
		aparejo.arriar(inmediato)


func esta_izada() -> bool:
	return aparejo == null or aparejo.esta_izada()


## Orienta la percha a sotavento. Público porque es lo que una vela sabe hacer, aunque hoy
## nadie se lo ordene desde fuera: lo dispara ella misma con el viento de cada frame.
func trimar(delta: float) -> void:
	if aparejo != null:
		aparejo.trimar(delta)


## El aparejo se mueve antes de que la base refresque los parámetros del shader, por el mismo
## motivo que en la tela física: que lo que se dibuje sea la percha de este frame.
func _process(delta: float) -> void:
	if aparejo != null:
		aparejo.paso(delta)
	super(delta)

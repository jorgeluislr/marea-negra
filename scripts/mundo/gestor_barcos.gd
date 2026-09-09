extends Node3D
## Selector de embarcación en runtime. Instancia el barco elegido en este punto y
## permite cambiar con una tecla (TAB por defecto). El barco nuevo hereda la
## posición/rumbo del anterior. El agua, las flechas y el HUD lo reconocen por el
## grupo "barco_activo", así que no hay que cablear nada más.

@export var barcos: Array[PackedScene] = []   # lista de escenas de barco (lancha, balandra…)
@export var indice_inicial := 0
@export var altura_flotacion := 1.7           # Y a la que flota el barco (nivel de cubierta)
@export var tecla_cambiar := KEY_TAB

var _indice := 0
var _actual: Node3D


func _ready() -> void:
	if barcos.is_empty():
		push_warning("GestorBarcos: la lista 'barcos' está vacía.")
		return
	_indice = clampi(indice_inicial, 0, barcos.size() - 1)
	# Diferido: en _ready el padre (MainWorld) aún está montando sus hijos y add_child()
	# sobre él falla ("Parent node is busy setting up children"). Se instancia al terminar.
	_instanciar.call_deferred(_pose_inicial())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == tecla_cambiar:
		if barcos.size() > 1:
			_siguiente()


func _siguiente() -> void:
	var pose := _pose_actual()
	_indice = (_indice + 1) % barcos.size()
	_instanciar(pose)


# Instancia el barco actual con la pose dada (se añade al mundo, no como hijo del gestor,
# para que sus transforms sean en espacio mundo).
func _instanciar(pose: Transform3D) -> void:
	if _actual and is_instance_valid(_actual):
		_actual.remove_from_group("barco_activo")  # que el grupo no lo tenga ni un frame
		# Sacarlo del árbol YA (no solo queue_free, que es diferido): si sigue presente este
		# frame, su colisión solapa con el barco nuevo (misma posición) y move_and_slide
		# empuja al nuevo a otro sitio. remove_child lo quita del mundo físico al instante.
		var padre_ant := _actual.get_parent()
		if padre_ant:
			padre_ant.remove_child(_actual)
		_actual.queue_free()
		_actual = null

	var esc := barcos[_indice]
	if esc == null:
		return
	var b := esc.instantiate()
	if b is Node3D:
		(b as Node3D).transform = pose   # colocarlo ANTES de entrar al árbol (para base_y)
	get_parent().add_child(b)
	_actual = b as Node3D


func _pose_inicial() -> Transform3D:
	return Transform3D(Basis(), Vector3(global_position.x, altura_flotacion, global_position.z))


func _pose_actual() -> Transform3D:
	if _actual and is_instance_valid(_actual):
		var t := _actual.global_transform
		t.origin.y = altura_flotacion   # reponer altura (evita deriva por el balanceo)
		return t
	return _pose_inicial()

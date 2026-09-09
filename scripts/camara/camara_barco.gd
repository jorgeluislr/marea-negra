extends Camera3D
## Cámara de seguimiento del barco (chase cam): se coloca por DETRÁS y en ALTO,
## mirando a la lancha, y la sigue cuando gira o navega. Va como hija del barco.

@export var distancia := 12.0   # cuánto por detrás del barco
@export var altura := 6.0       # cuánto por encima
@export var mira_altura := 1.5  # a qué altura del barco apunta la mirada
@export var suavizado := 8.0    # mayor = sigue más rígido; 0 = instantáneo


func _ready() -> void:
	current = true


func _physics_process(delta: float) -> void:
	var barco := get_parent_node_3d()
	if barco == null:
		return
	# "Detrás" = sentido contrario a la proa (el barco avanza hacia -Z local).
	var fwd := -barco.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	var objetivo := barco.global_position - fwd * distancia + Vector3.UP * altura
	if suavizado > 0.0:
		global_position = global_position.lerp(objetivo, clampf(delta * suavizado, 0.0, 1.0))
	else:
		global_position = objetivo

	look_at(barco.global_position + Vector3.UP * mira_altura, Vector3.UP)

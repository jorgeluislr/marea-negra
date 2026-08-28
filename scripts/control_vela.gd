extends Node3D
## Trimado de la vela: gira el hueso 'vela' del esqueleto hacia SOTAVENTO (el lado hacia
## donde sopla el viento), limitado a ±angulo_max grados. Así la vela "sigue" al viento.
##
## No-op si el barco no tiene esqueleto de vela (por ahora solo la lancha). Se coloca como
## hijo del barco (CharacterBody3D); busca el Skeleton3D en el subárbol del barco.
##
## Eje: en Blender el balanceo lateral es sobre Z (vertical); al pasar a glTF/Godot eso es
## el eje Y. Si el giro sale mal orientado, prueba otro 'eje' o marca 'invertir'.

@export var nombre_hueso := "vela"
@export_range(0.0, 45.0) var angulo_max := 10.0    ## Grados máximos a cada lado.
@export var eje := Vector3(0, 1, 0)                ## Eje LOCAL del hueso alrededor del que gira.
@export var invertir := false                       ## Invierte el sentido del giro.
@export_range(0.5, 20.0) var suavizado := 4.0      ## Rapidez con que la vela sigue al viento.

var _skel: Skeleton3D
var _hueso := -1
var _rot_reposo := Quaternion.IDENTITY
var _barco: Node3D
var _angulo := 0.0


func _ready() -> void:
	_barco = _buscar_barco()
	_skel = _buscar_skeleton(_barco if _barco else self)
	if _skel:
		_hueso = _skel.find_bone(nombre_hueso)
		if _hueso >= 0:
			_rot_reposo = _skel.get_bone_rest(_hueso).basis.get_rotation_quaternion()
	if _hueso < 0:
		# Este barco no lleva esqueleto de vela: no hacemos nada.
		set_process(false)


func _buscar_barco() -> Node3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n as Node3D
		n = n.get_parent()
	return get_parent() as Node3D


func _buscar_skeleton(raiz: Node) -> Skeleton3D:
	if raiz == null:
		return null
	for c in raiz.find_children("*", "Skeleton3D", true, false):
		return c as Skeleton3D
	return null


func _process(delta: float) -> void:
	# Viento del mundo -> espacio local del BARCO. Su componente lateral (estribor = +X)
	# decide hacia qué lado va la vela (a SOTAVENTO, a favor del viento).
	var base := (_barco if _barco else self).global_transform.basis
	var viento_local := base.inverse() * Viento.direccion
	var lateral := clampf(-viento_local.x, -1.0, 1.0)   # signo para que caiga a sotavento
	if invertir:
		lateral = -lateral
	var objetivo := lateral * deg_to_rad(angulo_max)

	# Seguimiento suave (no salta): la vela va girando hacia el objetivo.
	_angulo = lerpf(_angulo, objetivo, clampf(suavizado * delta, 0.0, 1.0))

	# Pose local del hueso = rotación de reposo + giro alrededor del eje indicado.
	var q := _rot_reposo * Quaternion(eje.normalized(), _angulo)
	_skel.set_bone_pose_rotation(_hueso, q)

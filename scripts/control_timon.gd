extends Node3D
## Timón: gira el hueso 'timon' del esqueleto según la entrada de virada (A/D), para que
## se vea la caña moviéndose cuando el jugador maneja el barco.
##
## Refleja la ENTRADA del jugador, no el giro real del casco: así el timón responde al
## instante aunque el barco esté parado o anclado (que es lo que se ve en la realidad).
##
## No-op si el barco no tiene hueso de timón (por ahora solo la lancha). Se coloca como
## hijo del barco (CharacterBody3D); busca el Skeleton3D en el subárbol del barco.
##
## Eje: el hueso apunta hacia arriba siguiendo el codaste, así que la pala barre girando
## sobre su propio eje (Y local), igual que el hueso 'vela'.

@export var nombre_hueso := "timon"
@export_range(0.0, 60.0) var angulo_max := 35.0    ## Grados máximos a cada banda.
@export var eje := Vector3(0, 1, 0)                ## Eje LOCAL del hueso alrededor del que gira.
@export var invertir := false                       ## Invierte el sentido del giro.
@export_range(0.5, 20.0) var suavizado := 6.0      ## Rapidez con que la caña sigue a la entrada.

var _skel: Skeleton3D
var _hueso := -1
var _rot_reposo := Quaternion.IDENTITY
var _angulo := 0.0


func _ready() -> void:
	var barco := _buscar_barco()
	_skel = _buscar_skeleton(barco if barco else self)
	if _skel:
		_hueso = _skel.find_bone(nombre_hueso)
		if _hueso >= 0:
			_rot_reposo = _skel.get_bone_rest(_hueso).basis.get_rotation_quaternion()
	if _hueso < 0:
		# Este barco no lleva timón riggeado: no hacemos nada.
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
	# Mismas teclas que el giro del casco en ship_controller.gd (A = babor, D = estribor).
	# El signo va al revés que allí: con la orientación del hueso, la pala tiene que caer
	# a la misma banda hacia la que vira el barco.
	var giro := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	if invertir:
		giro = -giro
	var objetivo := giro * deg_to_rad(angulo_max)

	# Seguimiento suave: la caña va y vuelve al centro sin saltos.
	_angulo = lerpf(_angulo, objetivo, clampf(suavizado * delta, 0.0, 1.0))

	var q := _rot_reposo * Quaternion(eje.normalized(), _angulo)
	_skel.set_bone_pose_rotation(_hueso, q)

extends Node3D
## Izado de la vela: TRASLADA el hueso 'driza' a lo largo de su propio eje para subir y
## bajar la verga. Al arriar, la verga baja y el paño se comprime contra la botavara (los
## pesos del paño están repartidos entre 'vela' y 'driza' con un degradado en altura).
##
## El hueso 'driza' cuelga de 'vela', así que el trimado de control_vela.gd sigue
## funcionando igual con la vela izada o arriada, sin coordinar nada entre los dos scripts.
##
## No-op si el barco no tiene driza (por ahora solo la lancha). Se coloca como hijo del
## barco (CharacterBody3D); busca el Skeleton3D en el subárbol del barco.
##
## 'recorrido' va en unidades DEL MODELO, no del mundo: la pose del hueso es local al
## esqueleto, así que la escala del nodo Modelo ya se aplica sola.

@export var nombre_hueso := "driza"
@export var recorrido := 0.77                       ## Cuánto baja la verga al arriar del todo.
@export_range(0.5, 20.0) var suavizado := 2.5      ## Rapidez con que sube/baja la vela.
@export_enum("Delantera", "Trasera", "Ambas") var vela := 1  ## Qué vela del barco sigue.

var _skel: Skeleton3D
var _hueso := -1
var _reposo := Transform3D.IDENTITY
var _barco: Node3D
var _izado := 1.0      ## 1 = izada del todo, 0 = arriada.
var _objetivo := 1.0


func _ready() -> void:
	_barco = _buscar_barco()
	_skel = _buscar_skeleton(_barco if _barco else self)
	if _skel:
		_hueso = _skel.find_bone(nombre_hueso)
		if _hueso >= 0:
			_reposo = _skel.get_bone_rest(_hueso)
	if _hueso < 0:
		# Este barco no lleva vela izable: no hacemos nada.
		set_process(false)
		return

	# Las señales del barco avisan de cada cambio (ship_controller las emite para esto).
	if _barco:
		if _barco.has_signal("vela_delantera_cambiada"):
			_barco.vela_delantera_cambiada.connect(_on_vela_cambiada)
		if _barco.has_signal("vela_trasera_cambiada"):
			_barco.vela_trasera_cambiada.connect(_on_vela_cambiada)

	# Arranca acorde al estado del barco, sin animación de entrada.
	_objetivo = 1.0 if _vela_abierta() else 0.0
	_izado = _objetivo


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


func _on_vela_cambiada(_abierta: bool) -> void:
	_objetivo = 1.0 if _vela_abierta() else 0.0


func _vela_abierta() -> bool:
	match vela:
		0:
			return _estado("vela_delantera")
		1:
			return _estado("vela_trasera")
		_:
			return _estado("vela_delantera") or _estado("vela_trasera")


## Estado de una vela del barco. Si el barco no tiene esa propiedad, la damos por abierta
## (así el modelo se ve con la vela puesta en vez de arriada sin motivo).
func _estado(prop: String) -> bool:
	if _barco == null:
		return true
	var v: Variant = _barco.get(prop)
	return v if v is bool else true


func _process(delta: float) -> void:
	_izado = lerpf(_izado, _objetivo, clampf(suavizado * delta, 0.0, 1.0))
	# Desplazamiento a lo largo del eje del hueso (su Y local), relativo a la pose de reposo:
	# así no dependemos de cómo quedaron los ejes al pasar de Blender a glTF.
	var dir := _reposo.basis.y.normalized()
	_skel.set_bone_pose_position(_hueso, _reposo.origin + dir * (-recorrido * (1.0 - _izado)))

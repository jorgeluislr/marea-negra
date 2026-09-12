class_name Boya
extends Node3D

## Blanco flotante de tiro: una boya fondeada que acusa el impacto.
##
## Es el blanco más simple que sirve para lo que hace falta —calibrar alcance y puntería a una
## distancia CONOCIDA— y por eso lleva su distancia escrita: al sembrarlas se ponen a 60, 120,
## 200… y así el jugador aprende cuánta cuña necesita para cada una.
##
## Va en la capa 2, la del casco, que es contra la que choca `Bala`.

signal tocada(donde: Vector3, total: int)

## 1,0 m: una boya de tiro es un blanco grande, no un corcho. Y hace falta que lo sea: a 120 m,
## un paso de 0,1° de cuña ya mueve el impacto 4,3 m, y el cabeceo del casco añade otros 2-3.
@export var radio := 1.0
@export var altura_mar := 0.0
@export var color := Color(0.85, 0.25, 0.15)
@export var color_tocada := Color(0.25, 0.75, 0.35)
## Cuánto cabecea, para que se vea que flota y no está clavada.
@export var balanceo := 0.18
@export var periodo := 2.6

var impactos := 0
var energia_recibida := 0.0

var _malla: MeshInstance3D
var _mat: StandardMaterial3D
var _t := 0.0
var _base_y := 0.0


func _ready() -> void:
	_base_y = altura_mar
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = color
	_mat.roughness = 0.7
	# Cuerpo: una esfera achatada con un mástil corto, que se ve de lejos sobre el agua.
	_malla = MeshInstance3D.new()
	var e := SphereMesh.new()
	e.radius = radio
	e.height = radio * 1.6
	_malla.mesh = e
	_malla.material_override = _mat
	add_child(_malla)
	var palo := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = radio * 0.09
	cil.bottom_radius = radio * 0.09
	cil.height = radio * 3.0
	palo.mesh = cil
	palo.position.y = radio * 1.6
	palo.material_override = _mat
	add_child(palo)
	# Cuerpo de choque: la bala lo busca en la capa 2.
	var cuerpo := StaticBody3D.new()
	cuerpo.collision_layer = 2
	cuerpo.collision_mask = 0
	var forma := CollisionShape3D.new()
	var sf := SphereShape3D.new()
	sf.radius = radio * 1.25
	forma.shape = sf
	cuerpo.add_child(forma)
	add_child(cuerpo)


func _process(delta: float) -> void:
	_t += delta
	position.y = _base_y + sin(_t * TAU / periodo) * balanceo
	rotation.z = sin(_t * TAU / periodo * 0.7) * 0.12


## La llama la BALA al alcanzarla, por el método que responde y no por el tipo (misma convención
## que `on_interact`). Un blanco con integridad de casco usará la energía para restar daño; una
## boya de tiro solo necesita saber que la tocaron.
func recibir_impacto(donde: Vector3, energia: float, _quien: Node) -> void:
	impactos += 1
	energia_recibida += energia
	_mat.albedo_color = color_tocada
	tocada.emit(donde, impactos)

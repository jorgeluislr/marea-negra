class_name Estela
extends RefCounted
## El rastro de un barco por el agua: dónde ha pasado su popa, cuándo y a qué velocidad, y la
## silueta de su casco en la flotación. Es DATO; quien lo dibuja es `agua_estela.gdshaderinc`.
##
## Sustituye a las "gotas" que había: cada 0,12 s se soltaba un anillo en la posición del barco
## que se abría a 1,6 m/s, heredado de otro proyecto. Un anillo es lo que deja una piedra, no un
## casco: no sabe hacia dónde va el barco ni lo ancho que es. Lo que deja un barco de verdad son
## tres cosas, y las tres salen de este rastro:
##
## - una BANDA de agua revuelta tras la popa, tan ancha como el casco y que se abre despacio;
## - las olas de KELVIN, dos brazos que nacen en la proa a 19,47° del rumbo —ese ángulo es el
##   mismo para cualquier barco a cualquier velocidad en aguas profundas, y es lo que hace que una
##   estela se lea como estela—, con una longitud de onda que sí crece con la velocidad;
## - espuma pegada al COSTADO, más en la proa, que es donde el casco aparta el agua.
##
## Va aparte de `mar.gd` para que la batería pueda montar un rastro sintético —un barco en línea
## recta a velocidad conocida— y medir la estela sin tener que navegar.

## Muestras del rastro. Con `INTERVALO` dan ~10 s de estela.
const N := 48
const INTERVALO := 0.2
## Rebanadas del perfil del casco que viajan al shader.
const PERFIL_N := 32

## (x, z) en el mundo de la popa, edad en s y velocidad en m/s. La muestra 0 es la de AHORA y se
## mueve con el barco; las demás quedan donde la popa estuvo. Edad negativa = vacía.
var traza: Array[Vector4] = []
var _t := 0.0
var _vel := 0.0
## Pose del barco en planta: centro (x, z) y proa (unitaria).
var _centro := Vector2.ZERO
var _proa := Vector2(0, -1)
var _perfil := PackedFloat32Array()
var _perfil_z := Vector2.ZERO


func _init() -> void:
	vaciar()
	_perfil.resize(PERFIL_N)
	_perfil.fill(0.0)


func vaciar() -> void:
	traza.clear()
	for i in N:
		traza.append(Vector4(0, 0, -1.0, 0))
	_t = 0.0
	_vel = 0.0


## El mundo se ha corrido `-d` (origen flotante): todo el rastro va en coordenadas de mundo.
func desplazar(d: Vector2) -> void:
	_centro -= d
	for i in N:
		if traza[i].z >= 0.0:
			traza[i].x -= d.x
			traza[i].y -= d.y


## La silueta del casco en la flotación: medio ancho por rebanada y entre qué z del barco va
## (`lo` es la proa, que en los ejes del barco está hacia −Z).
func fijar_casco(anchos: PackedFloat32Array, lo: float, hi: float) -> void:
	_perfil.resize(PERFIL_N)
	for k in PERFIL_N:
		if anchos.is_empty():
			_perfil[k] = 0.0
			continue
		var u := float(k) / float(PERFIL_N - 1) * float(anchos.size() - 1)
		var a := int(floor(u))
		var b := mini(a + 1, anchos.size() - 1)
		_perfil[k] = lerpf(anchos[a], anchos[b], u - float(a))
	_perfil_z = Vector2(lo, hi)


func popa() -> Vector2:
	return _centro - _proa * _perfil_z.y


## Un paso del barco: dónde está su centro en planta y hacia dónde mira su proa.
func registrar(centro: Vector2, proa: Vector2, delta: float) -> void:
	var antes := popa()
	var habia := traza[0].z >= 0.0
	_centro = centro
	_proa = proa.normalized() if proa.length() > 0.0001 else _proa
	var ahora := popa()
	# La velocidad es la del MOVIMIENTO de la popa, no la que dice el barco: con abatimiento la
	# popa barre de lado, y eso también levanta agua.
	if habia and delta > 0.0:
		var v := antes.distance_to(ahora) / delta
		_vel = lerpf(_vel, v, 1.0 - exp(-delta / 0.3))
	for i in N:
		if traza[i].z >= 0.0:
			traza[i].z += delta
	_t += delta
	if habia and _t >= INTERVALO:
		_t = 0.0
		for i in range(N - 1, 0, -1):
			traza[i] = traza[i - 1]
	traza[0] = Vector4(ahora.x, ahora.y, 0.0, _vel)


## Un barco que ha navegado `segundos` en línea recta a `vel` m/s y está ahora con el centro en
## `centro`. Para las pruebas y las herramientas: monta la estela de golpe, sin navegar.
func recta(centro: Vector2, proa: Vector2, vel: float, segundos: float) -> void:
	vaciar()
	var d := proa.normalized()
	var pasos := int(segundos / INTERVALO)
	for i in range(pasos, -1, -1):
		var t := float(i) * INTERVALO
		_t = INTERVALO
		registrar(centro - d * vel * t, d, INTERVALO)
	_vel = vel
	for i in N:
		if traza[i].z >= 0.0:
			traza[i].w = vel


func aplicar(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("estela_traza", PackedVector4Array(traza))
	mat.set_shader_parameter("estela_pose", Vector4(_centro.x, _centro.y, _proa.x, _proa.y))
	mat.set_shader_parameter("estela_perfil", _perfil)
	mat.set_shader_parameter("estela_perfil_z", _perfil_z)
	mat.set_shader_parameter("estela_vel", _vel)

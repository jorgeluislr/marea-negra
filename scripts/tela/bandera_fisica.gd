class_name BanderaFisica
extends TelaFisica

## Bandera de tela física: cuelga y vuela como cualquier paño (eso lo hace `TelaFisica`), y
## además se ORIENTA a sotavento girando su hueso sobre el eje del mástil.
##
## **NADIE LA USA desde el 9 de septiembre de 2026, y antes de reutilizarla hay que saber por
## qué.** La bandera de la balandra pasó a `TelaShader`. El motivo no es esta clase, es la
## GEOMETRÍA del aparejo: su gratil va cosido a 54,8 mm del eje del mástil, que ahí tiene 46 mm
## de radio — **nueve milímetros de holgura para un paño de 960 mm**. Al virar, el hueso lleva el
## gratil alrededor del palo, la lona libre va con retraso y termina al otro lado; una vez
## envuelta no sale hasta que el barco para. Medido en un viraje a sotavento: de 0 puntos a menos
## de 100 mm del eje se pasaba a 19, con el más hondo a 4 mm —dentro de la madera—, y 5 s
## después seguían 10-11 pegados.
##
## Descartado midiendo, y no hay que repetirlo: la velocidad de giro del hueso (`suavizado` 1,2 /
## 6 / 12 dan lo mismo), la cápsula del mástil con y sin ella (10 frente a 11 puntos pegados), el
## flameo, el empuje del viento (10 a 70), todo el solver (rigidez 0,3-0,95, precisión 10-30,
## masa, arrastre: 104-108 mm planos) y la frecuencia de física (60/120/240/480, que arregla la
## costura pero no el envuelto). Y una restricción dura que sacaba cada paso los puntos metidos
## en el palo —se ejecutaba, sacaba 7-9 por paso— la deshacía el solver, porque el enrollado es
## **topológico**: hay tela al otro lado del palo tirando de ellos.
##
## El eje y el pivote de esta clase están BIEN, por si alguien viene buscando el fallo que sí
## tenía el shader: aquí no hay pivote estimado —gira el hueso, cuyo origen está sobre el eje del
## mástil a 3 mm— y el eje sale de la Y de ese hueso, que es el del palo exactamente.
##
## Así que vale para una bandera con HOLGURA —de un asta o una driza a 15-25 cm del palo, como
## van las de verdad—, donde el paño tiene sitio para bascular sin cruzarlo y una cápsula con
## pared de verdad puede impedirlo. Cosida al palo, no.
##
## Una bandera es una veleta: no se "trima" a una fracción como la vela ni se arría, apunta a
## donde sopla. Así que aquí no hay ángulo máximo — el hueso da la vuelta completa si hace falta.
##
## Antes esto estaba partido en dos nodos hermanos: uno giraba el hueso y otro simulaba el paño,
## y funcionaban solo porque el primero iba delante del segundo en la escena. Ahora es un objeto:
## orienta y luego lleva sus anclas, en ese orden, por construcción.
##
## Dos cosas se MIDEN en vez de suponerse, porque deducirlas de la orientación del hueso es
## justo donde se cometen los errores de signo:
##
##  - La dirección de reposo de la bandera sale de su propia malla: del centroide de los
##    vértices anclados (junto al mástil) al centroide del extremo libre.
##  - El SIGNO del giro se calibra al arrancar aplicando una rotación de prueba y viendo hacia
##    qué lado se mueve de verdad la piel. Con el eje del mástil inclinado y la malla girada por
##    el nodo `Modelo`, adivinarlo sale mal la mitad de las veces.
##
## El barrido es diminuto (los anclajes están a ~10 cm del eje del mástil), así que esto no
## sufre el problema de arrastre que tenía la mayor al trimar.

## Hueso que gira. El paño lo sigue por su piel: los anclajes de los aros de amarre están
## pesados a este hueso, y la tela cuelga de ellos.
@export var nombre_hueso := "giro_bandera"
## Eje LOCAL del hueso alrededor del que gira. El hueso va a lo largo del mástil, así que es su Y.
@export var eje := Vector3(0, 1, 0)
@export_range(0.1, 10.0) var suavizado := 1.2
@export var invertir := false

var _hueso := -1
var _rot_reposo := Quaternion.IDENTITY
var _eje_g := Vector3.UP        ## eje del hueso, en espacio del esqueleto
var _u := Vector3.RIGHT         ## dirección de reposo de la bandera, perpendicular al eje
var _v := Vector3.FORWARD       ## la perpendicular a las otras dos
var _p_ancla := Vector3.ZERO
var _p_lejos := Vector3.ZERO
var _signo := 1.0
var _ang := 0.0
var _listo := false


func _etiqueta() -> String:
	return "bandera_fisica"


func _montado(_barco: Node3D) -> void:
	_hueso = _skel.find_bone(nombre_hueso)
	if _hueso < 0:
		push_warning("%s: no hay hueso '%s'" % [name, nombre_hueso])
		return
	_rot_reposo = _skel.get_bone_rest(_hueso).basis.get_rotation_quaternion()

	# La malla de autor y su sitio respecto al esqueleto ya los tiene la base.
	var arr := _malla_original.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]

	# Amarre: centroide de los vértices anclados (azul en Col), que son los de los aros.
	var suma := Vector3.ZERO
	var n_az := 0
	for k in vs.size():
		if cols.size() > k and cols[k].b > 0.5:
			suma += _tr * vs[k]
			n_az += 1
	if n_az == 0:
		push_warning("%s: la bandera no lleva anclajes marcados en azul" % name)
		return
	_p_ancla = suma / float(n_az)

	# Extremo libre: el vértice más lejano del amarre (el vuelo de la bandera).
	var peor := -1.0
	for k in vs.size():
		var p := _tr * vs[k]
		var d := p.distance_to(_p_ancla)
		if d > peor:
			peor = d
			_p_lejos = p

	# Base perpendicular al eje del mástil.
	_eje_g = (_skel.get_bone_global_rest(_hueso).basis * eje).normalized()
	var d0 := _p_lejos - _p_ancla
	d0 = d0 - _eje_g * d0.dot(_eje_g)
	if d0.length() < 0.001:
		push_warning("%s: la bandera es paralela al mástil, no puedo orientarla" % name)
		return
	_u = d0.normalized()
	_v = _eje_g.cross(_u).normalized()

	_calibrar_signo()
	_listo = true
	print("%s: %d anclajes, vuelo %.2f m, signo %+d" % [_etiqueta(), n_az, peor, int(_signo)])


## Aplica un giro de prueba y mira hacia qué lado se mueve la piel de verdad.
func _calibrar_signo() -> void:
	const PRUEBA := 0.25
	_skel.set_bone_pose_rotation(_hueso, _rot_reposo * Quaternion(eje.normalized(), PRUEBA))
	var m := _skel.get_bone_global_pose(_hueso) * _skel.get_bone_global_rest(_hueso).affine_inverse()
	var d := (m * _p_lejos) - (m * _p_ancla)
	d = d - _eje_g * d.dot(_eje_g)
	_signo = 1.0
	if d.length() > 0.001:
		var a := atan2(d.dot(_v), d.dot(_u))
		if a < 0.0:
			_signo = -1.0
	_skel.set_bone_pose_rotation(_hueso, _rot_reposo)


## Se gira ANTES de que la base lea la pose del esqueleto, para que las anclas del paño se
## coloquen ya con la bandera rolada y no un frame por detrás.
func _antes_de_pose(delta: float) -> void:
	orientar(delta)


## Pone la bandera a sotavento. Es su función propia: la vela se trima, la bandera se orienta.
func orientar(delta: float) -> void:
	if not _listo:
		return
	# Viento APARENTE en espacio del esqueleto, proyectado al plano perpendicular al mástil.
	#
	# Aparente y no real: con el barco a 8-10 m/s y el viento de través hay hasta 50° entre uno
	# y otro. El PAÑO ya vuela al aparente sin que nadie se lo diga —el `SoftBody` vive en el
	# mundo, el barco lo arrastra y su propio arrastre lo alinea— así que con el hueso apuntando
	# al real la driza miraba a un sitio y la tela a otro, y se veía como una bandera que no
	# termina de rolar. Medido: vuelo contra aparente 1-8°, contra real 30-50°.
	var w_mundo := Viento.aparente(_velocidad_barco())
	if w_mundo.length() < 0.01:
		w_mundo = Viento.direccion
	var w: Vector3 = _skel.global_transform.basis.inverse() * w_mundo
	w = w - _eje_g * w.dot(_eje_g)
	if w.length() > 0.001:
		w = w.normalized()
		var objetivo := atan2(w.dot(_v), w.dot(_u))
		if invertir:
			objetivo += PI
		# lerp_angle va por el camino corto: la bandera no da la vuelta larga al rolar el viento.
		_ang = lerp_angle(_ang, objetivo, clampf(suavizado * delta, 0.0, 1.0))
	_skel.set_bone_pose_rotation(_hueso,
		_rot_reposo * Quaternion(eje.normalized(), _ang * _signo))


## Hacia dónde está APUNTANDO la bandera el hueso, en espacio de mundo y en horizontal.
##
## Es la dirección de la driza, no la del paño: el paño flamea alrededor de ella. Pública
## porque es lo único que `orientar()` decide, y por tanto lo único que se puede comprobar de
## ella —medir el paño no sirve, que vuela al aparente aunque el hueso apunte mal—.
func direccion_de_vuelo() -> Vector3:
	if not _listo:
		return Vector3.ZERO
	var d := _u * cos(_ang) + _v * sin(_ang)
	d = _skel.global_transform.basis * d
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO


## Marcha del barco del que cuelga la bandera, para el viento aparente. Cero si no cuelga de uno
## que se mueva (un asta en tierra, por ejemplo).
func _velocidad_barco() -> Vector3:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return (n as CharacterBody3D).velocity
		n = n.get_parent()
	return Vector3.ZERO

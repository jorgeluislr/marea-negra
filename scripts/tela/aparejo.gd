class_name Aparejo
extends Resource

## Cómo se iza y se trima UNA vela: qué huesos mueve, cuánto recorren y a qué velocidad.
##
## Es un recurso y no un nodo porque lo necesitan las dos ramas de tela y no hay herencia
## múltiple en GDScript: una vela de tela física (`VelaFisica`, que hereda el mecanismo
## `TelaFisica`) y una vela dibujada por el shader (`VelaShader`, que hereda `TelaShader`) se
## izan y se triman exactamente igual — moviendo huesos del esqueleto — y solo se diferencian
## en cómo se pinta el paño. Metido en cada hoja habría dos copias de la misma mecánica; como
## recurso, la mecánica y sus ajustes viven en un solo sitio y cada vela lleva el suyo.
##
## Cada vela tiene que tener su PROPIA instancia: guarda el estado del izado y del trimado.
##
## Esto era antes `control_vela.gd` y `control_izado.gd`, dos o tres nodos sueltos por barco que
## subían por `get_parent()` hasta el barco y se conectaban a sus señales. El recorrido de la
## driza estaba escrito DOS VECES —en el control y en la vela física— con un comentario
## avisando de que tenían que coincidir; ahora hay un solo sitio.

@export_group("Izado")
## Driza principal: se TRASLADA a lo largo de su propio eje para subir y bajar el paño. Al
## arriar, la percha baja y el paño se comprime contra la botavara (los pesos del paño están
## repartidos entre `vela` y `driza` con un degradado en altura).
##
## El hueso de la driza cuelga del de trimado, así que trimar sigue funcionando igual con la
## vela izada o arriada, sin coordinar nada.
##
## `recorrido` va en unidades DEL MODELO, no del mundo: la pose del hueso es local al
## esqueleto, así que la escala del nodo Modelo ya se aplica sola. Es además la referencia con
## la que se mide cuánto está arriada la vela para decidir la recogida del paño.
@export var driza_hueso := "driza"
@export var driza_recorrido := 0.77
## Driza del PICO, solo en las cangrejas: el pico no baja recto, se TUMBA girando sobre la
## garganta a la vez que baja, y así la percha baja rígida en vez de deformarse (nivelarla con
## pesos por vértice la acorta y le aplasta las secciones). Hueso vacío = esta vela no tiene.
@export var pico_hueso := ""
@export var pico_recorrido := 0.0
@export_range(-90.0, 90.0) var pico_giro := 0.0   ## Grados que tumba al arriar del todo.
@export var pico_eje := Vector3(0, 0, 1)
## Collar de la garganta del pico que CORRE por el mástil (un racamento): baja a la par que la
## garganta pero NO se tumba con el pico. Se traslada lo MISMO que el pico (`pico_recorrido`) a
## lo largo de su propio eje, sin girar. Si en vez de esto se cuelga de la driza, recorre de más
## (6,9 contra los 5,5 del pico) y se mete bajo cubierta; si se cuelga del pico, bascula con él.
## Vacío = esta vela no tiene collar. Su hueso debe nacer con el MISMO origen y eje que el del pico.
@export var collar_hueso := ""
@export_range(0.5, 20.0) var izado_suavizado := 2.5

@export_group("Trimado")
## Hueso de la percha que gira hacia SOTAVENTO (el lado hacia donde sopla el viento). Vacío =
## esta vela no se trima, que es el caso del foque: va en su estay.
##
## Eje: en Blender el balanceo lateral es sobre Z (vertical); al pasar a glTF/Godot eso es el
## eje Y. Si el giro sale mal orientado, prueba otro eje o marca `trimado_invertir`.
@export var trimado_hueso := ""
@export_range(0.0, 90.0) var trimado_angulo_max := 10.0
@export var trimado_eje := Vector3(0, 1, 0)
@export var trimado_invertir := false
## OJO al subirlo de la cuenta: el trimado es lo que más estira un paño físico, porque el
## `SoftBody` vive en espacio de MUNDO y no sigue a su padre. En la mayor de la balandra,
## trimar ±45° barre 4,7 m con el puño de escota y las aristas fijo/libre se abrían de 14 cm a
## 1,13 m. No lo arregla la rigidez, ni la precisión, ni la masa, ni el viento (los cuatro
## comprobados): lo arregla trimar despacio. Medido con el visor: 1,8 → 9,95 % de estiramiento
## medio; 0,4 → 1,87 %. En una vela de shader esto da igual y puede ir rápido.
@export_range(0.05, 20.0) var trimado_suavizado := 4.0
## Jarcia que TOPA la percha, por patrón de nombre de malla. Vacío = esta vela no topa en nada.
##
## Una cangreja y sus obenques salen del MISMO palo, así que basta comparar azimutes alrededor
## del eje del mástil: en cuanto el paño gira más que el obenque de popa de su banda, los dos se
## cruzan por fuerza y la jarcia aparece atravesando la lona. Medido con
## `tools/vela_en_obenques.tscn` con el tope en 80°: a 150° de viento pasaban los **613 puntos de
## 613**, y a 120° ya 199 — no era un roce, era la vela entera al otro lado.
##
## El tope se MIDE de la jarcia al montar la vela y no se escribe en la escena: en esta balandra
## sale 68,5°, pero es geometría de este casco y cada uno tiene la suya. Y es lo que pasa en un
## barco de verdad — la botavara abre hasta que topa con el obenque de popa, y ahí se queda.
@export var trimado_jarcia := "obenque*"
## Grados que se dejan por dentro del obenque. La lona tiene barriga y sale del plano de la
## percha, así que llegar justo al obenque deja paño pasado igual.
@export_range(0.0, 15.0) var trimado_margen_jarcia := 2.5
## Cuánta componente lateral hace falta para que la botavara se pase de banda. Con el viento
## justo por la popa el signo del lateral baila alrededor de cero y sin esto la percha
## trasluchaba varias veces por segundo.
const CRUZAR_CRUJIA := 0.12

var _skel: Skeleton3D
var _barco: Node3D
var _driza := -1
var _driza_reposo := Transform3D.IDENTITY
var _pico := -1
var _pico_reposo := Transform3D.IDENTITY
var _collar := -1
var _collar_reposo := Transform3D.IDENTITY
var _trim := -1
var _trim_reposo := Quaternion.IDENTITY
var _izado := 1.0                              ## 1 = izada del todo, 0 = arriada.
var _objetivo := 1.0
var _ang_trim := 0.0
## Tope que impone la jarcia, en radianes. INF mientras no se haya medido o si no hay jarcia.
var _tope_jarcia := INF
## A qué banda está cazada la percha: −1, +1, o 0 mientras no se haya decidido.
var _lado_trim := 0.0


## Busca los huesos y guarda sus poses de reposo. Sin esto el aparejo no hace nada, así que es
## seguro llamarlo tarde (al montarse la vela) o no llamarlo (barco sin esqueleto de vela).
func preparar(skel: Skeleton3D, barco: Node3D) -> void:
	_skel = skel
	_barco = barco
	if _skel == null:
		return
	_driza = _skel.find_bone(driza_hueso) if driza_hueso != "" else -1
	if _driza >= 0:
		_driza_reposo = _skel.get_bone_rest(_driza)
	_pico = _skel.find_bone(pico_hueso) if pico_hueso != "" else -1
	if _pico >= 0:
		_pico_reposo = _skel.get_bone_rest(_pico)
	_collar = _skel.find_bone(collar_hueso) if collar_hueso != "" else -1
	if _collar >= 0:
		_collar_reposo = _skel.get_bone_rest(_collar)
	_trim = _skel.find_bone(trimado_hueso) if trimado_hueso != "" else -1
	if _trim >= 0:
		_trim_reposo = _skel.get_bone_rest(_trim).basis.get_rotation_quaternion()
		_medir_tope_jarcia()


## Sube el paño. Con `inmediato` se planta arriba sin animación (al arrancar la escena).
func izar(inmediato := false) -> void:
	_objetivo = 1.0
	if inmediato:
		_izado = 1.0


## Baja el paño.
func arriar(inmediato := false) -> void:
	_objetivo = 0.0
	if inmediato:
		_izado = 0.0


func esta_izada() -> bool:
	return _objetivo > 0.5


## Un frame de aparejo: trimar al viento y seguir izando o arriando.
func paso(delta: float) -> void:
	if _skel == null:
		return
	trimar(delta)
	mover_drizas(delta)


## Trima la percha: la lleva al ángulo que le toca según de dónde entre el viento.
##
## **La regla es la de la mitad**, que es como se caza una vela de cuchillo de verdad: la botavara
## se pone a la mitad del ángulo que forman el viento aparente y la crujía, siempre a sotavento.
## Ceñida a 45° → unos 22° de botavara; al través → 45°; a un largo de 135° → 67; y en popa
## cerrada, TODO AFUERA, casi perpendicular al barco.
##
## Lo que había antes ponía el ángulo proporcional a la componente LATERAL del viento, y eso da
## el máximo al través y **cero en popa**: la vela se quedaba en crujía justo cuando más abierta
## tiene que ir. El usuario lo describió como que la vela se pone en la dirección del viento
## cuando lo tiene por detrás, y es exactamente eso. De proa también daba cero, que ahí sí es
## casi correcto, y por eso el fallo solo se notaba navegando de popa.
##
## Va con el viento APARENTE y no con el real: es el que siente la vela, y con el barco corriendo
## la diferencia llega a 50°.
func trimar(delta: float) -> void:
	if _trim < 0:
		return
	var base := _barco.global_transform.basis if _barco != null else _skel.global_transform.basis
	var vel := (_barco as CharacterBody3D).velocity if _barco is CharacterBody3D else Vector3.ZERO
	var viento_local := base.inverse() * Viento.aparente(vel)
	var v := Vector2(viento_local.x, viento_local.z)
	if v.length() > 0.001:
		v = v.normalized()
		# Ángulo del viento respecto a la proa: 0 = de proa, 180° = en popa. La proa es −Z, así
		# que el coseno es directamente la componente z del viento (que apunta a donde SOPLA).
		var beta := acos(clampf(v.y, -1.0, 1.0))
		var ang: float = minf(beta * 0.5, minf(deg_to_rad(trimado_angulo_max), _tope_jarcia))
		# A qué banda cae. Con el viento justo por la popa la componente lateral es casi cero y
		# su signo baila, así que la botavara se pasaría de banda sola varias veces por segundo:
		# el lado solo cambia cuando el viento cruza de verdad la crujía. Eso es una trasluchada,
		# y en el mar tampoco pasa por accidente.
		if absf(v.x) > CRUZAR_CRUJIA or _lado_trim == 0.0:
			_lado_trim = signf(v.x) if not is_zero_approx(v.x) else 1.0
		var objetivo := -_lado_trim * ang
		if trimado_invertir:
			objetivo = -objetivo
		# Seguimiento suave (no salta): la percha va girando hacia el objetivo.
		_ang_trim = lerpf(_ang_trim, objetivo, clampf(trimado_suavizado * delta, 0.0, 1.0))
	_skel.set_bone_pose_rotation(_trim,
		_trim_reposo * Quaternion(trimado_eje.normalized(), _ang_trim))


## Hasta dónde deja abrir la jarcia, medido de las propias mallas al montar la vela.
##
## El paño y los obenques cuelgan del mismo palo, así que el tope es el AZIMUT del obenque más
## cerrado alrededor del eje del hueso de trimado — que es el eje del mástil —. No hace falta
## distancia de segmento a segmento ni barrer ángulos: si el paño pasa de ese azimut, se cruzan.
##
## Se mide el extremo BAJO de cada obenque, el de la mesa de guarnión: arriba el cabo muere en el
## tope del palo, donde el radio es cero y el azimut no significa nada.
##
## Todo en ejes del BARCO, que es donde babor y popa quieren decir algo; la escora del casco se
## va sola al ser relativo.
func _medir_tope_jarcia() -> void:
	_tope_jarcia = INF
	if _barco == null or _skel == null or trimado_jarcia == "":
		return
	var al_barco := _barco.global_transform.affine_inverse() * _skel.global_transform
	var rest := _skel.get_bone_global_rest(_trim)
	var origen := al_barco * rest.origin
	var eje := (al_barco.basis * rest.basis.y).normalized()
	var popa := (Vector3(0, 0, 1) - eje * eje.z).normalized()
	var lat := (Vector3(1, 0, 0) - eje * eje.x).normalized()
	var menor := INF
	var cual := ""
	for nodo in _barco.find_children(trimado_jarcia, "MeshInstance3D", true, false):
		var mi := nodo as MeshInstance3D
		if mi.mesh == null:
			continue
		var tr := al_barco * _relativo(mi, _skel)
		var bajo := Vector3(0.0, INF, 0.0)
		for v in (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var p: Vector3 = tr * v
			if p.y < bajo.y:
				bajo = p
		var q := bajo - origen
		q -= eje * q.dot(eje)
		var a := absf(atan2(q.dot(lat), q.dot(popa)))
		if a < menor:
			menor = a
			cual = mi.name
	if menor == INF:
		return
	_tope_jarcia = maxf(menor - deg_to_rad(trimado_margen_jarcia), deg_to_rad(5.0))
	print("aparejo '%s': la jarcia topa la percha a %.1f° (%s), tope efectivo %.1f° de %.0f pedidos"
		% [trimado_hueso, rad_to_deg(menor), cual, rad_to_deg(_tope_jarcia), trimado_angulo_max])


## Transformación de un nodo respecto a un ancestro suyo.
func _relativo(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D()
	var x: Node = n
	while x != null and x != raiz:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


func mover_drizas(delta: float) -> void:
	if _driza < 0:
		return
	_izado = lerpf(_izado, _objetivo, clampf(izado_suavizado * delta, 0.0, 1.0))
	var arriado := 1.0 - _izado
	# Desplazamiento a lo largo del eje del hueso (su Y local), relativo a la pose de reposo:
	# así no dependemos de cómo quedaron los ejes al pasar de Blender a glTF.
	var dir := _driza_reposo.basis.y.normalized()
	_skel.set_bone_pose_position(_driza, _driza_reposo.origin + dir * (-driza_recorrido * arriado))
	if _pico < 0:
		return
	var dir_p := _pico_reposo.basis.y.normalized()
	_skel.set_bone_pose_position(_pico, _pico_reposo.origin + dir_p * (-pico_recorrido * arriado))
	if _collar >= 0:
		# El collar baja lo MISMO que la garganta (pico_recorrido), pero SOLO traslada: nunca se
		# le aplica el giro del pico. Así corre por el mástil a la par y no se mete bajo cubierta.
		var dir_c := _collar_reposo.basis.y.normalized()
		_skel.set_bone_pose_position(_collar,
			_collar_reposo.origin + dir_c * (-pico_recorrido * arriado))
	if not is_zero_approx(pico_giro):
		# Rotación en el eje LOCAL del hueso, así que no depende de la conversión de ejes de
		# glTF. El hueso gira sobre su propio origen, que en el pico está en la garganta.
		var giro := Basis(pico_eje.normalized(), deg_to_rad(pico_giro) * arriado)
		_skel.set_bone_pose_rotation(_pico, (_pico_reposo.basis * giro).get_rotation_quaternion())


## Cuánto está arriada la vela, de 0 a 1, MEDIDO sobre el hueso y no sobre la variable interna:
## lo que recoge o estira el paño es dónde está la percha de verdad, no dónde queríamos que
## estuviese.
func arriado_medido() -> float:
	if _skel == null or _driza < 0:
		return 0.0
	var d := _skel.get_bone_global_pose(_driza).origin - _skel.get_bone_global_rest(_driza).origin
	return clampf(d.length() / maxf(driza_recorrido, 0.001), 0.0, 1.0)

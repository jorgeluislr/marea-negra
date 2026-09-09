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
@export_range(0.5, 20.0) var izado_suavizado := 2.5

@export_group("Trimado")
## Hueso de la percha que gira hacia SOTAVENTO (el lado hacia donde sopla el viento). Vacío =
## esta vela no se trima, que es el caso del foque: va en su estay.
##
## Eje: en Blender el balanceo lateral es sobre Z (vertical); al pasar a glTF/Godot eso es el
## eje Y. Si el giro sale mal orientado, prueba otro eje o marca `trimado_invertir`.
@export var trimado_hueso := ""
@export_range(0.0, 45.0) var trimado_angulo_max := 10.0
@export var trimado_eje := Vector3(0, 1, 0)
@export var trimado_invertir := false
## OJO al subirlo de la cuenta: el trimado es lo que más estira un paño físico, porque el
## `SoftBody` vive en espacio de MUNDO y no sigue a su padre. En la mayor de la balandra,
## trimar ±45° barre 4,7 m con el puño de escota y las aristas fijo/libre se abrían de 14 cm a
## 1,13 m. No lo arregla la rigidez, ni la precisión, ni la masa, ni el viento (los cuatro
## comprobados): lo arregla trimar despacio. Medido con el visor: 1,8 → 9,95 % de estiramiento
## medio; 0,4 → 1,87 %. En una vela de shader esto da igual y puede ir rápido.
@export_range(0.05, 20.0) var trimado_suavizado := 4.0

var _skel: Skeleton3D
var _barco: Node3D
var _driza := -1
var _driza_reposo := Transform3D.IDENTITY
var _pico := -1
var _pico_reposo := Transform3D.IDENTITY
var _trim := -1
var _trim_reposo := Quaternion.IDENTITY
var _izado := 1.0                              ## 1 = izada del todo, 0 = arriada.
var _objetivo := 1.0
var _ang_trim := 0.0


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
	_trim = _skel.find_bone(trimado_hueso) if trimado_hueso != "" else -1
	if _trim >= 0:
		_trim_reposo = _skel.get_bone_rest(_trim).basis.get_rotation_quaternion()


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


## Gira la percha hacia sotavento, limitado a ±`trimado_angulo_max`.
func trimar(delta: float) -> void:
	if _trim < 0:
		return
	# Viento del mundo -> espacio local del BARCO. Su componente lateral (estribor = +X)
	# decide hacia qué lado va la vela (a SOTAVENTO, a favor del viento).
	var base := _barco.global_transform.basis if _barco != null else _skel.global_transform.basis
	var viento_local := base.inverse() * Viento.direccion
	var lateral := clampf(-viento_local.x, -1.0, 1.0)   # signo para que caiga a sotavento
	if trimado_invertir:
		lateral = -lateral
	var objetivo := lateral * deg_to_rad(trimado_angulo_max)
	# Seguimiento suave (no salta): la vela va girando hacia el objetivo.
	_ang_trim = lerpf(_ang_trim, objetivo, clampf(trimado_suavizado * delta, 0.0, 1.0))
	_skel.set_bone_pose_rotation(_trim,
		_trim_reposo * Quaternion(trimado_eje.normalized(), _ang_trim))


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

class_name TelaShader
extends Node3D
## Anima con el shader de tela+viento UNA malla concreta del modelo: la que se le indica en
## `nombre_malla`. Conserva las texturas del modelo importado (Meshy) y le pasa el viento del
## autoload Viento.
##
## Además calcula una NORMAL representativa de la vela (ajuste de plano por covarianza sobre
## los vértices con color de vértice) para el modelo de ÁNGULO DE ATAQUE del shader: la vela se
## llena cuando el viento le da de cara y flamea cuando le da de canto.
##
## Antes esto ESCANEABA todas las mallas con color de vértice que colgasen del nodo y se las
## quedaba. Reclamaba cosas que no eran suyas: `SoftBody3D` hereda de `MeshInstance3D`, así que
## el paño físico de una vela entraba en el escaneo y acababa con el shader encima de la física
## — y había que construirlo sin capa de color a propósito para esquivarlo. Con la malla dicha
## por su nombre, la propiedad es explícita y ese apaño sobra.
##
## Nota sobre la flota: en la lancha, la barca y la goleta el casco y la vela son UNA sola malla
## (`Mesh_0`, 444.835 vértices en la lancha), y qué parte ondea lo decide el canal ROJO de `Col`,
## no la separación en mallas. Por eso el paño no es un nodo aparte en esos barcos. La balandra
## sí trae cada paño como malla propia, pero los suyos son físicos (`TelaFisica`).
##
## Contrato de la capa `Col` que lee el shader:
##   R — cuánto se mueve el vértice (0 amarrado, 1 borde libre).
##   G — es BANDERA (> 0,5), y entonces se anima con la rama de bandera en vez de la de vela.
##   B — anclas del paño físico. No lo usa este shader; es de `TelaFisica`.

const SHADER := preload("res://assets/shaders/tela_viento.gdshader")
const UMBRAL_TELA := 0.05          # rojo > umbral => vértice de tela
const UMBRAL_BANDERA := 0.5        # verde > umbral => vértice de bandera (no vela)
const UMBRAL_IZADA := 0.2          # dentro de la bandera, rojo < umbral => borde amarrado (izada)
const MAX_MUESTRAS_NORMAL := 20000 # límite de vértices a muestrear para el ajuste de plano

## Malla que anima este nodo, por nombre. Se busca en el BARCO, igual que hace `TelaFisica`,
## así que este nodo es un hermano más y no tiene que ser el padre del modelo.
@export var nombre_malla := "Mesh_0"

## Ajuste del movimiento de la VELA (se puede tocar por instancia en el inspector).
@export_group("Ondeo vela")
# La lancha lleva la vela modelada PLANA (2026-08-16): el volumen con viento lo pone
# entero el shader, no la malla. Su canal rojo se repintó como membrana amarrada (0 en
# verga, botavara y caídas; 1 en el centro), así que el desplazamiento máximo lo marca
# ahora 'amplitud' tal cual: 0.12 da una comba equivalente a los 13 cm que estaban
# modelados. 'flameo' y 'flameo_base' quedan reescalados para que el aleteo se vea igual
# que con el pintado anterior, que llegaba solo a 0.29.
@export_range(0.0, 0.6) var amplitud := 0.12     ## Escala global del desplazamiento.
@export_range(0.0, 2.0) var hinchado := 0.9      ## Cuánto se comba al llenarse (viento de cara).
@export_range(0.0, 20.0) var frecuencia := 4.0   ## Nº de pliegues del flameo.
@export_range(0.0, 12.0) var velocidad := 2.5    ## Rapidez del flameo.
@export_range(0.0, 2.0) var flameo := 0.09       ## Amplitud del flameo estando de canto.
@export_range(0.0, 1.0) var flameo_base := 0.012 ## Aleteo residual aun estando llena.
@export_range(0.0, 1.0) var flameo_max := 0.55   ## Tope del "de canto": limita el pico de vibración.
@export_range(0.0, 1.0) var respuesta_rafaga := 0.4 ## Cuánto pican las ráfagas en el aleteo.

## Obstáculos contra los que choca la vela, en el espacio LOCAL de la malla. Con el viento
## de proa la vela se comba hacia el palo y sin esto lo atraviesa. Los valores por defecto
## son los de la lancha, medidos sobre el modelo; 'mastil_radio = 0' apaga la colisión.
## Los cabos son cápsulas: 'cabos_a[i]' -> 'cabos_b[i]', máximo 4.
@export_group("Mástil (colisión de la vela)")
@export var mastil_base := Vector3(-0.0115, 0.0, -0.0003)
@export var mastil_eje := Vector3(0, 1, 0)
@export_range(0.0, 0.5) var mastil_radio := 0.024
@export var cabos_a: PackedVector3Array = [Vector3(0.0221, -0.1989, 0.2548),
										   Vector3(0.0226, -0.1993, -0.2554)]
@export var cabos_b: PackedVector3Array = [Vector3(0.0103, 0.4371, 0.0999),
										   Vector3(0.0108, 0.4375, -0.1006)]
@export_range(0.0, 0.1) var cabos_radio := 0.012
## Las perchas van aparte de los cabos porque son mucho más gruesas (25-35 mm frente a 12).
## Sin ellas, la vela recogida atraviesa la botavara. Medidos sobre la malla de la lancha:
## botavara en y = -0,201 y verga en y = +0,665, ambas de banda a banda (±0,55).
@export var perchas_a: PackedVector3Array = [Vector3(0.002, -0.2008, 0.5541),
											 Vector3(-0.0435, 0.6643, -0.5123)]
@export var perchas_b: PackedVector3Array = [Vector3(0.0027, -0.201, -0.5556),
											 Vector3(-0.0421, 0.6652, 0.5111)]
@export_range(0.0, 0.1) var perchas_radio := 0.026

## Ajuste del movimiento de la BANDERA (canal verde).
@export_group("Ondeo bandera")
@export_range(0.0, 1.0) var bandera_desfase_mastil := 0.15 ## Desplaza el eje de giro hacia el mástil (fracción del largo).
## Hueso sobre cuyo eje rola la bandera. Si existe, su ORIGEN y su Y dan el pivote y el eje de
## giro EXACTOS, y `bandera_desfase_mastil` deja de usarse.
##
## Sin él hay que estimar las dos cosas, y las dos salían mal en la balandra:
##
##  - el EJE se tomaba como la vertical del MUNDO, y su mástil está inclinado **9,4°**, así que
##    la bandera rolaba describiendo un cono en vez de girar alrededor del palo;
##  - el PIVOTE se estimaba retranqueando el anclaje una fracción del largo, y con el 0,15
##    calibrado para la lancha eso son 10 cm en un paño cuyo gratil está a **5,5 cm** del eje:
##    el centro de giro caía al OTRO LADO del mástil, la bandera barría un círculo grande y se
##    metía en el palo.
##
## El origen del hueso sí está sobre el eje del mástil (medido: a 3,0 mm), así que no hay que
## estimar nada. La lancha no tiene hueso de bandera y se queda como estaba.
@export var bandera_hueso := "giro_bandera"
@export_range(0.0, 1.5) var bandera_latigo := 0.5     ## Amplitud de los pliegues.
@export_range(0.0, 30.0) var bandera_frecuencia := 12.0
@export_range(0.0, 20.0) var bandera_velocidad := 7.0

var _skel: Skeleton3D     # esqueleto del barco; lo usan las hojas que mueven huesos
var _telas: Array = []   # [{mat: ShaderMaterial, mi: MeshInstance3D}]
var _planitud := 0.0     # planitud de la última tela analizada (0 = 1 plano ; alto = varias velas)


func _ready() -> void:
	_montar.call_deferred()   # el modelo puede no estar montado del todo en este _ready


func _buscar_barco() -> Node3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n as Node3D
		n = n.get_parent()
	return get_parent() as Node3D


## Esqueleto del barco, para las hojas que mueven huesos (una vela se iza y se trima).
func _buscar_skeleton(raiz: Node) -> Skeleton3D:
	if raiz == null:
		return null
	for c in raiz.find_children("*", "Skeleton3D", true, false):
		return c as Skeleton3D
	return null


## Nombre con el que esta tela se presenta en los mensajes.
func _etiqueta_tela() -> String:
	return "tela_shader %s" % nombre_malla


## Gancho para que la hoja prepare lo suyo con la tela ya montada. No hace nada en la base.
func _montado(_barco: Node3D) -> void:
	pass


func _montar() -> void:
	var barco := _buscar_barco()
	if barco == null:
		return
	_skel = _buscar_skeleton(barco)
	var l := barco.find_children(nombre_malla, "MeshInstance3D", true, false)
	if l.is_empty():
		push_warning("%s: no encuentro la malla '%s'." % [name, nombre_malla])
		return
	var mi := l[0] as MeshInstance3D
	var m := mi.mesh
	if m == null or m.get_surface_count() == 0:
		push_warning("%s: la malla '%s' no tiene superficies." % [name, nombre_malla])
		return
	# Sin color de vértice no hay máscara de tela y el shader no sabría qué mover.
	if (m.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) == 0:
		push_warning("%s: la malla '%s' no lleva color de vértice." % [name, nombre_malla])
		return
	_aplicar(mi)
	_montado(barco)


func _aplicar(mi: MeshInstance3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	# Copiar las texturas del material importado para mantener el aspecto.
	var orig := mi.get_active_material(0)
	if orig is StandardMaterial3D:
		var sm := orig as StandardMaterial3D
		mat.set_shader_parameter("textura_albedo", sm.albedo_texture)
		if sm.normal_enabled and sm.normal_texture:
			mat.set_shader_parameter("textura_normal", sm.normal_texture)
			mat.set_shader_parameter("usar_normal", true)
		if sm.emission_enabled and sm.emission_texture:
			mat.set_shader_parameter("textura_emision", sm.emission_texture)
			mat.set_shader_parameter("usar_emision", true)
	# Normal representativa de la vela y anclaje de la bandera, ambos en el espacio
	# LOCAL de la malla (= espacio de VERTEX). Son estáticos: se fijan una vez.
	mat.set_shader_parameter("vela_normal", _normal_vela(mi))
	# Confianza en la normal según la planitud (1 = una vela plana ; 0 = varias velas). A
	# menor confianza, el shader atenúa el flameo dependiente del ángulo (evita vibración).
	mat.set_shader_parameter("vela_confianza", clampf(1.0 - (_planitud - 0.02) / 0.08, 0.0, 1.0))
	# Cilindro del mástil: con viento de proa la vela se comba hacia el palo y lo
	# atravesaría, así que el shader empuja el vértice fuera de este cilindro.
	mat.set_shader_parameter("mastil_base", mastil_base)
	mat.set_shader_parameter("mastil_eje", mastil_eje)
	mat.set_shader_parameter("mastil_radio", mastil_radio)
	# Los arrays del shader son de tamaño fijo (4): se rellenan y 'cabos_n' dice cuántos valen.
	var n_cabos := mini(mini(cabos_a.size(), cabos_b.size()), 4)
	var ca := PackedVector3Array(); ca.resize(4)
	var cb := PackedVector3Array(); cb.resize(4)
	for i in n_cabos:
		ca[i] = cabos_a[i]
		cb[i] = cabos_b[i]
	mat.set_shader_parameter("cabos_a", ca)
	mat.set_shader_parameter("cabos_b", cb)
	mat.set_shader_parameter("cabos_radio", cabos_radio)
	mat.set_shader_parameter("cabos_n", n_cabos)
	# Perchas: mismo esquema, array de tamaño fijo (2) más el contador.
	var n_perchas := mini(mini(perchas_a.size(), perchas_b.size()), 2)
	var pa := PackedVector3Array(); pa.resize(2)
	var pb := PackedVector3Array(); pb.resize(2)
	for i in n_perchas:
		pa[i] = perchas_a[i]
		pb[i] = perchas_b[i]
	mat.set_shader_parameter("perchas_a", pa)
	mat.set_shader_parameter("perchas_b", pb)
	mat.set_shader_parameter("perchas_radio", perchas_radio)
	mat.set_shader_parameter("perchas_n", n_perchas)
	var ancla := _ancla_bandera(mi)
	# Con hueso de bandera, el pivote es su ORIGEN —que está sobre el eje del mástil— y no el
	# anclaje retranqueado a ojo, y el desfase estimado deja de hacer falta.
	var eje_fijo := Vector3.ZERO
	var desfase := bandera_desfase_mastil
	var pivote := ancla
	var hb := _skel.find_bone(bandera_hueso) if _skel != null else -1
	if hb >= 0:
		var a_malla := mi.global_transform.affine_inverse() * _skel.global_transform
		var rest := _skel.get_bone_global_rest(hb)
		pivote = a_malla * rest.origin
		eje_fijo = (a_malla.basis * (rest.basis * Vector3(0, 1, 0))).normalized()
		desfase = 0.0
	# El VUELO se mide del anclaje del PAÑO al borde libre, no desde el pivote: `bandera_largo`
	# escala la amplitud del látigo, y el origen del hueso cae 46 cm por debajo del paño, lo que
	# lo habría inflado 1,7 veces. Para la ROTACIÓN da igual dónde del eje esté el pivote —una
	# rotación de Rodrigues alrededor de un eje es la misma en cualquier punto de él—, lo que
	# importa es que esté SOBRE él.
	var reposo := _vector_reposo_bandera(mi, ancla)   # izada -> vuelo (sin normalizar)
	var largo := maxf(reposo.length(), 0.001)
	mat.set_shader_parameter("bandera_ancla", pivote)
	mat.set_shader_parameter("bandera_dir_reposo", reposo / largo)
	mat.set_shader_parameter("bandera_largo", largo)
	mi.material_override = mat
	# 'r0' = dir. de reposo de la bandera (para calcular el ángulo de yaw cada frame).
	# 'eje_fijo' = eje del mástil en espacio local de la malla; Vector3.ZERO = usar la vertical.
	_telas.append({"mat": mat, "mi": mi, "r0": reposo / largo,
				   "eje_fijo": eje_fijo, "desfase": desfase})
	if hb >= 0:
		print("%s: bandera sobre el hueso '%s' — pivote %s, eje %s, largo %.3f m"
			% [_etiqueta_tela(), bandera_hueso, pivote, eje_fijo, largo])


## Marcha del barco del que cuelga la tela. Cero si no cuelga de algo que se mueva (un asta en
## tierra), y entonces el aparente es el viento real.
func _velocidad_barco() -> Vector3:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return (n as CharacterBody3D).velocity
		n = n.get_parent()
	return Vector3.ZERO


## Hacia dónde apunta la BANDERA, en espacio de mundo y en horizontal. Vacío si esta tela no
## lleva bandera (canal verde) o aún no está montada.
##
## Es la dirección de reposo girada por el mismo ángulo que se le pasa al shader, así que es
## exactamente lo que se ve. Pública porque es lo único de la bandera de shader que se puede
## comprobar desde código: el desplazamiento del paño ocurre en el VERTEX SHADER, y GDScript no
## puede leer dónde acabó cada vértice. Con tela física se medía el paño punto por punto; aquí
## se comprueba la orden, no el resultado.
func direccion_de_vuelo() -> Vector3:
	if _telas.is_empty():
		return Vector3.ZERO
	var t: Dictionary = _telas[0]
	if not t.has("giro"):
		return Vector3.ZERO
	var d: Vector3 = (t["r0"] as Vector3).rotated((t["eje"] as Vector3).normalized(), t["giro"])
	d = (t["mi"] as MeshInstance3D).global_transform.basis * d
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO


## Datos de la bandera que el shader dedujo de la capa `Col`, para verificarlos.
func datos_bandera() -> Dictionary:
	if _telas.is_empty():
		return {}
	var t: Dictionary = _telas[0]
	var mat: ShaderMaterial = t["mat"]
	return {
		"malla": (t["mi"] as MeshInstance3D),
		"ancla": mat.get_shader_parameter("bandera_ancla"),
		"largo": mat.get_shader_parameter("bandera_largo"),
		"giro": t.get("giro", 0.0),
	}


## Normal del plano de mejor ajuste de los vértices de tela (dirección de menor
## varianza de la nube de puntos). El signo es indiferente: el shader elige el lado
## de sotavento según el viento.
func _normal_vela(mi: MeshInstance3D) -> Vector3:
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var total := verts.size()
	if total == 0 or cols.size() != total:
		return Vector3(1, 0, 0)

	# Muestreo con paso para no recorrer cientos de miles de vértices en el arranque.
	var paso: int = maxi(1, total / MAX_MUESTRAS_NORMAL)

	var centro := Vector3.ZERO
	var n := 0
	var i := 0
	while i < total:
		# Solo VELA: rojo (tela) y NO verde (bandera).
		if cols[i].r > UMBRAL_TELA and cols[i].g <= UMBRAL_BANDERA:
			centro += verts[i]
			n += 1
		i += paso
	if n < 3:
		return Vector3(1, 0, 0)
	centro /= float(n)

	# Matriz de covarianza (simétrica 3x3).
	var xx := 0.0; var xy := 0.0; var xz := 0.0
	var yy := 0.0; var yz := 0.0; var zz := 0.0
	i = 0
	while i < total:
		if cols[i].r > UMBRAL_TELA and cols[i].g <= UMBRAL_BANDERA:
			var d := verts[i] - centro
			xx += d.x * d.x; xy += d.x * d.y; xz += d.x * d.z
			yy += d.y * d.y; yz += d.y * d.z; zz += d.z * d.z
		i += paso

	var cov := [
		[xx, xy, xz],
		[xy, yy, yz],
		[xz, yz, zz],
	]
	var normal := _menor_eigenvector(cov)
	# _menor_eigenvector diagonaliza 'cov' -> su diagonal son los autovalores. La planitud
	# (menor / suma) mide si la tela es un solo plano (≈0) o varias velas (alto).
	var suma: float = cov[0][0] + cov[1][1] + cov[2][2]
	var menor: float = minf(cov[0][0], minf(cov[1][1], cov[2][2]))
	_planitud = menor / maxf(suma, 1e-9)
	return normal.normalized()


## Punto de izada (amarre) de la bandera, en espacio LOCAL de la malla: centroide de
## los vértices de bandera (verde) con rojo bajo (el borde que NO se mueve). Si no hay
## bandera, devuelve el origen (el shader no usa la rama de bandera sin verde).
func _ancla_bandera(mi: MeshInstance3D) -> Vector3:
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var total := verts.size()
	if total == 0 or cols.size() != total:
		return Vector3.ZERO
	var paso: int = maxi(1, total / MAX_MUESTRAS_NORMAL)

	# Centroide del borde amarrado (rojo bajo) dentro de la bandera.
	var ancla := Vector3.ZERO
	var n := 0
	# Reserva: centroide de TODA la bandera, por si no hay un borde de rojo bajo claro.
	var todo := Vector3.ZERO
	var n_todo := 0
	var i := 0
	while i < total:
		if cols[i].g > UMBRAL_BANDERA:
			todo += verts[i]
			n_todo += 1
			if cols[i].r < UMBRAL_IZADA:
				ancla += verts[i]
				n += 1
		i += paso

	if n >= 3:
		return ancla / float(n)
	if n_todo >= 1:
		return todo / float(n_todo)
	return Vector3.ZERO


## Vector de reposo de la bandera (izada -> vuelo), en espacio LOCAL SIN normalizar: del
## anclaje al centroide del borde libre (bandera con rojo alto). Su dirección orienta la
## bandera y su longitud da el 'largo' de referencia para el ondeo.
func _vector_reposo_bandera(mi: MeshInstance3D, ancla: Vector3) -> Vector3:
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var total := verts.size()
	if total == 0 or cols.size() != total:
		return Vector3(1, 0, 0)
	var paso: int = maxi(1, total / MAX_MUESTRAS_NORMAL)

	var vuelo := Vector3.ZERO
	var n := 0
	var i := 0
	while i < total:
		# Borde libre de la bandera: verde alto y rojo alto.
		if cols[i].g > UMBRAL_BANDERA and cols[i].r > 0.7:
			vuelo += verts[i]
			n += 1
		i += paso
	if n < 1:
		return Vector3(1, 0, 0)
	var dir := (vuelo / float(n)) - ancla
	if dir.length() < 0.0001:
		return Vector3(1, 0, 0)
	return dir


## Ángulo de yaw (rad) que orienta la bandera a sotavento girando alrededor del mástil
## ('m'), desde su dir. de reposo 'r0' hacia el viento 'rw' (todo en espacio LOCAL).
## El giro en el shader es RÍGIDO, así que no hace falta desenrollar: +179° y -179° dan
## casi la misma orientación -> el cruce por detrás no salta.
func _giro_bandera(r0: Vector3, m: Vector3, rw: Vector3) -> float:
	var r0h := r0 - m * r0.dot(m)   # componentes horizontales (perp. al mástil)
	var rwh := rw - m * rw.dot(m)
	if r0h.length() < 0.001 or rwh.length() < 0.001:
		return 0.0
	r0h = r0h.normalized()
	rwh = rwh.normalized()
	var cs := clampf(r0h.dot(rwh), -1.0, 1.0)
	var sn := r0h.cross(rwh).dot(m)   # seno con signo alrededor de m
	return atan2(sn, cs)              # en [-PI, PI]


## Eigenvector del menor autovalor de una matriz simétrica 3x3 (algoritmo de Jacobi).
## Devuelve la normal del plano de mejor ajuste. Modifica 'a' localmente.
func _menor_eigenvector(a: Array) -> Vector3:
	var v := [
		[1.0, 0.0, 0.0],
		[0.0, 1.0, 0.0],
		[0.0, 0.0, 1.0],
	]
	for _iter in 32:
		# Mayor elemento fuera de la diagonal.
		var p := 0
		var q := 1
		var maxv: float = absf(a[0][1])
		if absf(a[0][2]) > maxv:
			maxv = absf(a[0][2]); p = 0; q = 2
		if absf(a[1][2]) > maxv:
			maxv = absf(a[1][2]); p = 1; q = 2
		if maxv < 1e-12:
			break

		var app: float = a[p][p]
		var aqq: float = a[q][q]
		var apq: float = a[p][q]
		var phi := 0.5 * atan2(2.0 * apq, aqq - app)
		var c := cos(phi)
		var s := sin(phi)

		# Rotar A por la izquierda y por la derecha (Jacobi).
		a[p][p] = c * c * app - 2.0 * s * c * apq + s * s * aqq
		a[q][q] = s * s * app + 2.0 * s * c * apq + c * c * aqq
		a[p][q] = 0.0
		a[q][p] = 0.0
		for k in 3:
			if k != p and k != q:
				var akp: float = a[k][p]
				var akq: float = a[k][q]
				a[k][p] = c * akp - s * akq
				a[p][k] = a[k][p]
				a[k][q] = s * akp + c * akq
				a[q][k] = a[k][q]

		# Acumular eigenvectores.
		for k in 3:
			var vkp: float = v[k][p]
			var vkq: float = v[k][q]
			v[k][p] = c * vkp - s * vkq
			v[k][q] = s * vkp + c * vkq

	# Columna del menor autovalor (diagonal más pequeña).
	var menor := 0
	if a[1][1] < a[menor][menor]:
		menor = 1
	if a[2][2] < a[menor][menor]:
		menor = 2
	return Vector3(v[0][menor], v[1][menor], v[2][menor])


func _process(_delta: float) -> void:
	if _telas.is_empty():
		return
	for t in _telas:
		var mi: MeshInstance3D = t["mi"]
		var mat: ShaderMaterial = t["mat"]
		# Viento del mundo -> espacio LOCAL de ESTA malla (coherente al girar el barco
		# y consistente con 'vela_normal', calculada en ese mismo espacio).
		var base_inv := mi.global_transform.basis.inverse()
		# Viento APARENTE para la bandera: el real menos la marcha del barco. Una veleta sobre
		# algo que se mueve se orienta al aparente, y con el barco a 8-10 m/s y el viento de
		# través hay hasta 50° entre uno y otro. Para el ONDEO de la vela se sigue usando el
		# real, que es el que la llena.
		var dir_local := base_inv * Viento.direccion
		var dir_bandera := base_inv * Viento.aparente(_velocidad_barco())
		if dir_bandera.length() > 0.0001:
			dir_bandera = dir_bandera.normalized()
		else:
			dir_bandera = dir_local
		if dir_local.length() > 0.0001:
			dir_local = dir_local.normalized()
		# Eje del mástil = vertical del MUNDO llevado al espacio local de la malla
		# (para el giro de la bandera alrededor del mástil, coherente al girar el barco).
		# El eje del mástil. Con hueso de bandera va medido de él; si no, la vertical del mundo
		# llevada a local, que es lo que hay para un barco sin ese hueso.
		var eje_local: Vector3 = t.get("eje_fijo", Vector3.ZERO)
		if eje_local.length() < 0.0001:
			eje_local = base_inv * Vector3.UP
		if eje_local.length() > 0.0001:
			eje_local = eje_local.normalized()
		mat.set_shader_parameter("viento_dir", dir_local)
		mat.set_shader_parameter("viento_fuerza", Viento.fuerza)
		mat.set_shader_parameter("bandera_eje", eje_local)
		# Ángulo de yaw de la bandera a sotavento (giro rígido en el shader; sin salto al
		# cruzar ±180°). Se calcula en el mismo espacio local (r0, eje, viento).
		var giro := _giro_bandera(t["r0"], eje_local, dir_bandera)
		t["giro"] = giro
		t["eje"] = eje_local
		mat.set_shader_parameter("bandera_giro", giro)
		# Parámetros de ondeo (aquí para poder afinarlos en vivo desde el inspector).
		mat.set_shader_parameter("amplitud", amplitud)
		mat.set_shader_parameter("hinchado", hinchado)
		mat.set_shader_parameter("frecuencia", frecuencia)
		mat.set_shader_parameter("velocidad", velocidad)
		mat.set_shader_parameter("flameo", flameo)
		mat.set_shader_parameter("flameo_base", flameo_base)
		mat.set_shader_parameter("flameo_max", flameo_max)
		mat.set_shader_parameter("respuesta_rafaga", respuesta_rafaga)
		mat.set_shader_parameter("bandera_desfase_mastil", t.get("desfase", bandera_desfase_mastil))
		mat.set_shader_parameter("bandera_latigo", bandera_latigo)
		mat.set_shader_parameter("bandera_frecuencia", bandera_frecuencia)
		mat.set_shader_parameter("bandera_velocidad", bandera_velocidad)

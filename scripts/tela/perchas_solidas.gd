extends Node3D
## Da cuerpo de colisión a las perchas y al estay, para que el paño de las velas se apoye en
## ellos en vez de atravesarlos.
##
## Sin esto, el paño libre pasa de largo: en la mayor el pujamen y el gratil cuelgan por debajo
## de la botavara y del pico entre aro y aro y sale una sierra de picos, y el paño puede envolver
## el mástil. Los puntos fijados no tienen ese problema (medido: 0,000 m de su anclaje), es el
## paño suelto el que no tiene nada que lo pare.
##
## Cada percha se describe con VARIAS cápsulas a lo largo de su eje, no con una sola: los palos
## son CÓNICOS. El mástil va de 130 mm de radio en el pie a 5-51 mm en la perilla, y una cápsula
## de radio constante tiene que usar el máximo, con lo que arriba sobran 90 mm de aire sólido.
## Ahí es donde va cosida la bandera —sus anclajes están a 54 mm del eje, justo fuera del palo
## real—, así que quedaban DENTRO del colisionador, en conflicto permanente.
##
## Un punto anclado dentro de la cápsula no tiene solución: el solver lo empuja fuera cada paso
## de física y el hueso lo devuelve, y ese tira y afloja se propaga por el paño como un golpe
## repetido que nace en el palo. Aparece y desaparece según trima la percha, que es lo que se
## veía como un "latido".
##
## La cadena de cápsulas se reparte sobre la extensión REAL de la malla a lo largo del eje
## (`t_min`..`t_max`), no simétricamente sobre su centroide. Solo coinciden si los vértices
## están repartidos, y en el mástil no lo están: 134 de sus 201 vértices son el racimo de la
## perilla. Con `max(|t|)` la cadena medía 14,03 m para un palo de 8,75, se pasaba 5,26 m por
## encima del tope con 107 mm de aire sólido, y a cambio metía el collar y la perilla en el
## mismo tramo —que es lo que atrapaba la bandera—.
##
## Medido con `tools/anclas_en_perchas.tscn`: la bandera pasó de 11 anclajes (todos) 53,8 mm
## dentro de la cápsula del mástil el 100 % de los frames, a CERO. Y ojo con esa herramienta:
## hasta el 8 de septiembre de 2026 solo leía `get_child(0)` de cada percha —el tramo del pie—,
## así que la bandera salía limpia y con esa medida se descartó, mal, que la causa fueran los
## colisionadores. La comprobación que no cubre todos los cuerpos no descarta nada.
##
## Sigue siendo cápsulas y no la malla: cuestan una fracción de un trimesh que además habría que
## reubicar cada frame, y por tramos ya siguen el perfil del palo.
##
## Las perchas se mueven —la botavara trima con `vela`, el pico baja con `driza_pico`— así que
## el colisionador sigue su hueso cada frame. El eje y el radio se miden de la propia malla al
## arrancar, así que esto vale para cualquier barco sin números a mano.
##
## Va en su propia capa de colisión: las velas la llevan en su `collision_mask` y nada más
## choca con ella, para que el personaje no se quede enganchado en la botavara.

@export var perchas: Array[String] = ["mastil_v3", "botavara", "pico", "estay_proa"]
## Se SUMA al radio medido de cada tramo. En negativo mete la cápsula dentro del palo, que es
## lo que hace falta para que las costuras de las velas —que están cosidas a la superficie— no
## queden atrapadas. Con el +0,01 que tenía, la mayor metía 13 anclajes en la botavara.
@export var margen := -0.002
## Cápsulas por percha, a lo largo de su eje. Con 1 se vuelve al comportamiento anterior (una
## sola, de radio máximo).
##
## Ocho, y no cuatro, por el mástil: entre el collar (109 mm de radio, a t = +0,50) y la
## perilla (48 mm, a t = +1,57) hay un metro escaso, y la bandera va cosida justo en medio, a
## 54,8 mm del eje. Con cuatro tramos el collar y la bandera caían en el MISMO tramo, la
## cápsula tomaba los 109 mm y dejaba los 11 anclajes 53 mm dentro. Con ocho, el corte cae en
## t = +0,66 y la bandera se lleva su propio tramo, de 46 mm.
@export_range(1, 16) var tramos := 8
@export_flags_3d_physics var capa := 16   ## Capa 5, solo para las velas.

var _barco: Node3D
var _skel: Skeleton3D
var _cuerpos: Array[StaticBody3D] = []
var _huesos: PackedInt32Array = PackedInt32Array()
var _reposos: Array[Transform3D] = []


func _ready() -> void:
	_montar.call_deferred()


func _buscar_barco() -> Node3D:
	var n := get_parent()
	while n != null:
		if n is CharacterBody3D:
			return n as Node3D
		n = n.get_parent()
	return get_parent() as Node3D


func _relativo(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != raiz:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


func _montar() -> void:
	_barco = _buscar_barco()
	if _barco == null:
		return
	var es := _barco.find_children("*", "Skeleton3D", true, false)
	if es.is_empty():
		return
	_skel = es[0] as Skeleton3D
	var hechas: Array[String] = []
	for nombre in perchas:
		var l := _barco.find_children(nombre, "MeshInstance3D", true, false)
		if l.is_empty():
			continue
		var mi := l[0] as MeshInstance3D
		if mi.mesh == null:
			continue
		var tr := _relativo(mi, _skel)
		var arr := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var hu: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var pe: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		# Centro, eje y radio de la percha, medidos de su malla en espacio del esqueleto.
		var c := Vector3.ZERO
		for v in vs:
			c += tr * v
		c /= float(vs.size())
		# Eje por PCA: el vértice más lejano al centro NO es el eje (con él el mástil salía de
		# radio 0,267 midiendo 0,13, y el estay 0,046 midiendo 0,016). Se itera la matriz de
		# covarianza, que converge en pocas vueltas al eje del cilindro.
		var cov := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
		for v in vs:
			var d := (tr * v) - c
			cov.x += d * d.x
			cov.y += d * d.y
			cov.z += d * d.z
		var eje := Vector3(0.577, 0.577, 0.577)
		for _it in 24:
			var nx := cov.x * eje.x + cov.y * eje.y + cov.z * eje.z
			if nx.length() < 1e-9:
				break
			eje = nx.normalized()
		# Extension a lo largo del eje: los DOS extremos por separado, no `max(|t|)` sobre el
		# centroide. El centroide solo cae en el medio si los vertices estan repartidos, y en el
		# mastil no lo estan --134 de sus 201 vertices son el racimo de la perilla--, asi que la
		# cadena simetrica se pasaba 5,26 m por encima del tope, con 107 mm de aire solido, y a
		# cambio metia el collar y la perilla en el mismo tramo.
		var radio := 0.0
		var t_min := INF
		var t_max := -INF
		for v in vs:
			var q := (tr * v) - c
			var t: float = q.dot(eje)
			t_min = minf(t_min, t)
			t_max = maxf(t_max, t)
			radio = maxf(radio, (q - eje * t).length())
		var largo := t_max - t_min
		# Hueso que la mueve: el de mayor peso de toda la malla.
		var suma := {}
		if hu.size() >= vs.size() * 4:
			for k in vs.size():
				for j in 4:
					var w: float = pe[k * 4 + j]
					if w > 0.0:
						var bi: int = hu[k * 4 + j]
						suma[bi] = float(suma.get(bi, 0.0)) + w
		var mejor := -1
		var mejor_w := 0.0
		for bi in suma:
			if float(suma[bi]) > mejor_w:
				mejor_w = float(suma[bi]); mejor = int(bi)

		# Radio máximo por TRAMO a lo largo del eje: es lo que permite seguir el cono del palo.
		var radios := []
		var cuentas := []
		for _k in tramos:
			radios.append(0.0)
			cuentas.append(0)
		for v in vs:
			var q := (tr * v) - c
			var t: float = q.dot(eje)
			var f: float = clampf((t - t_min) / maxf(largo, 1e-6), 0.0, 0.99999)
			var k := int(f * tramos)
			radios[k] = maxf(radios[k], (q - eje * t).length())
			cuentas[k] += 1
		# Los tramos sin vértices heredan del vecino con datos, o la cápsula saldría de radio 0.
		for k in tramos:
			if cuentas[k] == 0:
				var j := k
				while j >= 0 and cuentas[j] == 0:
					j -= 1
				if j < 0:
					j = k
					while j < tramos and cuentas[j] == 0:
						j += 1
				radios[k] = radios[j] if j >= 0 and j < tramos else radio

		var cuerpo := StaticBody3D.new()
		cuerpo.name = "Percha_" + nombre
		cuerpo.collision_layer = capa
		cuerpo.collision_mask = 0
		# La cápsula de Godot va a lo largo de SU eje Y: hay que orientarla al eje de la percha.
		var y := eje.normalized()
		var x := y.cross(Vector3.UP)
		if x.length() < 0.01:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		var base := Basis(x, y, x.cross(y))
		var largo_tramo := largo / float(tramos)
		var rs := []
		for k in tramos:
			var cap := CapsuleShape3D.new()
			cap.radius = maxf(radios[k] + margen, 0.004)
			cap.height = maxf(largo_tramo, cap.radius * 2.0 + 0.002)
			var cs := CollisionShape3D.new()
			cs.shape = cap
			cs.name = "T%d" % k
			var centro_t: float = t_min + largo_tramo * (float(k) + 0.5)
			cs.transform = Transform3D(base, eje * centro_t)
			cuerpo.add_child(cs)
			rs.append("%.3f" % cap.radius)
		_skel.add_child(cuerpo)
		cuerpo.transform = Transform3D(Basis(), c)
		_cuerpos.append(cuerpo)
		_huesos.append(mejor)
		_reposos.append(Transform3D(Basis(), c))
		hechas.append("%s(r=%s l=%.2f h=%s)" % [nombre, "/".join(rs), largo,
			_skel.get_bone_name(mejor) if mejor >= 0 else "-"])
	print("perchas_solidas: %s" % ", ".join(hechas))


func _process(_delta: float) -> void:
	# Las perchas se mueven con su hueso: la botavara trima, el pico baja y gira.
	for i in _cuerpos.size():
		var b: int = _huesos[i]
		if b < 0:
			continue
		var m := _skel.get_bone_global_pose(b) * _skel.get_bone_global_rest(b).affine_inverse()
		_cuerpos[i].transform = m * _reposos[i]

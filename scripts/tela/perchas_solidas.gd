extends Node3D
## Da cuerpo de colisión a los PALOS y a la JARCIA: para que el paño de las velas se apoye en
## ellos en vez de atravesarlos, y para que el personaje tampoco los atraviese.
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
## **TRES capas, y cada una responde a una pregunta distinta.** La 5 es la de los palos y solo la
## miran las velas que la pidan; la 6 es la de la jarcia, aparte de la anterior para que una vela
## pueda apoyarse en los obenques sin tragarse las cápsulas de las perchas (la mayor tiene
## `capa_perchas = 0` porque la cápsula de la botavara le hacía un ángulo a lo largo del pujamen);
## y la 3, la de cubierta, va en TODOS los cuerpos porque es la que enmascara el personaje. Sin
## esa tercera, el jugador cruzaba el mástil, la botavara y los obenques como si fueran humo.
##
## La JARCIA —seis obenques y veintiséis flechastes en esta balandra— se describe por PATRONES de
## nombre y con UNA cápsula por pieza: un cabo es recto y no tiene el cono de un palo, así que
## ocho tramos serían 256 formas para nada.
##
## Lo que la jarcia sólida NO arregla es que la lona se apoye en ella: probado dándole capa propia
## y máscara a la mayor, el paño pasado de los obenques se quedó en 476 puntos contra 475 sin
## colisión (`tools/vela_en_obenques.tscn`), porque esta malla tiene 25 cm de arista y el cabo
## 1,5 cm de radio: los puntos pasan ENTRE las cápsulas. Topar la percha (`Aparejo.trimado_jarcia`)
## para el PLANO de la vela, pero no su barriga.
##
## **Para la barriga, cada obenque lleva detrás un MURO para la lona** (`jarcia_lona`): una cápsula
## gruesa, de radio comparable a la arista del paño para que ningún par de vértices pueda quedar a
## caballo del cabo, DESPLAZADA hacia el lado contrario a la vela hasta que su cara de popa queda a
## ras de la del cabo. La lona se apoya justo en la cuerda y todo el grosor queda escondido detrás.
## La idea es del usuario.
##
## El lado sale de la geometría y no de un número: la vela y los obenques cuelgan del mismo palo,
## así que el paño llega al cabo girando alrededor del eje del mástil, y el muro va en la tangente
## de ese giro, hacia proa — en el obenque de popa de esta balandra, a 68,5°, eso es 93 % proa y
## 37 % hacia fuera. Una recta tangente deja la circunferencia entera a un lado, así que el muro
## queda todo él a proa del plano radial del cabo y no puede tragarse ningún ancla de la vela, que
## está toda a popa de ese plano. Va en su propia capa, que solo mira la lona: el personaje sigue
## chocando con el cabo fino de siempre y puede trepar.

@export var perchas: Array[String] = ["mastil_v3", "botavara", "pico", "estay_proa"]
## JARCIA: los cabos por los que se trepa y en los que topa la lona. Son patrones de nombre, no
## nombres exactos, porque son muchos y numerados (seis obenques y veintiséis flechastes).
##
## Van con UN tramo y no ocho: un cabo es recto y no tiene el cono de un palo, así que una
## cápsula lo describe entera. Con ocho, estas treinta y dos piezas costarían 256 formas.
@export var jarcia: Array[String] = ["obenque_*", "flechaste_*"]
## De la jarcia, cuáles son PELDANOS: se describen con una caja y no con una cápsula, porque lo
## que se pisa tiene que tener cara plana arriba. Sobre un cilindro de 1,7 cm de radio el
## personaje resbala, y con `is_on_floor()` en falso no puede ni saltar al siguiente.
@export var jarcia_peldanos: Array[String] = ["flechaste_*"]
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
## Capa 6, la de la JARCIA. Va aparte de la 5 para que una vela pueda apoyarse en los obenques
## sin tragarse las cápsulas de los palos: la mayor tiene `capa_perchas = 0` precisamente porque
## la cápsula de la botavara le hacía un ángulo a lo largo del pujamen.
@export_flags_3d_physics var capa_jarcia := 32
## Capa 3, la de cubierta, que es la que enmascara el personaje. Se SUMA a la capa de tela en
## todos los cuerpos: sin ella el jugador atraviesa el mástil, la botavara y los obenques como
## si no estuvieran, porque la capa 5 no la mira nadie más que la lona.
@export_flags_3d_physics var capa_personaje := 4
@export_group("Muro para la lona")
## Cabos que llevan detrás un muro en el que se apoya la lona. Patrones de nombre, como `jarcia`.
## Vacío = ningún muro.
@export var jarcia_lona: Array[String] = ["obenque_*"]
## El palo del que cuelgan la vela y esos cabos: su eje es el giro con el que la lona llega a ellos.
@export var palo_lona := "mastil_v3"
## Radio del muro. Tiene que pasar de media arista del paño (12,5 cm en la mayor): si no, un
## vértice a cada lado del cabo y la cara entre los dos lo deja dentro. Barrido con
## `tools/vela_en_obenques.tscn`, caras del paño que el obenque atraviesa de 120° a 170° de viento:
##   2 cm → 2-4 (es el cabo fino de siempre, y da lo mismo que sin muro)
##   8 cm → 2-4      12 cm → 0-8      15 cm → 0      20 cm → 0
## Va en 20 y no en 15 porque el umbral cae entre 12 y 15, y un valor pegado al umbral es como
## nace una prueba intermitente. En ningún radio quedó un ancla dentro ni subió el estiramiento.
## OJO con ese barrido: se hizo con el fallo de la caja del `SoftBody` sin arreglar (ver
## `TelaFisica._vigilar_caja`), y repetido el 17-10-2026 el primer rumbo que llega al obenque
## (120°, estribor) da con 20 cm EXACTAMENTE lo mismo que con 2. Los ceros eran de los rumbos en
## que la caja se había rehecho por casualidad.
@export_range(0.02, 0.6) var radio_lona := 0.20
## Capa 7, la de los muros. Solo la mira la vela que la ponga en su `capa_perchas`.
@export_flags_3d_physics var capa_lona := 64
@export_group("")

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
	var cabos := 0
	var radio_cabo := 0.0
	var muros := 0
	# El eje del palo de la lona se mide al pasar por él, que va en `perchas` y por tanto antes que
	# la jarcia. La proa, en ejes del esqueleto: la del barco es −Z.
	var palo_c := Vector3.ZERO
	var palo_eje := Vector3.ZERO
	var hacia_proa := _relativo(_skel, _barco).basis.inverse() * Vector3(0, 0, -1)
	var lista := []
	for nombre in perchas:
		for n in _barco.find_children(nombre, "MeshInstance3D", true, false):
			lista.append([n, tramos, capa | capa_personaje, false])
	for nombre in jarcia:
		var peldano := false
		for patron in jarcia_peldanos:
			if nombre.matchn(patron) or patron.matchn(nombre):
				peldano = true
		for n in _barco.find_children(nombre, "MeshInstance3D", true, false):
			lista.append([n, 1, capa_jarcia | capa_personaje, peldano])
	for entrada in lista:
		var mi := entrada[0] as MeshInstance3D
		var tramos_p: int = entrada[1]
		var capa_p: int = entrada[2]
		var peldano: bool = entrada[3]
		var nombre: String = mi.name
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
		if nombre.matchn(palo_lona):
			palo_c = c
			palo_eje = eje
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
		for _k in tramos_p:
			radios.append(0.0)
			cuentas.append(0)
		for v in vs:
			var q := (tr * v) - c
			var t: float = q.dot(eje)
			var f: float = clampf((t - t_min) / maxf(largo, 1e-6), 0.0, 0.99999)
			var k := int(f * tramos_p)
			radios[k] = maxf(radios[k], (q - eje * t).length())
			cuentas[k] += 1
		# Los tramos sin vértices heredan del vecino con datos, o la cápsula saldría de radio 0.
		for k in tramos_p:
			if cuentas[k] == 0:
				var j := k
				while j >= 0 and cuentas[j] == 0:
					j -= 1
				if j < 0:
					j = k
					while j < tramos_p and cuentas[j] == 0:
						j += 1
				radios[k] = radios[j] if j >= 0 and j < tramos_p else radio

		var cuerpo := StaticBody3D.new()
		cuerpo.name = "Percha_" + nombre
		cuerpo.collision_layer = capa_p
		cuerpo.collision_mask = 0
		# La cápsula de Godot va a lo largo de SU eje Y: hay que orientarla al eje de la percha.
		var y := eje.normalized()
		var x := y.cross(Vector3.UP)
		if x.length() < 0.01:
			x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		var base := Basis(x, y, x.cross(y))
		var largo_tramo := largo / float(tramos_p)
		var rs := []
		for k in tramos_p:
			var r: float = maxf(radios[k] + margen, 0.004)
			var alto_tramo: float = maxf(largo_tramo, r * 2.0 + 0.002)
			var cs := CollisionShape3D.new()
			if peldano:
				# Un peldano se PISA: caja, con su cara de arriba plana. La cápsula de Godot va a
				# lo largo de su Y y la caja también aquí, así que la orientación es la misma.
				var cja := BoxShape3D.new()
				cja.size = Vector3(r * 2.0, alto_tramo, r * 2.0)
				cs.shape = cja
			else:
				var cap := CapsuleShape3D.new()
				cap.radius = r
				cap.height = alto_tramo
				cs.shape = cap
			cs.name = "T%d" % k
			var centro_t: float = t_min + largo_tramo * (float(k) + 0.5)
			cs.transform = Transform3D(base, eje * centro_t)
			cuerpo.add_child(cs)
			rs.append("%.3f" % r)
		_skel.add_child(cuerpo)
		cuerpo.transform = Transform3D(Basis(), c)
		_cuerpos.append(cuerpo)
		_huesos.append(mejor)
		_reposos.append(Transform3D(Basis(), c))
		if tramos_p == 1:
			cabos += 1
			radio_cabo = maxf(radio_cabo, float(rs[0]))
			if palo_eje != Vector3.ZERO and _es_lona(nombre):
				_muro_lona(nombre, c, eje, radio, t_min, t_max, mejor, palo_c, palo_eje, hacia_proa)
				muros += 1
		else:
			hechas.append("%s(r=%s l=%.2f h=%s)" % [nombre, "/".join(rs), largo,
				_skel.get_bone_name(mejor) if mejor >= 0 else "-"])
	# La jarcia se cuenta y no se detalla: son 32 cabos y el detalle tapaba todo lo demás.
	print("perchas_solidas: %s%s%s" % [", ".join(hechas),
		", y %d cabos de jarcia (radio hasta %.3f)" % [cabos, radio_cabo] if cabos > 0 else "",
		", %d con muro para la lona (radio %.3f)" % [muros, radio_lona] if muros > 0 else ""])


func _es_lona(nombre: String) -> bool:
	for patron in jarcia_lona:
		if nombre.matchn(patron):
			return true
	return false


## El muro en que se apoya la lona detrás de un cabo: una cápsula de `radio_lona` a lo largo del
## cabo, corrida hacia proa en la tangente del giro alrededor del palo hasta que su cara de popa
## queda a ras de la del cabo. Todo en ejes del esqueleto, como el resto de cuerpos.
func _muro_lona(nombre: String, c: Vector3, eje: Vector3, radio: float, t_min: float,
		t_max: float, hueso: int, palo_c: Vector3, palo_eje: Vector3, hacia_proa: Vector3) -> void:
	# Del eje del palo al cabo. El obenque va en un plano que contiene ese eje, así que el centro
	# del cabo da la misma dirección que cualquier otro punto suyo.
	var radial := (c - palo_c) - palo_eje * (c - palo_c).dot(palo_eje)
	var n := palo_eje.cross(radial)
	n -= eje * n.dot(eje)
	if n.length() < 1e-6:
		return
	n = n.normalized()
	# La lona de una cangreja va a popa del palo, así que la tangente que se aleja de ella es la que
	# apunta a proa — en cualquier obenque, sea cual sea su azimut.
	if n.dot(hacia_proa) < 0.0:
		n = -n
	var centro := c + n * (radio_lona - radio)
	var y := eje.normalized()
	var x := y.cross(n).normalized()
	var cap := CapsuleShape3D.new()
	cap.radius = radio_lona
	cap.height = maxf(t_max - t_min, radio_lona * 2.0 + 0.002)
	var cs := CollisionShape3D.new()
	cs.name = "Muro"
	cs.shape = cap
	cs.transform = Transform3D(Basis(x, y, x.cross(y)), y * (t_min + t_max) * 0.5)
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Lona_" + nombre
	cuerpo.collision_layer = capa_lona
	cuerpo.collision_mask = 0
	cuerpo.add_child(cs)
	_skel.add_child(cuerpo)
	cuerpo.transform = Transform3D(Basis(), centro)
	_cuerpos.append(cuerpo)
	_huesos.append(hueso)
	_reposos.append(Transform3D(Basis(), centro))


func _process(_delta: float) -> void:
	# Las perchas se mueven con su hueso: la botavara trima, el pico baja y gira.
	for i in _cuerpos.size():
		var b: int = _huesos[i]
		if b < 0:
			continue
		var m := _skel.get_bone_global_pose(b) * _skel.get_bone_global_rest(b).affine_inverse()
		_cuerpos[i].transform = m * _reposos[i]

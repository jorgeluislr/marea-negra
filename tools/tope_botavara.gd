extends Node

## Hasta dónde puede abrir la botavara antes de meterse en los obenques, medido de la geometría.
##
## En un barco de verdad la botavara no abre lo que quiera: topa con el obenque de popa, y ahí se
## queda. Sin ese tope la percha sigue girando y el paño atraviesa la jarcia, que es lo que se ve.
##
## Se calcula sin mover el juego: el trimado es un giro del hueso `vela` sobre su eje Y, así que
## basta rotar los extremos de la botavara en reposo (Rodrigues) y medir la distancia del segmento
## a cada obenque. Barrer el ángulo con el viento tardaría minutos y daría lo mismo.
##
## Se mide también la ALTURA del penol en cada ángulo: girar sobre el eje del MÁSTIL, que cae
## 9,47° a popa, levanta la percha, y esa subida es la que se ve como que la vela "se iza" al
## abrirse.
##
##     godot --path . tools/tope_botavara.tscn

## Radios de cálculo, medidos por `perchas_solidas` al arrancar (botavara 0,072) y del cabo.
const R_BOTAVARA := 0.072
const R_OBENQUE := 0.020


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(6.0).timeout

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco"); get_tree().quit(1); return
	var skel: Skeleton3D = null
	for n in b.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	var hueso := skel.find_bone("vela")
	var rest := skel.get_bone_global_rest(hueso)
	# Todo en ejes del BARCO: es donde se entiende qué es babor y qué es popa.
	var al_barco := b.global_transform.affine_inverse() * skel.global_transform
	var pivote := al_barco * rest.origin
	var eje := (al_barco.basis * rest.basis.y).normalized()
	print("\n─── tope de la botavara ───")
	print("pivote del trimado (ejes del barco): (%.3f, %.3f, %.3f)" % [pivote.x, pivote.y, pivote.z])
	print("eje del giro: (%.4f, %.4f, %.4f), %.2f° fuera de la vertical"
		% [eje.x, eje.y, eje.z, rad_to_deg(acos(clampf(absf(eje.y), -1.0, 1.0)))])

	var bota := _extremos(b, al_barco, "botavara")
	# El extremo de trabajo es el que se aleja del pivote: el penol.
	var penol: Vector3 = bota[0] if (bota[0] - pivote).length() > (bota[1] - pivote).length() else bota[1]
	var garganta: Vector3 = bota[1] if penol == bota[0] else bota[0]
	print("botavara: de (%.2f, %.2f, %.2f) a (%.2f, %.2f, %.2f), %.2f m"
		% [garganta.x, garganta.y, garganta.z, penol.x, penol.y, penol.z,
			(penol - garganta).length()])

	var obenques := {}
	for nom in ["obenque_pr_b", "obenque_med_b", "obenque_pp_b",
			"obenque_pr_e", "obenque_med_e", "obenque_pp_e"]:
		var e := _extremos(b, al_barco, nom)
		if e.is_empty():
			continue
		obenques[nom] = e
		print("%-16s de (%6.2f,%6.2f,%6.2f) a (%6.2f,%6.2f,%6.2f)"
			% [nom, e[0].x, e[0].y, e[0].z, e[1].x, e[1].y, e[1].z])

	print("\n%8s %10s %10s %s" % ["ángulo", "penol Y", "ΔY", "obenque más cercano (m)"])
	var y0 := penol.y
	var tope := 0.0
	var limite := R_BOTAVARA + R_OBENQUE
	for paso in 19:
		var ang := float(paso) * 5.0
		# A babor: signo negativo en X. Las dos bandas son espejo, así que con una basta.
		var g := _rodrigues(garganta - pivote, eje, deg_to_rad(ang)) + pivote
		var p := _rodrigues(penol - pivote, eje, deg_to_rad(ang)) + pivote
		var cual := ""
		var dmin := INF
		for nom in obenques:
			var o: Array = obenques[nom]
			var d := _dist_seg(g, p, o[0], o[1])
			if d < dmin:
				dmin = d; cual = nom
		if dmin > limite:
			tope = ang
		print("%7.0f° %10.3f %10.3f   %-16s %.3f%s"
			% [ang, p.y, p.y - y0, cual, dmin, "  <-- TOCA" if dmin <= limite else ""])
	print("\nÚltimo ángulo libre: %.0f°   (la percha sube %.3f m respecto a la crujía)"
		% [tope, _rodrigues(penol - pivote, eje, deg_to_rad(tope)).y + pivote.y - y0])
	get_tree().quit(0)


## Los dos extremos de una pieza alargada, en ejes del barco: los puntos más separados a lo
## largo de su eje principal, sacado por PCA como en `perchas_solidas`.
func _extremos(b: Node3D, al_barco: Transform3D, malla: String) -> Array:
	var l := b.find_children(malla, "MeshInstance3D", true, false)
	if l.is_empty():
		return []
	var mi := l[0] as MeshInstance3D
	if mi.mesh == null:
		return []
	var skel := mi.get_parent()
	var tr := al_barco * _relativo(mi, skel)
	var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var c := Vector3.ZERO
	for v in vs:
		c += tr * v
	c /= float(vs.size())
	var cov := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for v in vs:
		var d := (tr * v) - c
		cov.x += d * d.x; cov.y += d * d.y; cov.z += d * d.z
	var eje := Vector3(0.577, 0.577, 0.577)
	for _it in 24:
		var nx := cov.x * eje.x + cov.y * eje.y + cov.z * eje.z
		if nx.length() < 1e-9:
			break
		eje = nx.normalized()
	var t0 := INF; var t1 := -INF
	for v in vs:
		var t: float = ((tr * v) - c).dot(eje)
		t0 = minf(t0, t); t1 = maxf(t1, t)
	return [c + eje * t0, c + eje * t1]


func _rodrigues(v: Vector3, n: Vector3, a: float) -> Vector3:
	return v * cos(a) + n.cross(v) * sin(a) + n * n.dot(v) * (1.0 - cos(a))


## Distancia mínima entre dos segmentos.
func _dist_seg(p1: Vector3, p2: Vector3, q1: Vector3, q2: Vector3) -> float:
	var u := p2 - p1
	var v := q2 - q1
	var w := p1 - q1
	var a := u.dot(u); var bb := u.dot(v); var c := v.dot(v)
	var d := u.dot(w); var e := v.dot(w)
	var den := a * c - bb * bb
	var s := 0.0; var t := 0.0
	if den > 1e-9:
		s = clampf((bb * e - c * d) / den, 0.0, 1.0)
	t = clampf((a * e - bb * d) / maxf(c, 1e-9), 0.0, 1.0) if c > 1e-9 else 0.0
	s = clampf((bb * t - d) / maxf(a, 1e-9), 0.0, 1.0) if a > 1e-9 else 0.0
	t = clampf((bb * s + e) / maxf(c, 1e-9), 0.0, 1.0) if c > 1e-9 else 0.0
	return (w + u * s - v * t).length()


func _relativo(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != raiz:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

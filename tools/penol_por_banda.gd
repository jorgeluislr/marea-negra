extends Node

## A qué ALTURA queda el penol de la botavara al trimar a cada banda, y si las dos bandas
## salen iguales.
##
## El síntoma que se ve en el juego es que "hacia babor la vela sube el ángulo de drizado": la
## percha no solo se abre, se LEVANTA, y solo a una banda. Trimar es girar el hueso `vela` sobre
## un eje LOCAL suyo; si ese eje no es el vertical del barco, el penol describe un cono y la
## altura que gana a un lado la pierde al otro. Lo que decide es el término de Rodrigues que va
## con `sin(θ)` —el único que cambia de signo con la banda—, así que la asimetría es exactamente
## la mitad de la diferencia entre las dos bandas.
##
## Se mide la POSICIÓN del penol en ejes del BARCO, no en el mundo: el casco cabecea y escora con
## la ola, y en ejes de mundo eso se suma a lo que hace la percha.
##
## El barco va anclado y con el viento fijo, así que el aparente es el real y el ángulo que se le
## pide a la percha es el que dice el rumbo.
##
##     godot --path . tools/penol_por_banda.tscn

## Ángulos del viento respecto a la proa que se barren (0 = de proa, 180 = en popa).
const BETAS := [30.0, 60.0, 90.0, 120.0, 150.0, 175.0]
## Cuánto se espera a que el trimado se asiente en cada rumbo. El suavizado de la mayor es 0,4,
## así que necesita bastante: su constante de tiempo es de 2,5 s.
const ASENTARSE := 14.0


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco"); get_tree().quit(1); return
	b.set("anclado", true)

	var mayor: Node = null
	for h in b.get_children():
		if h.has_method("datos_depuracion") and str(h.get("nombre_malla")) == "vela_mayor":
			mayor = h
	if mayor == null or mayor.get("aparejo") == null:
		print("no encuentro la mayor con su aparejo"); get_tree().quit(1); return
	var apa: Resource = mayor.get("aparejo")

	var skel: Skeleton3D = null
	for n in b.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	var hueso := skel.find_bone(String(apa.get("trimado_hueso"))) if skel != null else -1
	if hueso < 0:
		print("no encuentro el hueso de trimado"); get_tree().quit(1); return

	# El penol: el vértice de la botavara más lejano del origen de su hueso, en reposo.
	var penol_reposo := _punta(b, skel, "botavara", hueso)
	var pico_hueso := skel.find_bone(String(apa.get("pico_hueso")))
	var penol_pico := _punta(b, skel, "pico", pico_hueso) if pico_hueso >= 0 else Vector3.ZERO

	# El eje sobre el que gira el trimado, en ejes del barco: es la causa, si la hay.
	var eje_local: Vector3 = apa.get("trimado_eje")
	var eje_barco := (b.global_transform.basis.inverse() * skel.global_transform.basis
		* skel.get_bone_global_rest(hueso).basis * eje_local.normalized()).normalized()
	print("\n─── penol por banda ───   tope de percha %.0f°" % float(apa.get("trimado_angulo_max")))
	print("eje de trimado en ejes del barco: (%.4f, %.4f, %.4f)  ->  %.2f° fuera de la vertical, %s"
		% [eje_barco.x, eje_barco.y, eje_barco.z,
			rad_to_deg(acos(clampf(absf(eje_barco.y), -1.0, 1.0))),
			"tumbado a una BANDA (asimétrico)" if absf(eje_barco.x) > 0.01 else "en el plano de crujía"])
	print("%-8s %10s %10s %10s %10s %10s"
		% ["viento", "banda", "percha", "penol Y", "pico Y", "ΔY penol"])

	var y0 := _en_barco(b, skel, hueso, penol_reposo).y
	var resultados := {}
	for beta in BETAS:
		for lado in [1.0, -1.0]:      # +1 = viento desde estribor, la percha cae a babor
			var desde := Vector3(sin(deg_to_rad(beta)) * lado, 0.0, -cos(deg_to_rad(beta)))
			# `desde` va en ejes del barco; la proa es −Z. `direccion` apunta a donde SOPLA.
			Viento.direccion_base = (b.global_transform.basis * -desde).normalized()
			var t := 0.0
			while t < ASENTARSE:
				b.set("anclado", true)
				await get_tree().physics_frame
				t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
			var p := _en_barco(b, skel, hueso, penol_reposo)
			var pp := _en_barco(b, skel, pico_hueso, penol_pico) if pico_hueso >= 0 else Vector3.ZERO
			var ang := rad_to_deg(atan2(p.x, p.z))
			var banda := "babor" if p.x < 0.0 else "estribor"
			resultados[[beta, lado]] = [ang, p.y, pp.y]
			print("%-8s %10s %9.1f° %10.3f %10.3f %10.3f"
				% ["%.0f°" % beta, banda, ang, p.y, pp.y, p.y - y0])

	print("\n%-8s %12s %12s %12s %12s" % ["viento", "|ángulo| b", "|ángulo| e", "ΔY babor", "ΔY estrib"])
	var peor := 0.0
	for beta in BETAS:
		var e: Array = resultados[[beta, 1.0]]     # viento por estribor -> percha a babor
		var bb: Array = resultados[[beta, -1.0]]
		var d := absf((e[1] - y0) - (bb[1] - y0))
		peor = maxf(peor, d)
		print("%-8s %12.1f %12.1f %12.3f %12.3f"
			% ["%.0f°" % beta, absf(e[0]), absf(bb[0]), e[1] - y0, bb[1] - y0])
	print("\nPEOR diferencia de altura del penol entre las dos bandas: %.3f m" % peor)
	get_tree().quit(0)


## El punto del penol en reposo, en espacio del ESQUELETO: el vértice de esa malla más lejano
## del origen de su hueso.
func _punta(b: Node3D, skel: Skeleton3D, malla: String, hueso: int) -> Vector3:
	var l := b.find_children(malla, "MeshInstance3D", true, false)
	if l.is_empty():
		return Vector3.ZERO
	var mi := l[0] as MeshInstance3D
	var tr := _relativo(mi, skel)
	var o := skel.get_bone_global_rest(hueso).origin
	var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var mejor := Vector3.ZERO
	var d := -1.0
	for v in vs:
		var p := tr * v
		if (p - o).length() > d:
			d = (p - o).length()
			mejor = p
	return mejor


## Lleva un punto de reposo del esqueleto a donde está AHORA, en ejes del barco.
func _en_barco(b: Node3D, skel: Skeleton3D, hueso: int, p: Vector3) -> Vector3:
	var m := skel.get_bone_global_pose(hueso) * skel.get_bone_global_rest(hueso).affine_inverse()
	return b.global_transform.affine_inverse() * (skel.global_transform * (m * p))


func _relativo(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != raiz:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

extends Node

## Cuánto paño de la mayor queda al otro lado de los obenques, rumbo a rumbo.
##
## La vela y los obenques salen del mismo palo, así que en cuanto la percha gira más que el
## obenque de popa de su banda los dos se cruzan y la jarcia aparece atravesando la lona. Se
## cuenta el paño pasado por azimut alrededor del eje del mástil, que es lo que distingue "roza"
## de "la atraviesa entera".
##
##     godot --path . tools/vela_en_obenques.tscn
##     godot --path . tools/vela_en_obenques.tscn -- 0.08     # con el muro de 8 cm de radio
##
## Además de lo que pasa del obenque por azimut, cuenta las caras del paño que el cabo
## ATRAVIESA de verdad y las anclas de la vela que quedan dentro del muro de la lona — un ancla
## dentro de un colisionador es el "latido", y el muro no puede comprar una cosa con la otra.

const RUMBOS := [45.0, 90.0, 120.0, 150.0, 170.0]
const ASENTARSE := 14.0


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func(): get_tree().quit(1))
	# El barco lo crea el mundo cuando le toca, así que el radio se pone al entrar en el árbol;
	# las perchas se montan en diferido y les llega a tiempo.
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		get_tree().node_added.connect(func(n: Node):
			if n.name == "PerchasSolidas":
				n.set("radio_lona", float(args[0])))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()
	var b := UtilesPruebas.barco(get_tree())
	var mayor: Node = null
	for t in UtilesPruebas.telas(get_tree()):
		if str(t.get("nombre_malla")) == "vela_mayor":
			mayor = t
	if b == null or mayor == null:
		print("no hay barco o no hay mayor"); get_tree().quit(1); return
	print("\n─── paño pasado de los obenques ───   tope de percha %.0f°"
		% float((mayor.get("aparejo") as Resource).get("trimado_angulo_max")))
	var e0: Dictionary = await UtilesPruebas.estiramiento(get_tree(), mayor)
	print("radio del muro %s   estiramiento al empezar %.4f medio, %d aristas > 25 %%"
		% [_radio_muro(b), e0["medio"], e0["malas"]])
	print("%-9s %-9s %12s %12s %14s  %6s %6s %8s  %s" % ["viento", "banda", "azimut vela",
		"obenque", "paño pasado", "caras", "anclas", "estira", "qué cabo"])
	for beta in RUMBOS:
		for lado in [1.0, -1.0]:
			var desde := Vector3(sin(deg_to_rad(beta)) * lado, 0.0, -cos(deg_to_rad(beta)))
			var t := 0.0
			while t < ASENTARSE:
				Viento.direccion_base = (b.global_transform.basis * -desde).normalized()
				b.set("anclado", true)
				await get_tree().physics_frame
				t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
			var d: Dictionary = await UtilesPruebas.vela_en_jarcia(get_tree(), b, mayor)
			# Las caras se cuentan en varias muestras: la lona flamea y un cruce puede ir y venir.
			var peor := 0
			var cabos := {}
			var anclas := 0
			for _m in 10:
				var c: Dictionary = await UtilesPruebas.jarcia_por_la_lona(get_tree(), b, mayor)
				if int(c["cruces"]) > peor:
					peor = int(c["cruces"])
					cabos = c["por_cabo"]
				anclas = maxi(anclas, _anclas_en_muros(b, mayor))
				for _f in 6:
					await get_tree().physics_frame
			var e: Dictionary = await UtilesPruebas.estiramiento(get_tree(), mayor)
			print("%-9s %-9s %11.1f° %11.1f° %8d de %d  %6d %6d %8.4f  %s"
				% ["%.0f°" % beta, "estribor" if lado > 0.0 else "babor",
					d["az_vela"], d["az_obenque"], d["pasados"], d["total"], peor, anclas,
					e["medio"], cabos])
	get_tree().quit(0)


func _radio_muro(b: Node3D) -> String:
	for c in b.find_children("Lona_*", "StaticBody3D", true, false):
		return "%.3f m" % ((c.get_child(0) as CollisionShape3D).shape as CapsuleShape3D).radius
	return "(sin muro)"


## Puntos ANCLADOS de la vela dentro de algún muro de la lona.
func _anclas_en_muros(b: Node3D, tela: Node) -> int:
	var d: Dictionary = tela.datos_depuracion()
	var cuerpo: SoftBody3D = d["cuerpo"]
	var fijo: PackedByteArray = d["fijo"]
	var muros := []
	for c in b.find_children("Lona_*", "StaticBody3D", true, false):
		var cs := c.get_child(0) as CollisionShape3D
		var cap := cs.shape as CapsuleShape3D
		muros.append([(c as Node3D).global_transform * cs.transform, cap.radius,
			maxf(cap.height * 0.5 - cap.radius, 0.0)])
	var n := 0
	for i in fijo.size():
		if fijo[i] == 0:
			continue
		var p := cuerpo.get_point_transform(i)
		for m in muros:
			var q: Vector3 = (m[0] as Transform3D).affine_inverse() * p
			if q.distance_to(Vector3(0.0, clampf(q.y, -m[2], m[2]), 0.0)) < m[1]:
				n += 1
				break
	return n

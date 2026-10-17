extends Node

## A qué ángulo se caza la percha según de dónde entre el viento, y si eso es lo que le toca.
##
## La regla de una vela de cuchillo es la **de la mitad**: la botavara se pone a la mitad del
## ángulo entre el viento aparente y la crujía, siempre a sotavento. Ceñida a 45° → 22° de
## botavara; al través → 45; a un largo de 135° → 67; en popa cerrada, todo afuera.
##
## Se barre el viento alrededor del barco y se compara lo que hace con lo que le tocaría. Y se
## mira también el ESTIRAMIENTO del paño en cada rumbo: abrir más la botavara es un barrido
## mayor, y el paño es un `SoftBody3D` que lo tiene que seguir.
##
##     godot --path . tools/trimado_por_rumbo.tscn

## De cuánto en cuánto se barre, en grados.
const PASO := 30.0
## Cuánto se espera en cada rumbo a que el trimado se asiente, en segundos.
const ASENTARSE := 2.5


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(1))
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	Viento.variacion_fuerza = 0.0
	Viento.bamboleo_dir = 0.0
	Viento.fuerza_base = 1.0
	await get_tree().create_timer(7.0).timeout
	Oleaje.asentar()

	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco")
		get_tree().quit(1)
		return
	# Anclado: así el viento aparente es el real y el barrido es limpio.
	b.set("anclado", true)

	var mayor: Node = null
	for h in b.get_children():
		if h.has_method("datos_depuracion") and str(h.get("nombre_malla")) == "vela_mayor":
			mayor = h
	if mayor == null or mayor.get("aparejo") == null:
		print("no encuentro la mayor con su aparejo")
		get_tree().quit(1)
		return
	var apa: Resource = mayor.get("aparejo")
	print("\n─── trimado por rumbo ───   (tope de la percha: %.0f°)"
		% float(apa.get("trimado_angulo_max")))
	# La botavara de VERDAD, no el ángulo interno del hueso: lo que importa es a qué banda cae la
	# percha, y el signo de un hueso no lo dice —depende de su eje y de `trimado_invertir`—.
	# El HUESO, no la malla: la botavara es parte de una malla con piel y su `MeshInstance3D` no
	# tiene transformación propia, así que medirla daba 0,0° en todos los rumbos. Lo que gira es
	# el hueso, y el eje de un hueso en Godot es su Y.
	var skel: Skeleton3D = null
	for n in b.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	var hueso := skel.find_bone(String(apa.get("trimado_hueso"))) if skel != null else -1
	if hueso < 0:
		print("no encuentro el hueso de trimado")
		get_tree().quit(1)
		return
	print("%-14s %11s %11s %10s %12s"
		% ["viento desde", "botavara", "le tocaría", "sotavento", "estira"])

	var proa := -b.global_transform.basis.z
	var a := 0.0
	while a < 360.0:
		# `a` = de dónde VIENE el viento, medido desde la proa hacia estribor.
		var desde := proa.rotated(Vector3.UP, deg_to_rad(-a))
		Viento.direccion_base = -desde
		var t := 0.0
		while t < ASENTARSE:
			b.set("anclado", true)
			await get_tree().physics_frame
			t += 1.0 / maxf(Engine.physics_ticks_per_second, 1)
		# Eje largo de la botavara, en ejes del barco. Se saca de su CAJA y no de un eje de su
		# transform: cuál de los tres es el largo depende de cómo salió el modelo de Blender, y
		# tomando la Y a ciegas salía vertical y la tabla entera vacía.
		var pose := skel.global_transform * skel.get_bone_global_pose(hueso)
		# El giro de trimado es SOBRE el eje Y del hueso, así que su Y no se entera: hay que mirar
		# el eje que barre, que es el perpendicular. Se elige el que más se mueve entre X y Z.
		var bx := b.global_transform.basis.inverse() * pose.basis.x.normalized()
		var bz := b.global_transform.basis.inverse() * pose.basis.z.normalized()
		var eje := bx if absf(bx.y) < absf(bz.y) else bz
		var eh := Vector2(eje.x, eje.z)
		if eh.length() < 0.001:
			continue
		eh = eh.normalized()
		# Positivo = la percha cae a ESTRIBOR.
		# Positivo = la percha cae a ESTRIBOR. Se toma el extremo que mira a POPA (la botavara
		# va hacia atrás desde el mástil), para que el signo no dependa de cómo se orientó el eje.
		if eh.y < 0.0:
			eh = -eh
		var ang := rad_to_deg(asin(clampf(eh.x, -1.0, 1.0)))
		# A sotavento significa a la banda contraria de donde viene el viento: con el viento
		# desde estribor (0-180°) la percha tiene que caer a babor, o sea ángulo negativo.
		var bien: bool = (ang < 0.0) if (a > 5.0 and a < 175.0) 			else ((ang > 0.0) if (a > 185.0 and a < 355.0) else true)
		# Lo que le tocaría: la mitad del ángulo del viento, con el tope de la percha.
		var beta: float = a if a <= 180.0 else 360.0 - a
		var toca: float = minf(beta * 0.5, float(apa.get("trimado_angulo_max")))
		var e: Dictionary = await UtilesPruebas.estiramiento(get_tree(), mayor)
		print("%-14s %10.1f° %10.1f° %10s %12.4f"
			% ["%.0f°" % a, ang, -toca * (1.0 if a <= 180.0 else -1.0),
				"sí" if bien else "NO", e.get("medio", 0.0)])
		a += PASO
	get_tree().quit(0)

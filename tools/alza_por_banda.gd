extends Node

## Hacia dónde se va el tiro cuando el jugador sube la cuña, banda por banda.
##
## Hermana de `apunte_por_banda.tscn`, que hizo esto mismo con el espeque. La puntería fina es
## un par de números —grados de espeque y grados de cuña— que se aplican a la batería entera, y
## la pregunta es qué significan VISTOS POR QUIEN APUNTA: subir el ratón tiene que levantar el
## tiro, se tire con la batería que se tire.
##
## Se mide el ángulo del ánima sobre el horizonte y el ALCANCE, porque son las dos caras del
## mismo síntoma: si una banda baja el tubo cuando la otra lo sube, esa banda tira más corto con
## la misma orden, y eso es lo que se nota jugando.
##
##     godot --path . tools/alza_por_banda.tscn

const CUNA := 8.0


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	var b := (load("res://scenes/barcos/balandra.tscn") as PackedScene).instantiate() as Barco
	add_child(b)
	# El agua de este mundo está en −0,882 y la balandra suelta no la encuentra: con un cero la
	# lámina queda medio metro sobre la boca y los alcances salen todos cortos. Ver
	# `tools/alcance_real.gd`, que es donde se descubrió.
	b.altura_mar = -0.882
	b.set("anclado", true)
	# ADRIZADA, y las tres causas a la vez. Con el casco escorado las dos bandas salen inclinadas
	# en sentidos CONTRARIOS —una apunta al cielo y la otra al agua por la escora, no por la
	# cuña— y la tabla es ilegible: la primera tirada dio −5,85° y +5,78° con la cuña a cero.
	b.set("obediencia_escora", 0.0)
	b.set("obediencia_cabeceo", 0.0)
	b.set("brazo_velico", 0.0)
	b.set("brazo_giro", 0.0)
	await get_tree().create_timer(4.0).timeout
	# El casco llega al plano por un filtro de 0,45 s: hay que esperar a que LLEGUE, no un rato.
	while absf(b.global_transform.basis.get_euler().z) > 0.0008:
		await get_tree().physics_frame

	print("\n─── qué hace la cuña en cada banda ───")
	print("%-20s %10s %11s %11s %11s %11s"
		% ["pieza", "banda", "ánima 0°", "ánima +%.0f°" % CUNA, "alcance 0°", "alcance +%.0f°" % CUNA])
	for n in b.find_children("*", "Node3D", true, false):
		if not n.has_method("direccion_global"):
			continue
		var c := n as Node3D
		c.set("elevacion", 0.0)
		await get_tree().process_frame
		var a0 := _sobre_horizonte(c)
		var r0 := _alcance(c)
		c.set("elevacion", CUNA)
		await get_tree().process_frame
		var a1 := _sobre_horizonte(c)
		var r1 := _alcance(c)
		c.set("elevacion", 0.0)
		print("%-20s %10s %10.2f° %10.2f° %9.1f m %9.1f m"
			% [c.name, String(c.call("banda")), a0, a1, r0, r1])
	get_tree().quit(0)


## Grados que levanta el ánima sobre el horizonte. Positivo = apunta al cielo.
func _sobre_horizonte(c: Node3D) -> float:
	var d: Vector3 = c.call("direccion_global")
	return rad_to_deg(asin(clampf(d.normalized().y, -1.0, 1.0)))


## Distancia en planta de la boca al punto de caída.
func _alcance(c: Node3D) -> float:
	var boca: Vector3 = c.call("boca_global")
	var cae: Vector3 = c.call("punto_de_caida")
	return Vector2(cae.x - boca.x, cae.z - boca.z).length()

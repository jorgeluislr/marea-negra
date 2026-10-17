extends Node

## Hacia dónde se mueve la puntería cuando el jugador mueve el ratón, banda por banda.
##
## El apuntado fino es un solo número —`giro_lateral`, los grados de espeque— que se aplica a
## todas las piezas de la batería elegida. La pregunta es qué significa ese número VISTO POR
## QUIEN APUNTA, que es lo que el jugador siente: al mover el ratón a la derecha espera que la
## mira se vaya a la derecha, tire con la batería que tire.
##
## Se mide girando +10° y viendo hacia qué lado se movió la boca, en el marco de referencia del
## propio cañón: `derecha = dirección × arriba`. Una banda con el signo cambiado sale con el
## número en negativo.
##
##     godot --path . tools/apunte_por_banda.tscn

const GIRO := 10.0


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	var b := (load("res://scenes/barcos/balandra.tscn") as PackedScene).instantiate() as Node3D
	add_child(b)
	b.set("anclado", true)
	await get_tree().create_timer(4.0).timeout

	print("\n─── a dónde apunta cada banda ───")
	print("con el espeque a +%.0f°, cuánto se va la boca a la DERECHA del que apunta" % GIRO)
	print("%-22s %14s %14s %12s" % ["pieza", "banda", "a su derecha", "hacia proa"])
	for n in b.find_children("*", "Node3D", true, false):
		if not n.has_method("direccion_global"):
			continue
		var c := n as Node3D
		c.set("giro_lateral", 0.0)
		await get_tree().process_frame
		var d0: Vector3 = c.call("direccion_global")
		c.set("giro_lateral", GIRO)
		await get_tree().process_frame
		var d1: Vector3 = c.call("direccion_global")
		c.set("giro_lateral", 0.0)
		# La derecha de quien mira en `d0`. En coordenadas de Godot, mirando a −Z (la proa) esto
		# da +X, que es estribor: correcto.
		var derecha := d0.cross(Vector3.UP).normalized()
		var proa := -b.global_transform.basis.z.normalized()
		var giro := (d1 - d0)
		print("%-22s %14s %13.3f %12.3f"
			% [c.name, String(c.call("banda")), giro.dot(derecha), giro.dot(proa)])
	get_tree().quit(0)

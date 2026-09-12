extends Node

## Alcance real de cada pieza, medido en la escena de COMBATE (con mar) y en una balandra
## suelta (sin mar), para ver cuánto cambia el número según de dónde salga la altura del agua.
##
## Lo pide un aviso del compañero de la IA: `Barco._altura_del_mar()` devuelve 0 si no encuentra
## nodo de agua, y en esta balandra el mar está en −0,882, así que un cero deja la lámina medio
## metro por encima de la boca y el tiro cae mucho más corto. Cualquier herramienta que
## instancie el barco suelto mide otro juego.

func _ready() -> void:
	await _medir_suelto()
	get_tree().quit(0)


func _medir_suelto() -> void:
	var esc := load("res://scenes/barcos/balandra.tscn") as PackedScene
	for mar in [INF, -0.882]:
		var b := esc.instantiate() as Barco
		add_child(b)
		b.altura_mar = mar
		b.set("anclado", true)
		b.tomar_mando_jugador()
		await get_tree().create_timer(4.0).timeout
		var piezas: Array = b.canones_de("estribor")
		if piezas.is_empty():
			print("sin piezas"); continue
		var p: Canon = piezas[0]
		var boca: Vector3 = p.boca_global()
		var cae: Vector3 = p.punto_de_caida()
		print("altura_mar=%-8s → la pieza la toma como %.3f | ánima a %.3f (%.3f sobre el agua) | alcance %.1f m"
			% [("INF (se busca)" if not is_finite(mar) else "%.3f" % mar), p.altura_mar,
				boca.y, boca.y - p.altura_mar,
				Vector2(cae.x - boca.x, cae.z - boca.z).length()])
		if is_finite(mar):
			for g in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0]:
				for q in piezas:
					q.elevacion = g
				await get_tree().process_frame
				var b2: Vector3 = p.boca_global()
				var c2: Vector3 = p.punto_de_caida()
				print("    cuña %5.1f° → %6.1f m" % [g,
					Vector2(c2.x - b2.x, c2.z - b2.z).length()])
		b.queue_free()
		await get_tree().process_frame

extends Node

## A qué calado flota el barco y cuánto desplaza a ese calado.
##
## `altura_flotacion` es un número puesto a mano, y la pregunta que contesta esta herramienta es
## si ese número deja el casco donde lo dejaría el agua. La forma de saberlo no es mirarlo: es
## calcular el VOLUMEN SUMERGIDO y ver qué peso equilibra. Un casco que desplaza cinco toneladas
## no puede ser una balandra de carga de doce metros.
##
## El volumen se saca de la malla del casco por el teorema de la divergencia: se recorta cada
## triángulo por debajo del plano de flotación y se suma `a · (b × c) / 6`. La tapa que cierra el
## volumen por arriba no hace falta generarla — está en el plano y, con el origen puesto en ese
## mismo plano, aporta cero.
##
## Se imprime además la escala de calados, que es lo que hay que mirar para decidir: cuánto
## desplazaría a cada calado y qué francobordo le quedaría.
##
##     godot --path . tools/linea_de_flotacion.tscn

## Densidad del agua de mar, kg/m³.
const RHO := 1025.0


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit(1))
	# El MUNDO entero, no la balandra suelta: el nivel del mar lo fija `mar.gd` desde su propio
	# nodo, y sin él `Oleaje.nivel` vale 0 — que es justo el valor con el que la respuesta sale
	# bien por accidente. Con el agua donde de verdad está, sale otra cosa.
	add_child((load("res://scenes/world/main_world.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(7.0).timeout
	var b := get_tree().get_first_node_in_group("barco_activo") as Node3D
	if b == null:
		print("no hay barco")
		get_tree().quit(1)
		return
	b.set("anclado", true)

	var mi := _malla_casco(b)
	if mi == null:
		print("no encuentro la malla del casco")
		get_tree().quit(1)
		return
	# Vértices en ejes del BARCO, con la quilla como referencia.
	var a_local := b.global_transform.affine_inverse() * mi.global_transform
	var tris := mi.mesh.get_faces()
	var lo := INF
	var hi := -INF
	for v in tris:
		var p: Vector3 = a_local * v
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)

	var nivel: float = Oleaje.nivel
	var flota: float = float(b.get("altura_flotacion"))
	var calado := nivel - (flota + lo)
	print("\n─── línea de flotación ───")
	print("casco de %.2f m de puntal (de y=%.2f a y=%.2f en ejes del barco)" % [hi - lo, lo, hi])
	print("flota con el origen en y=%.3f y la lámina en y=%.3f" % [flota, nivel])
	print("→ CALADO actual %.2f m, o sea el %.0f %% del puntal"
		% [calado, 100.0 * calado / maxf(hi - lo, 0.01)])

	var v_actual := _volumen_bajo(tris, a_local, lo + calado)
	print("→ desplaza %.1f m³ = %.1f toneladas" % [v_actual, v_actual * RHO / 1000.0])

	print("\n%-10s %12s %14s %14s" % ["calado", "volumen m³", "desplaza t", "francobordo"])
	var c := 0.2
	while c <= minf(1.8, hi - lo):
		var v := _volumen_bajo(tris, a_local, lo + c)
		# Francobordo hasta el punto más alto del casco, que en esta balandra es la regala.
		print("%-10s %12.2f %13.1f %11.2f m %12.2f m"
			% ["%.2f m" % c, v, v * RHO / 1000.0, (hi - lo) - c, (y_cubierta - lo) - c])
		c += 0.2
	get_tree().quit(0)


## Volumen del casco por debajo de `y_corte`, en ejes del barco. Teorema de la divergencia sobre
## los triángulos recortados; el origen se lleva al plano de corte para que la tapa aporte cero.
func _volumen_bajo(tris: PackedVector3Array, a_local: Transform3D, y_corte: float) -> float:
	var vol := 0.0
	var t := 0
	while t + 2 < tris.size():
		var p: Array[Vector3] = []
		for k in 3:
			var q: Vector3 = a_local * tris[t + k]
			p.append(Vector3(q.x, q.y - y_corte, q.z))
		t += 3
		# Recorte del triángulo contra el semiespacio y ≤ 0 (Sutherland-Hodgman).
		var dentro: Array[Vector3] = []
		for k in 3:
			var a: Vector3 = p[k]
			var b: Vector3 = p[(k + 1) % 3]
			if a.y <= 0.0:
				dentro.append(a)
			if (a.y <= 0.0) != (b.y <= 0.0):
				var f: float = a.y / (a.y - b.y)
				dentro.append(a.lerp(b, f))
		# El polígono recortado, en abanico.
		for k in range(1, dentro.size() - 1):
			vol += dentro[0].dot(dentro[k].cross(dentro[k + 1])) / 6.0
	return absf(vol)


func _malla_casco(b: Node3D) -> MeshInstance3D:
	var nombre := String(b.get("colision_casco"))
	for n in b.find_children("*", "MeshInstance3D", true, false):
		if n.name == nombre:
			return n as MeshInstance3D
	return null

extends Node

## Dónde están los frames LENTOS del arranque, y en cuál nace cada paño.
##
## Importa porque un `SoftBody3D` que se crea durante un tirón sale roto y el solver no vuelve a
## cerrar esas aristas nunca (ver `TelaFisica.delta_estable` y la nota del arranque en
## CLAUDE.md). `TelaFisica` espera a que haya varios frames normales seguidos, pero eso solo
## mira hacia ATRÁS: si el tirón llega justo después de que el paño nazca, el paño se lo come
## igual. Así que no basta con que el arranque tenga pocos tirones, hay que saber DÓNDE caen
## respecto al nacimiento.
##
## Cada línea es un frame que pasa del umbral, y se marca el frame en que aparece cada paño.
##
##     godot --path . tools/tirones_del_arranque.tscn
##
## Con ventana: en `--headless` no se compilan los shaders espaciales, que son medio tirón.

## Frame que `TelaFisica` considera normal. Mismo número, para hablar de lo mismo.
const NORMAL := 1.0 / 30.0
const FRAMES := 150


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit(1))
	var esc := load("res://scenes/world/main_world.tscn") as PackedScene
	add_child(esc.instantiate())

	var nacidos := {}
	var peor := 0.0
	var peor_en := 0
	var lentos := 0
	var lineas: Array[String] = []
	for f in FRAMES:
		await get_tree().process_frame
		var d := get_process_delta_time()
		if d > peor:
			peor = d
			peor_en = f
		if d > NORMAL:
			lentos += 1
			lineas.append("   frame %3d: %6.1f ms" % [f, d * 1000.0])
		# Los paños del barco activo, en cuanto tengan cuerpo.
		var b := get_tree().get_first_node_in_group("barco_activo")
		if b != null:
			for t in b.get_children():
				if not t.has_method("datos_depuracion"):
					continue
				var nombre := str(t.get("nombre_malla"))
				if nacidos.has(nombre):
					continue
				var dd: Dictionary = t.datos_depuracion()
				if not dd.is_empty() and dd.get("cuerpo") != null:
					nacidos[nombre] = f
					lineas.append("   frame %3d: NACE '%s'" % [f, nombre])

	lineas.sort_custom(func(a, b): return a.substr(9, 3).to_int() < b.substr(9, 3).to_int())
	print("\n─── tirones del arranque ───")
	print("frames por encima de %.1f ms: %d de %d" % [NORMAL * 1000.0, lentos, FRAMES])
	print("el peor: %.1f ms en el frame %d" % [peor * 1000.0, peor_en])
	for l in lineas:
		print(l)
	# Lo que de verdad decide: si tras nacer cada pano quedo algun tiron.
	print("")
	for nombre in nacidos:
		print("   '%s' nació en el frame %d" % [nombre, nacidos[nombre]])
	get_tree().quit(0)

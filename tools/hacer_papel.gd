extends Node
## Saca de la carta de Meshy una baldosa de papel que empalma por sus cuatro lados.
##
##     godot --path . tools/hacer_papel.tscn -- <carta recortada> <png de salida> [x y lado]
##
## Tres pasos:
##
## 1. **Un trozo de mar sin adornos**: por defecto el cuadrado de la mitad derecha, entre la cartela
##    y el barco, donde solo hay papel, rayado de olas y líneas de rumbo.
## 2. **Fuera la tinta**: las líneas de rumbo son mucho más oscuras que el rayado de olas, así que
##    un umbral de luminancia las separa. Se marcan (ensanchadas un píxel) y se rellenan con el papel
##    de alrededor por difusión: cada píxel marcado toma la media de sus vecinos ya buenos, pasada
##    tras pasada, hasta que no queda ninguno. Una línea de 2-3 px se cierra en tres o cuatro pasadas.
## 3. **Que empalme**: se mezcla el trozo con él mismo desplazado medio lado, con un peso que vale 1
##    en el centro y 0 en los bordes. En los bordes manda la copia desplazada, cuyo contenido allí es
##    el CENTRO del original, continuo a través del borde; así la baldosa se repite sin costura.
##
## Imprime la diferencia entre bordes opuestos antes y después, que es lo que dice si empalma.

const UMBRAL_TINTA := 0.55


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit.bind(1))
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	img.convert(Image.FORMAT_RGB8)
	var x := int(a[2]) if a.size() > 4 else 470
	var y := int(a[3]) if a.size() > 4 else 340
	var lado := int(a[4]) if a.size() > 4 else 288
	var trozo := img.get_region(Rect2i(x, y, lado, lado))
	print("trozo de %d px en (%d, %d); bordes antes: %.4f" % [lado, x, y, _costura(trozo)])

	var tinta := _quitar_tinta(trozo)
	print("tinta borrada: %d píxeles (%.1f %%)" % [tinta, 100.0 * tinta / (lado * lado)])
	var baldosa := _sin_costura(trozo)
	print("bordes después: %.4f  (0 = empalma perfecto)" % _costura(baldosa))
	baldosa.save_png(a[1])
	print("guardada %s" % a[1])
	get_tree().quit()


func _quitar_tinta(img: Image) -> int:
	var n := img.get_width()
	var malo := PackedByteArray()
	malo.resize(n * n)
	for j in n:
		for i in n:
			if img.get_pixel(i, j).get_luminance() < UMBRAL_TINTA:
				# Ensanchada un píxel: el borde de la línea es más claro y pasa del umbral.
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var ii := clampi(i + di, 0, n - 1)
						var jj := clampi(j + dj, 0, n - 1)
						malo[jj * n + ii] = 1
	var total := 0
	for v in malo:
		total += v
	var quedan := total
	while quedan > 0:
		var siguiente := malo.duplicate()
		for j in n:
			for i in n:
				if malo[j * n + i] == 0:
					continue
				var suma := Color(0, 0, 0)
				var k := 0
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ii := i + d.x
					var jj := j + d.y
					if ii < 0 or jj < 0 or ii >= n or jj >= n or malo[jj * n + ii] == 1:
						continue
					suma += img.get_pixel(ii, jj)
					k += 1
				if k > 0:
					img.set_pixel(i, j, suma / k)
					siguiente[j * n + i] = 0
		malo = siguiente
		quedan = 0
		for v in malo:
			quedan += v
	return total


func _sin_costura(img: Image) -> Image:
	var n := img.get_width()
	var h := n / 2
	var out := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	for j in n:
		for i in n:
			# 1 en el centro, 0 en el borde, en cada eje; el producto da el peso del original.
			var wx := 1.0 - absf(float(i) - (n - 1) * 0.5) / ((n - 1) * 0.5)
			var wy := 1.0 - absf(float(j) - (n - 1) * 0.5) / ((n - 1) * 0.5)
			var w := smoothstep(0.0, 1.0, minf(wx, wy) * 2.0)
			var o := img.get_pixel(i, j)
			var d := img.get_pixel((i + h) % n, (j + h) % n)
			out.set_pixel(i, j, d.lerp(o, w))
	return out


## Diferencia media entre la primera y la última columna, y la primera y la última fila. Una
## baldosa que empalma la tiene del orden de la de dos columnas vecinas cualesquiera.
func _costura(img: Image) -> float:
	var n := img.get_width()
	var s := 0.0
	for k in n:
		s += _dif(img.get_pixel(0, k), img.get_pixel(n - 1, k))
		s += _dif(img.get_pixel(k, 0), img.get_pixel(k, n - 1))
	return s / (2 * n)


func _dif(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0

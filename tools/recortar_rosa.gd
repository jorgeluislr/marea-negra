extends Node
## Saca la rosa de los vientos de la carta de Meshy como imagen con transparencia, para ponerla
## pequeña y quieta en una esquina de la carta.
##
##     godot --path . tools/recortar_rosa.tscn -- <carta recortada> <png de salida> <cx> <cy> <r>
##
## `cx cy r` son una estimación a ojo del círculo exterior; la herramienta la AFINA buscando, en
## ±12 px de centro y ±15 de radio, el anillo con más tinta, que es la línea del círculo. Se queda
## con lo que hay dentro de ese círculo más la flor de lis de encima, y nada más: así los rumbos que
## salen de la rosa hacia toda la carta no vienen con ella.
##
## La transparencia sale de la luminancia: el papel es claro y la tinta oscura, así que cada píxel es
## tanto más opaco cuanto más se aparta del papel. El color se conserva: sepia sobre nada.

const PAPEL := 0.80     # luminancia por encima de la cual es papel (transparente)
const TINTA := 0.40     # por debajo, tinta opaca


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit.bind(1))
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	img.convert(Image.FORMAT_RGBA8)
	var c := Vector2(float(a[2]), float(a[3]))
	var r := float(a[4])

	var mejor := -1.0
	var mc := c
	var mr := r
	for dy in range(-12, 13, 2):
		for dx in range(-12, 13, 2):
			for dr in range(-15, 16):
				var f := _tinta_en_anillo(img, c + Vector2(dx, dy), r + dr)
				if f > mejor:
					mejor = f
					mc = c + Vector2(dx, dy)
					mr = r + dr
	print("círculo afinado: centro (%.0f, %.0f), radio %.0f, tinta en el anillo %.2f"
		% [mc.x, mc.y, mr, mejor])

	# La flor de lis: un rectángulo estrecho encima del círculo.
	var lis := Rect2(mc.x - 34, mc.y - mr - 88, 68, 92)
	var caja := Rect2(mc - Vector2(mr, mr) - Vector2(4, 4), Vector2(mr, mr) * 2.0 + Vector2(8, 8))
	caja = caja.merge(lis)
	var out := Image.create_empty(int(caja.size.x), int(caja.size.y), false, Image.FORMAT_RGBA8)
	for j in out.get_height():
		for i in out.get_width():
			var p := caja.position + Vector2(i, j)
			if p.distance_to(mc) > mr + 3.0 and not lis.has_point(p):
				continue
			if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
				continue
			var col := img.get_pixel(int(p.x), int(p.y))
			var alfa := clampf((PAPEL - col.get_luminance()) / (PAPEL - TINTA), 0.0, 1.0)
			out.set_pixel(i, j, Color(col.r, col.g, col.b, alfa))
	out.save_png(a[1])
	print("rosa de %d × %d px guardada en %s" % [out.get_width(), out.get_height(), a[1]])
	get_tree().quit()


func _tinta_en_anillo(img: Image, c: Vector2, r: float) -> float:
	var n := 0
	var t := 0
	for k in 180:
		var p := c + Vector2.from_angle(TAU * k / 180.0) * r
		if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
			continue
		n += 1
		if img.get_pixel(int(p.x), int(p.y)).get_luminance() < 0.55:
			t += 1
	return float(t) / maxf(n, 1)

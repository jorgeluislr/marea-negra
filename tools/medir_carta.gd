extends Node
## Prepara la imagen de la carta: recorta el fondo que rodea el pergamino y MIDE dónde está la
## línea interior del marco, que es el rectángulo que se corresponde con el mundo
## (`Carta.rect_interior`).
##
##     godot --path . tools/medir_carta.tscn -- <imagen de origen> [<png de salida>]
##
## La línea interior se busca por lo que la distingue de todo lo demás que hay dibujado: es una
## línea RECTA y LARGA. Los rumbos que salen de la rosa son diagonales y cruzan cada columna en
## un solo punto; la línea del marco oscurece la columna entera. Así que por cada columna se cuenta
## qué fracción del tramo central es tinta, y la línea del marco es la columna más cercana al centro
## que pasa del umbral, a cada lado. Igual con las filas.

const UMBRAL_TINTA := 0.62      # luminancia por debajo de la cual un píxel es tinta
const FRACCION_LINEA := 0.75    # qué parte de la columna tiene que ser tinta para ser la línea
const FRANJA_MARCO := 0.16      # el marco ocupa ~1/12 del lado; se busca en el 16 % de cada borde


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit.bind(1))
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("medir_carta: falta la imagen de origen")
		get_tree().quit(1)
		return
	var img := Image.load_from_file(args[0])
	img.convert(Image.FORMAT_RGB8)
	var w := img.get_width()
	var h := img.get_height()

	# 1. El pergamino: todo lo que se aparta del color de la esquina, que es el fondo.
	var fondo := img.get_pixel(2, 2)
	var r := Rect2i(w, h, 0, 0)
	var x0 := w; var y0 := h; var x1 := 0; var y1 := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if absf(c.r - fondo.r) + absf(c.g - fondo.g) + absf(c.b - fondo.b) > 0.12:
				x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
	r = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	# Hacia dentro unos píxeles: el borde rasgado del papel deja huecos de fondo en las esquinas.
	r = r.grow(-6)
	var carta := img.get_region(r)
	var cw := carta.get_width()
	var ch := carta.get_height()

	# 2. La línea interior del marco.
	var col := PackedFloat32Array(); col.resize(cw)
	var fil := PackedFloat32Array(); fil.resize(ch)
	for x in cw:
		var n := 0
		for y in range(int(ch * 0.3), int(ch * 0.7)):
			if carta.get_pixel(x, y).get_luminance() < UMBRAL_TINTA:
				n += 1
		col[x] = float(n) / (ch * 0.4)
	for y in ch:
		var n := 0
		for x in range(int(cw * 0.3), int(cw * 0.7)):
			if carta.get_pixel(x, y).get_luminance() < UMBRAL_TINTA:
				n += 1
		fil[y] = float(n) / (cw * 0.4)
	# Solo en la franja del marco: el rumbo que sube recto desde la rosa también es una línea
	# vertical larga, y buscando hasta el 30 % del ancho se tomaba por el marco (x = 224 en vez de
	# 84 en la imagen de 828 px).
	var izq := _mas_interior(col, 0, int(cw * FRANJA_MARCO), 1)
	var der := _mas_interior(col, cw - 1, int(cw * (1.0 - FRANJA_MARCO)), -1)
	var arr := _mas_interior(fil, 0, int(ch * FRANJA_MARCO), 1)
	var aba := _mas_interior(fil, ch - 1, int(ch * (1.0 - FRANJA_MARCO)), -1)
	print("imagen %d × %d, pergamino %s → %d × %d" % [w, h, str(r), cw, ch])
	print("línea interior del marco: x %d..%d, y %d..%d" % [izq, der, arr, aba])
	print("rect_interior = Rect2(%d, %d, %d, %d)" % [izq, arr, der - izq, aba - arr])
	print("perfil columnas (izq): %s" % _perfil(col, 0, int(cw * FRANJA_MARCO)))
	print("perfil filas (arr):    %s" % _perfil(fil, 0, int(ch * FRANJA_MARCO)))
	if args.size() > 1:
		carta.save_png(args[1])
		print("guardada %s" % args[1])
	get_tree().quit()


## La posición que pasa del umbral más cerca del centro, buscando de `desde` hacia `hasta`.
func _mas_interior(v: PackedFloat32Array, desde: int, hasta: int, paso: int) -> int:
	var mejor := -1
	var i := desde
	while i != hasta:
		if v[i] >= FRACCION_LINEA:
			mejor = i
		i += paso
	return mejor


func _perfil(v: PackedFloat32Array, a: int, b: int) -> String:
	var s := []
	for i in range(a, b):
		if v[i] >= 0.4:
			s.append("%d:%.2f" % [i, v[i]])
	return ", ".join(s)

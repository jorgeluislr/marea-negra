extends SceneTree

## Pasa las imágenes de Meshy del HUD (`fuentes/crudo/hud/`) a texturas con alfa en
## `assets/textures/ui/`. No toca los originales.
##
##     godot --path . --headless -s tools/procesar_iconos_hud.gd
##
## Dos maneras de sacar el fondo, según la imagen:
## - **Iconos** (tinta sobre pergamino, en una hoja de 3 × 3): el alfa es lo OSCURA que es la tinta
##   respecto al pergamino de su casilla, y el color se des-mezcla del pergamino para que los bordes
##   no traigan un halo claro. Así el icono queda en tinta pura y se puede poner sobre cualquier
##   disco.
## - **Marco, rosa y cartela** (objeto sobre blanco): el fondo es lo gris claro CONECTADO al borde
##   de la imagen, rellenado desde fuera. No vale un umbral de blanco a secas: la cartela trae un
##   degradado gris y una sombra (hasta 0,95), y el pergamino tiene brillos casi blancos dentro.

const CRUDO := "res://fuentes/crudo/hud/"
const SALIDA := "res://assets/textures/ui/"
const HOJA := "Meshy_AI_bb7c4d77e75996daa40df29095bdf6bfc3ab75113dcad4f4f34ff0d4b02959a9.png"
const MARCO := "Meshy_AI_2744e8d19832e07d01a926304cf22f3119f30a8b90356b657da43f9895631a11.png"
const ROSA := "Meshy_AI_8741f128c932528da86bbccffd219dfe1a678321ff4956a3ac466eb19870b5d0.png"
const CARTELA := "Meshy_AI_1f700501fcf7733ce14ec191fb3afc77db8a22b77c855e6fbae656fe770b9eb9.png"
## Las casillas de la hoja, de izquierda a derecha y de arriba abajo, como se pidieron.
const NOMBRES := ["foque", "mayor", "ancla", "timon", "cubierta", "batalla", "municion", "canon",
	"dano"]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))
	_hoja()
	_sobre_blanco(MARCO, "marco_laton.png", 256)
	_sobre_blanco(ROSA, "rosa_esfera.png", 512)
	_sobre_blanco(CARTELA, "cartela.png", 512)
	quit(0)


func _cargar(nombre: String) -> Image:
	var im := Image.load_from_file(ProjectSettings.globalize_path(CRUDO + nombre))
	im.convert(Image.FORMAT_RGBA8)
	return im


## Las bandas blancas que separan las casillas: tramos de columnas (o filas) casi blancas.
func _cortes(im: Image, por_x: bool) -> Array[Vector2i]:
	var n := im.get_width() if por_x else im.get_height()
	var m := im.get_height() if por_x else im.get_width()
	var lleno: Array[bool] = []
	for i in n:
		var blancos := 0
		for j in range(0, m, 4):
			var c := im.get_pixel(i, j) if por_x else im.get_pixel(j, i)
			if minf(c.r, minf(c.g, c.b)) > 0.95:
				blancos += 1
		lleno.append(float(blancos) / float(m / 4) < 0.6)
	var tramos: Array[Vector2i] = []
	var desde := -1
	for i in n:
		if lleno[i] and desde < 0:
			desde = i
		elif not lleno[i] and desde >= 0:
			if i - desde > n / 10:
				tramos.append(Vector2i(desde, i))
			desde = -1
	if desde >= 0 and n - desde > n / 10:
		tramos.append(Vector2i(desde, n))
	return tramos


func _hoja() -> void:
	var im := _cargar(HOJA)
	var cols := _cortes(im, true)
	var filas := _cortes(im, false)
	print("hoja: columnas %s, filas %s" % [cols, filas])
	if cols.size() != 3 or filas.size() != 3:
		push_error("la hoja no se parte en 3 × 3")
		return
	var k := 0
	for f in filas:
		for c in cols:
			var margen := 8
			var r := Rect2i(c.x + margen, f.x + margen, c.y - c.x - margen * 2, f.y - f.x - margen * 2)
			var celda := im.get_region(r)
			var icono := _sin_motas(_tinta(celda))
			_guardar(_cuadrar(icono, 256), "icono_%s.png" % NOMBRES[k])
			k += 1


## Borra las motas: las manchas del papel que pasan por tinta tenue. Sin esto la caja del icono
## la marcaban ellas y no el dibujo, y el icono salía descentrado (el cañón tenía la tinta en
## x 81-210 de 256 y la caja en 43-212). Se queda con las manchas de tinta FIRME (alfa > 0,4) que
## pesan al menos un 1 % de la mayor, y con lo tenue que las toca; el resto fuera.
func _sin_motas(im: Image) -> Image:
	var w := im.get_width()
	var h := im.get_height()
	var marca := PackedInt32Array()
	marca.resize(w * h)
	marca.fill(-1)
	var tamanos: Array[int] = []
	for i in w * h:
		if marca[i] >= 0 or im.get_pixel(i % w, i / w).a <= 0.4:
			continue
		var id := tamanos.size()
		var n := 0
		var pila: Array[int] = [i]
		marca[i] = id
		while not pila.is_empty():
			var j: int = pila.pop_back()
			n += 1
			var x := j % w
			var y := j / w
			for v: Vector2i in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1),
					Vector2i(x, y + 1)]:
				if v.x < 0 or v.y < 0 or v.x >= w or v.y >= h:
					continue
				var vecino: int = v.y * w + v.x
				if marca[vecino] < 0 and im.get_pixel(v.x, v.y).a > 0.4:
					marca[vecino] = id
					pila.append(vecino)
		tamanos.append(n)
	var mayor := 0
	for n in tamanos:
		mayor = maxi(mayor, n)
	# Lo firme que se queda, y un margen de 3 px alrededor para conservar el borde suave.
	var queda := PackedByteArray()
	queda.resize(w * h)
	for i in w * h:
		if marca[i] >= 0 and tamanos[marca[i]] * 100 >= mayor:
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var x := clampi(i % w + dx, 0, w - 1)
					var y := clampi(i / w + dy, 0, h - 1)
					queda[y * w + x] = 1
	for i in w * h:
		if not queda[i]:
			im.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
	return im


## Tinta sobre pergamino → tinta sobre transparente.
func _tinta(im: Image) -> Image:
	# El pergamino de la casilla: la mediana del borde, que es papel sin dibujo.
	var borde: Array[Color] = []
	for x in im.get_width():
		borde.append(im.get_pixel(x, 2))
		borde.append(im.get_pixel(x, im.get_height() - 3))
	borde.sort_custom(func(a, b): return a.get_luminance() < b.get_luminance())
	var papel: Color = borde[borde.size() / 2]
	var l_papel := papel.get_luminance()
	const L_TINTA := 0.12
	var sale := Image.create(im.get_width(), im.get_height(), false, Image.FORMAT_RGBA8)
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			var a := clampf((l_papel - c.get_luminance()) / (l_papel - L_TINTA), 0.0, 1.0)
			# Quita el ruido de las manchas del papel, que no son tinta.
			a = clampf((a - 0.12) / 0.88, 0.0, 1.0)
			if a <= 0.0:
				sale.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var t := Color((c.r - papel.r * (1.0 - a)) / a, (c.g - papel.g * (1.0 - a)) / a,
				(c.b - papel.b * (1.0 - a)) / a, a)
			sale.set_pixel(x, y, Color(clampf(t.r, 0, 1), clampf(t.g, 0, 1), clampf(t.b, 0, 1), a))
	return sale


func _sobre_blanco(nombre: String, destino: String, lado: int) -> void:
	var im := _cargar(nombre)
	var fondo := _fondo(im)
	var w := im.get_width()
	var h := im.get_height()
	# Borde suave: el alfa es la parte de la vecindad 3 × 3 que no es fondo.
	for y in h:
		for x in w:
			if fondo[y * w + x]:
				im.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var dentro := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var xx := clampi(x + dx, 0, w - 1)
					var yy := clampi(y + dy, 0, h - 1)
					if not fondo[yy * w + xx]:
						dentro += 1
			if dentro < 9:
				var c := im.get_pixel(x, y)
				c.a = float(dentro) / 9.0
				im.set_pixel(x, y, c)
	var caja := im.get_used_rect()
	print("%s: objeto en %s" % [destino, caja])
	var recorte := im.get_region(caja)
	# Los redondos se cuadran centrados para que su centro sea el del dibujo: es el eje de las
	# agujas. La cartela conserva su proporción.
	if destino == "cartela.png":
		var alto := int(float(lado) * float(recorte.get_height()) / float(recorte.get_width()))
		recorte.resize(lado, alto, Image.INTERPOLATE_LANCZOS)
		_guardar(recorte, destino)
		# Y una pequeña para el nueve-parches de la cartela del HUD: las esquinas de un
		# `StyleBoxTexture` se dibujan a su tamaño en píxeles, así que la textura tiene que venir ya
		# a la escala a la que se ve (128 de alto para una cartela de 84).
		var chica := recorte.duplicate() as Image
		chica.resize(int(128.0 * float(lado) / float(alto)), 128, Image.INTERPOLATE_LANCZOS)
		_guardar(chica, "cartela_hud.png")
	else:
		_guardar(_cuadrar(recorte, lado), destino)


## Lo que es fondo: casi gris (poca saturación) y claro, y alcanzable desde el borde.
func _fondo(im: Image) -> PackedByteArray:
	var w := im.get_width()
	var h := im.get_height()
	var es := PackedByteArray()
	es.resize(w * h)
	var pila: Array[int] = []
	for x in w:
		pila.append(x)
		pila.append((h - 1) * w + x)
	for y in h:
		pila.append(y * w)
		pila.append(y * w + w - 1)
	while not pila.is_empty():
		var i: int = pila.pop_back()
		if es[i]:
			continue
		var c := im.get_pixel(i % w, i / w)
		var hi := maxf(c.r, maxf(c.g, c.b))
		var lo := minf(c.r, minf(c.g, c.b))
		if hi - lo > 0.05 or lo < 0.72:
			continue
		es[i] = 1
		var x := i % w
		if x > 0: pila.append(i - 1)
		if x < w - 1: pila.append(i + 1)
		if i >= w: pila.append(i - w)
		if i < w * (h - 1): pila.append(i + w)
	return es


## Centra en un cuadrado transparente con un margen mínimo y lo lleva a `lado` píxeles.
func _cuadrar(im: Image, lado: int) -> Image:
	var caja := im.get_used_rect()
	if caja.size.x == 0:
		caja = Rect2i(Vector2i.ZERO, im.get_size())
	var trozo := im.get_region(caja)
	var n := maxi(trozo.get_width(), trozo.get_height())
	var lienzo := Image.create(n, n, false, Image.FORMAT_RGBA8)
	lienzo.fill(Color(0, 0, 0, 0))
	lienzo.blit_rect(trozo, Rect2i(Vector2i.ZERO, trozo.get_size()),
		Vector2i((n - trozo.get_width()) / 2, (n - trozo.get_height()) / 2))
	lienzo.resize(lado, lado, Image.INTERPOLATE_LANCZOS)
	return lienzo


func _guardar(im: Image, nombre: String) -> void:
	var ruta := ProjectSettings.globalize_path(SALIDA + nombre)
	im.save_png(ruta)
	print("guardado %s (%d × %d)" % [nombre, im.get_width(), im.get_height()])

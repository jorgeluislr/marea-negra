extends SceneTree

## Pasa las imágenes de Meshy del menú (`fuentes/crudo/menu/`) a texturas con alfa en
## `assets/textures/ui/`: el título «Marea Negra» y el marco de los paneles. No toca los originales.
##
##     godot --path . --headless -s tools/procesar_menu.gd
##
## El fondo se saca como el del marco y la cartela del HUD (`tools/procesar_iconos_hud.gd`): lo gris
## claro CONECTADO al borde, rellenado desde fuera, con el canto suavizado por la vecindad 3 × 3. Un
## umbral de blanco a secas se comería los brillos del pergamino y dejaría la sombra.
##
## **El marco se usa como nueve-parches** (`TemaMenu.marco()`), y un `StyleBoxTexture` dibuja las
## esquinas a su tamaño en píxeles: por eso la textura sale ya a la escala a la que se ve, con el
## marco a `ANCHO_MARCO` píxeles. Imprime los márgenes del recuadro liso de dentro (lo que queda para
## los botones), medidos en la imagen de salida; `TemaMenu.MARGENES_MARCO` los copia.

const CRUDO := "res://fuentes/crudo/menu/"
const SALIDA := "res://assets/textures/ui/"
const TITULO := "Meshy_AI_0f049f75312ebe80c16c01685fe3d809a41eb5e0cba367a7e738af13965ae10d.png"
const MARCO := "Meshy_AI_ebe41f53db7f749426fac0583b41fd1b70e847531fc79f9fcdd3aa0e364034bb.png"
const ANCHO_TITULO := 900
const ANCHO_MARCO := 440
## Las letras del título solas, sobre blanco (prompt «Letras del título, solas»). Vacío hasta que
## lleguen.
const LETRAS := "Meshy_AI_marea_negra_text_extracted.png"
## Dónde van MAREA y NEGRA en el lienzo del título entero (900 × 469), medido sobre `titulo_menu.png`
## por el contorno oscuro de sus letras (filas y columnas con píxeles de valor < 0,35, sin los rollos
## del pergamino). Cada línea de las letras solas se lleva a su caja, para que caigan encima de las del
## pergamino y el fundido del final de la intro case.
## El alto, por el LATÓN (saturado y no oscuro) y no por lo oscuro: medido sobre el original de Meshy,
## las letras van de la fila 102 a la 257 y de la 266 a la 420; con la primera medida (106-254) las
## antiguas asomaban por arriba y por abajo («la letra es más alta», el usuario).
const LINEAS := [Rect2i(84, 102, 734, 155), Rect2i(108, 266, 702, 154)]
## Trazo oscuro por fuera de las letras nuevas, en píxeles: tapa los bordes de las antiguas que aún
## asoman, donde el dibujo de una y otra no coincide.
const TRAZO := 3
## MAREA y NEGRA: cinco letras cada una. Y cuánto (fracción del ancho) se busca el corte a cada lado de
## donde se espera.
const LETRAS_POR_LINEA := 5
const VENTANA_CORTE := 0.07

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SALIDA))
	var t := _recortar(_cargar(TITULO))
	t.resize(ANCHO_TITULO, int(ANCHO_TITULO * float(t.get_height()) / t.get_width()),
		Image.INTERPOLATE_LANCZOS)
	# Las letras solas, para la intro, salen de una generación aparte sobre blanco (`LETRAS`). Del
	# título no se pueden recortar: las caras de la R y la A son del mismo crema que el pergamino, y
	# ni por color ni por el contorno oscuro de las letras salía limpio (22-10-2026, tres intentos).
	# Y el título del menú las lleva ENCIMA de las suyas: no casan píxel a píxel con las del pergamino
	# (otra generación), y el paso de unas a otras al final de la intro se notaba mucho (el usuario).
	# Con las mismas letras en los dos, el paso no cambia ni un píxel.
	if LETRAS != "" and FileAccess.file_exists(ProjectSettings.globalize_path(CRUDO + LETRAS)):
		var letras := _con_trazo(_por_lineas(_recortar(_cargar(LETRAS), true), t), TRAZO)
		_guardar(letras, "titulo_letras.png")
		t.blend_rect(letras, Rect2i(Vector2i.ZERO, letras.get_size()), Vector2i.ZERO)
	_guardar(t, "titulo_menu.png")
	var m := _recortar(_cargar(MARCO))
	m.resize(ANCHO_MARCO, int(ANCHO_MARCO * float(m.get_height()) / m.get_width()),
		Image.INTERPOLATE_LANCZOS)
	_guardar(m, "marco_menu.png")
	_recuadro(m)
	quit(0)


func _cargar(nombre: String) -> Image:
	var im := Image.load_from_file(ProjectSettings.globalize_path(CRUDO + nombre))
	im.convert(Image.FORMAT_RGBA8)
	return im


## Fondo fuera, canto suave y recorte a lo que queda. Con `huecos`, también el blanco ENCERRADO (el
## triángulo de la A, el ojo de la R), que el relleno desde fuera no alcanza: vale para las letras
## solas, que son de latón y nunca blancas; no para el título, cuyo pergamino es casi blanco.
func _recortar(im: Image, huecos := false) -> Image:
	var fondo := _fondo(im)
	if huecos:
		for i in fondo.size():
			if not fondo[i] and _es_blanco(im.get_pixel(i % im.get_width(), i / im.get_width())):
				fondo[i] = 1
	var w := im.get_width()
	var h := im.get_height()
	for y in h:
		for x in w:
			if fondo[y * w + x]:
				im.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var dentro := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if not fondo[clampi(y + dy, 0, h - 1) * w + clampi(x + dx, 0, w - 1)]:
						dentro += 1
			if dentro < 9:
				var c := im.get_pixel(x, y)
				c.a = float(dentro) / 9.0
				im.set_pixel(x, y, c)
	var caja := im.get_used_rect()
	print("objeto en %s" % caja)
	return im.get_region(caja)


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
		if not _es_blanco(im.get_pixel(i % w, i / w)):
			continue
		es[i] = 1
		var x := i % w
		if x > 0: pila.append(i - 1)
		if x < w - 1: pila.append(i + 1)
		if i >= w: pila.append(i - w)
		if i < w * (h - 1): pila.append(i + w)
	return es


## Casi gris (poca saturación) y claro: el fondo blanco y su sombra.
static func _es_blanco(c: Color) -> bool:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	return hi - lo <= 0.05 and lo >= 0.72


## Las letras partidas en sus dos líneas (por la fila vacía entre ellas) y cada una llevada a su caja
## de `LINEAS` LETRA A LETRA: en las dos imágenes se buscan los cortes entre letras (la columna con
## menos letra entre una y otra) y la línea se deforma por tramos, cada letra al ancho de la suya en el
## pergamino. La deformación es continua (lineal por tramos en x), así que donde dos letras se tocan no
## queda corte.
func _por_lineas(l: Image, titulo: Image) -> Image:
	var w := l.get_width()
	var h := l.get_height()
	var llenas: Array[int] = []
	for y in h:
		var k := 0
		for x in w:
			if l.get_pixel(x, y).a > 0.5:
				k += 1
		llenas.append(k)
	# La fila más vacía del tercio central separa las dos líneas.
	var corte := h / 3
	for y in range(h / 3, 2 * h / 3):
		if llenas[y] < llenas[corte]:
			corte = y
	var lienzo := titulo.get_size()
	var sale := Image.create(lienzo.x, lienzo.y, false, Image.FORMAT_RGBA8)
	sale.fill(Color(0, 0, 0, 0))
	for i in 2:
		var franja := l.get_region(Rect2i(0, 0, w, corte) if i == 0 else Rect2i(0, corte, w, h - corte))
		var trozo := franja.get_region(franja.get_used_rect())
		var caja: Rect2i = LINEAS[i]
		# Cortes en el pergamino (contorno oscuro) y en las letras solas (alfa), en fracción del ancho.
		var destino := _cortes(titulo, caja, func(c: Color) -> bool: return c.a > 0.5 and c.v < 0.35, PackedFloat32Array())
		var origen := _cortes(trozo, Rect2i(Vector2i.ZERO, trozo.get_size()),
			func(c: Color) -> bool: return c.a > 0.5, destino)
		print("línea %d: cortes destino %s, origen %s" % [i + 1, destino, origen])
		# El alto no se ajusta letra a letra: medido, todas ocupan el alto entero de su línea en las
		# dos imágenes (de 0 a 1, con 0,014 de diferencia como mucho).
		for x in caja.size.x:
			var sx := _tramo((float(x) + 0.5) / caja.size.x, destino, origen) * trozo.get_width() - 0.5
			for y in caja.size.y:
				var sy := (float(y) + 0.5) / caja.size.y * trozo.get_height() - 0.5
				var c := _bilineal(trozo, sx, sy)
				if c.a > 0.0:
					sale.set_pixel(caja.position.x + x, caja.position.y + y, c)
	return sale


## Las letras con un trazo de `px` píxeles por fuera, del color medio de su propio contorno oscuro.
func _con_trazo(l: Image, px: int) -> Image:
	var w := l.get_width()
	var h := l.get_height()
	var suma := Color(0, 0, 0, 0)
	var n := 0
	for y in h:
		for x in w:
			var c := l.get_pixel(x, y)
			if c.a > 0.9 and c.v < 0.3:
				suma += c
				n += 1
	var tinta := suma / maxf(n, 1)
	tinta.a = 1.0
	var sale := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sale.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if l.get_pixel(x, y).a > 0.5:
				continue
			# Alfa del trazo: lo cerca que está la letra más próxima, con el canto suavizado.
			var mejor := 999.0
			for dy in range(-px - 1, px + 2):
				for dx in range(-px - 1, px + 2):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and yy >= 0 and xx < w and yy < h and l.get_pixel(xx, yy).a > 0.5:
						mejor = minf(mejor, Vector2(dx, dy).length())
			if mejor <= px + 1:
				var c := tinta
				c.a = clampf(px + 1.0 - mejor, 0.0, 1.0)
				sale.set_pixel(x, y, c)
	sale.blend_rect(l, Rect2i(Vector2i.ZERO, l.get_size()), Vector2i.ZERO)
	print("trazo de %d px, tinta %s" % [px, tinta])
	return sale


## Los cortes entre letras de una línea de LETRAS_POR_LINEA, en fracción de su ancho (0 y 1 en los
## extremos): la columna con menos "letra" (según `es_letra`), suavizada, en una ventana alrededor de
## donde se espera. Sin `guia`, el corte se espera repartido a partes iguales; con ella (los cortes del
## pergamino), alrededor del mismo sitio.
func _cortes(im: Image, caja: Rect2i, es_letra: Callable, guia: PackedFloat32Array) -> PackedFloat32Array:
	var perfil := PackedFloat32Array()
	perfil.resize(caja.size.x)
	for x in caja.size.x:
		var k := 0
		for y in caja.size.y:
			if es_letra.call(im.get_pixel(caja.position.x + x, caja.position.y + y)):
				k += 1
		perfil[x] = k
	var suave := PackedFloat32Array()
	suave.resize(caja.size.x)
	for x in caja.size.x:
		var s := 0.0
		var n := 0
		for d in range(-3, 4):
			if x + d >= 0 and x + d < caja.size.x:
				s += perfil[x + d]
				n += 1
		suave[x] = s / n
	var sale := PackedFloat32Array([0.0])
	for k in range(1, LETRAS_POR_LINEA):
		var espera := guia[k] if guia.size() > k else float(k) / LETRAS_POR_LINEA
		var x0 := int((espera - VENTANA_CORTE) * caja.size.x)
		var x1 := int((espera + VENTANA_CORTE) * caja.size.x)
		var mejor := clampi(x0, 0, caja.size.x - 1)
		for x in range(maxi(x0, 0), mini(x1, caja.size.x)):
			if suave[x] < suave[mejor]:
				mejor = x
		sale.append(float(mejor) / caja.size.x)
	sale.append(1.0)
	return sale


## De la fracción `f` del destino a la del origen, lineal dentro del tramo (la letra) en que cae.
static func _tramo(f: float, destino: PackedFloat32Array, origen: PackedFloat32Array) -> float:
	for k in range(destino.size() - 1):
		if f <= destino[k + 1] or k == destino.size() - 2:
			var t := (f - destino[k]) / maxf(destino[k + 1] - destino[k], 1e-6)
			return lerpf(origen[k], origen[k + 1], t)
	return f


static func _bilineal(im: Image, x: float, y: float) -> Color:
	var x0 := clampi(floori(x), 0, im.get_width() - 1)
	var y0 := clampi(floori(y), 0, im.get_height() - 1)
	var x1 := mini(x0 + 1, im.get_width() - 1)
	var y1 := mini(y0 + 1, im.get_height() - 1)
	var fx := clampf(x - x0, 0.0, 1.0)
	var fy := clampf(y - y0, 0.0, 1.0)
	var arriba := im.get_pixel(x0, y0).lerp(im.get_pixel(x1, y0), fx)
	var abajo := im.get_pixel(x0, y1).lerp(im.get_pixel(x1, y1), fx)
	return arriba.lerp(abajo, fy)


## El recuadro liso del centro: desde el medio hacia cada lado, hasta el primer píxel claramente
## más oscuro que el pergamino de dentro (la línea fina que lo cierra).
func _recuadro(im: Image) -> void:
	var w := im.get_width()
	var h := im.get_height()
	var cx := w / 2
	var cy := h / 2
	var ref := im.get_pixel(cx, cy).get_luminance()
	var lados := {}
	for d in [["izquierda", Vector2i(-1, 0)], ["derecha", Vector2i(1, 0)],
			["arriba", Vector2i(0, -1)], ["abajo", Vector2i(0, 1)]]:
		var p := Vector2i(cx, cy)
		var paso: Vector2i = d[1]
		while p.x > 0 and p.x < w - 1 and p.y > 0 and p.y < h - 1:
			p += paso
			if im.get_pixel(p.x, p.y).get_luminance() < ref - 0.18:
				break
		lados[d[0]] = p.x if paso.x < 0 else (w - p.x if paso.x > 0 else (p.y if paso.y < 0 else h - p.y))
	print("recuadro liso: márgenes %s (de %d × %d)" % [lados, w, h])


func _guardar(im: Image, nombre: String) -> void:
	im.save_png(ProjectSettings.globalize_path(SALIDA + nombre))
	print("guardado %s (%d × %d)" % [nombre, im.get_width(), im.get_height()])

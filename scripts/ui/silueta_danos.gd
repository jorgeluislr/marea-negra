class_name SiluetaDanos
extends Control

## Silueta del barco TUMBADA (proa a la derecha, babor arriba) con cada zona teñida según su
## integridad: verde sana, amarillo algo tocada, rojo crítica.
##
## La forma es la flotación medida del propio casco (`EstiloHud.contorno`), así vale para los
## cuatro barcos. La integridad se lee de `Barco.integridad` cada frame; aquí no se guarda.
##
## Zonas: la proa es el primer cuarto de la eslora, la popa el último quinto, y el centro se parte
## en babor y estribor. El aparejo va como un disco donde se arbola el palo.

## Las cotas de las zonas son las del modelo de daños (`Barco.ZONA_PROA/POPA`), no unas propias:
## si el HUD cortara por otro sitio, un tiro a la «proa» se pintaría en el costado.
const PROA := Barco.ZONA_PROA
const POPA := Barco.ZONA_POPA
## Azul de las vías de agua: el agua no es un estado de la madera, va aparte del semáforo.
const AZUL_AGUA := Color(0.16, 0.42, 0.78)

var barco: Node:
	set(v):
		barco = v
		_contorno = EstiloHud.contorno(v) if v != null else PackedVector2Array()
		queue_redraw()

var _contorno := PackedVector2Array()
var _ultimo := {}


func _ready() -> void:
	resized.connect(queue_redraw)


func color_de(zona: String) -> Color:
	var integ = barco.get("integridad") if barco != null else null
	var v := float((integ as Dictionary).get(zona, 1.0)) if integ is Dictionary else 1.0
	return EstiloHud.color_integridad(v)


## Cuántas vías de agua pinta la silueta en una zona: las que tiene el barco. Se pregunta al barco y
## no se cuenta aquí, igual que la integridad.
func vias_en(zona: String) -> int:
	return int(barco.call("vias_en", zona)) if barco != null and barco.has_method("vias_en") else 0


func _process(_delta: float) -> void:
	if barco == null:
		return
	var integ = barco.get("integridad")
	var estado := {}
	if integ is Dictionary:
		estado = (integ as Dictionary).duplicate()
	for z in ["proa", "babor", "estribor", "popa"]:
		estado["via_" + z] = vias_en(z)
	estado["agua"] = snappedf(float(barco.get("agua_embarcada")) if "agua_embarcada" in barco
		else 0.0, 0.01)
	if estado != _ultimo:
		_ultimo = estado
		queue_redraw()


func _draw() -> void:
	if _contorno.size() < 3:
		return
	var lo := INF
	var hi := -INF
	var semi := 0.0
	for p in _contorno:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
		semi = maxf(semi, absf(p.x))
	var zc := (lo + hi) * 0.5
	var s := minf(size.x * 0.92 / (hi - lo), size.y * 0.8 / (semi * 2.0))
	var c := size * 0.5
	var a_pantalla := func(p: Vector2) -> Vector2: return c + Vector2(-(p.y - zc), p.x) * s
	var z_proa := lerpf(lo, hi, PROA)
	var z_popa := lerpf(lo, hi, 1.0 - POPA)
	var zonas := {
		"proa": _trozo(lo, z_proa, 0), "popa": _trozo(z_popa, hi, 0),
		"babor": _trozo(z_proa, z_popa, -1), "estribor": _trozo(z_proa, z_popa, 1)}
	for z in zonas:
		var pts := PackedVector2Array()
		for p in zonas[z]:
			pts.append(a_pantalla.call(p))
		if pts.size() >= 3:
			draw_colored_polygon(pts, color_de(z))
	var borde := PackedVector2Array()
	for p in _contorno:
		borde.append(a_pantalla.call(p))
	borde.append(borde[0])
	draw_polyline(borde, EstiloHud.TINTA, 2.0, true)
	draw_line(a_pantalla.call(Vector2(0, z_proa)), a_pantalla.call(Vector2(0, z_popa)),
		EstiloHud.TINTA, 1.0, true)
	for zz in [z_proa, z_popa]:
		var w := _semi_en(zz)
		draw_line(a_pantalla.call(Vector2(-w, zz)), a_pantalla.call(Vector2(w, zz)),
			EstiloHud.TINTA, 1.0, true)
	# Una gota por vía de agua, en el centro de su zona, y el agua embarcada como una barra bajo la
	# silueta: es lo que dice cuánto le queda al barco.
	var centros := {"proa": Vector2(0, lerpf(lo, z_proa, 0.55)),
		"popa": Vector2(0, lerpf(z_popa, hi, 0.45)),
		"babor": Vector2(-semi * 0.5, (z_proa + z_popa) * 0.5),
		"estribor": Vector2(semi * 0.5, (z_proa + z_popa) * 0.5)}
	for z in centros:
		var n := vias_en(z)
		for k in mini(n, 3):
			var p: Vector2 = a_pantalla.call(centros[z]) + Vector2(float(k) * 9.0 - float(mini(n, 3) - 1) * 4.5, 0)
			_gota(p, 5.0)
	var agua := float(_ultimo.get("agua", 0.0))
	if agua > 0.0:
		var ancho := size.x * 0.7
		var r := Rect2(Vector2((size.x - ancho) * 0.5, size.y - 7.0), Vector2(ancho, 5.0))
		draw_rect(r, EstiloHud.PERGAMINO_OSCURO)
		draw_rect(Rect2(r.position, Vector2(ancho * agua, 5.0)), AZUL_AGUA)
	var palo: Vector2 = a_pantalla.call(Vector2(0, lerpf(lo, hi, 0.4)))
	draw_circle(palo, semi * s * 0.45, EstiloHud.TINTA)
	draw_circle(palo, semi * s * 0.35, color_de("aparejo"))


## El trozo del contorno entre dos z: lado −1 (babor), +1 (estribor) o 0 (las dos bandas).
func _trozo(z0: float, z1: float, lado: int) -> PackedVector2Array:
	var der := PackedVector2Array()
	var izq := PackedVector2Array()
	for p in _contorno:
		if p.y < z0 or p.y > z1:
			continue
		if p.x >= 0.0:
			der.append(p)
		else:
			izq.append(p)
	var orden := func(a: Vector2, b: Vector2) -> bool: return a.y < b.y
	var d := Array(der)
	d.sort_custom(orden)
	var i := Array(izq)
	i.sort_custom(orden)
	i.reverse()
	var w0 := _semi_en(z0)
	var w1 := _semi_en(z1)
	var sale := PackedVector2Array()
	if lado > 0:
		sale.append(Vector2(0.0, z0))
	if lado >= 0:
		sale.append(Vector2(w0, z0))
		for p in d:
			sale.append(p)
		sale.append(Vector2(w1, z1))
	if lado > 0:
		sale.append(Vector2(0.0, z1))
	if lado < 0:
		sale.append(Vector2(0.0, z1))
	if lado <= 0:
		sale.append(Vector2(-w1, z1))
		for p in i:
			sale.append(p)
		sale.append(Vector2(-w0, z0))
	if lado < 0:
		sale.append(Vector2(0.0, z0))
	return sale


## Medio ancho del contorno a una z, interpolando entre los dos puntos de estribor que la rodean.
func _semi_en(z: float) -> float:
	var mejor_a := Vector2(0, -INF)
	var mejor_b := Vector2(0, INF)
	for p in _contorno:
		if p.x < 0.0:
			continue
		if p.y <= z and p.y > mejor_a.y:
			mejor_a = p
		if p.y >= z and p.y < mejor_b.y:
			mejor_b = p
	if is_inf(mejor_a.y):
		return mejor_b.x
	if is_inf(mejor_b.y) or mejor_b.y == mejor_a.y:
		return mejor_a.x
	return lerpf(mejor_a.x, mejor_b.x, (z - mejor_a.y) / (mejor_b.y - mejor_a.y))


func _gota(c: Vector2, r: float) -> void:
	draw_circle(c + Vector2(0, r * 0.3), r, AZUL_AGUA)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.85, 0), c + Vector2(0, -r * 1.6),
		c + Vector2(r * 0.85, 0)]), AZUL_AGUA)
	draw_arc(c + Vector2(0, r * 0.3), r, 0.0, PI, 12, EstiloHud.TINTA, 1.0, true)

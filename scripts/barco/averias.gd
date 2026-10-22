class_name Averias
extends Node

## Lo que una bala le hace a un barco: en qué zona pega, cuánto la rompe, si abre vía de agua, y el
## agua que entra y que las bombas sacan hasta que el barco se va a pique.
##
## Va en un nodo aparte y no dentro de `Barco` por lo mismo que `Canon` o `TelaFisica`: tiene estado
## propio (las vías abiertas, el agua, los agujeros) y un reloj (el achique), y el casco ya hace
## bastante. El barco sigue siendo la ÚNICA fuente de lo que se ve: `Barco.integridad` es lo que
## pinta el HUD, y esto solo escribe ahí.
##
## **Las zonas son las cinco del icono de daños del HUD** (decisión del usuario, 18-10-2026): proa,
## babor, estribor, popa y aparejo. La proa es el primer cuarto de la eslora en la flotación, la
## popa el último quinto, y el centro se parte por crujía (`Barco.ZONA_PROA`, `ZONA_POPA`). Las
## cotas salen de la flotación MEDIDA del casco (`silueta_de_flotacion`), así que valen para
## cualquier barco sin un número escrito a mano.
##
## **El daño va por balas**: cada impacto resta lo que diga su `Municion` en esa zona.
##
## **Una vía de agua** se abre cuando la bala entra por la flotación —hasta `franja_flotacion` por
## encima de la lámina, porque el balance la mete en el agua a cada bandazo— o cuando la zona ya está
## destrozada y no queda tablazón que pare nada. El agua se mide como fracción de la reserva de
## flotabilidad: con la reserva llena el barco se hunde.

signal hundido_ya

## Agujeros como mucho por barco: cada uno es un `Decal`, y una pelea larga son cientos de balas.
const AGUJEROS_MAX := 40

var barco: Node3D
## Fracción de la reserva de flotabilidad embarcada, de 0 (seco) a 1 (a pique).
var agua := 0.0
var hundido := false
## Una entrada por vía abierta, con la zona donde está.
var vias: Array[String] = []
## Metros que lleva hundiéndose desde que se fue a pique.
var _bajada := 0.0
var _agujeros: Array[Node] = []

static var _textura_agujero: GradientTexture2D


func vias_en(zona: String) -> int:
	return vias.count(zona)


func reparar() -> void:
	for z in barco.integridad:
		barco.integridad[z] = 1.0
	vias.clear()
	agua = 0.0
	hundido = false
	_bajada = 0.0
	for a in _agujeros:
		if is_instance_valid(a):
			a.queue_free()
	_agujeros.clear()


## La zona que toca una bala. `cuerpo` es el colisionador que devolvió el rayo: una vela
## (`SoftBody3D`), un palo o un cabo (sus capas de `PerchasSolidas`) son el aparejo; todo lo demás
## es casco y se reparte por DÓNDE pegó.
func zona_de(donde: Vector3, cuerpo: Object) -> String:
	if cuerpo is SoftBody3D:
		return "aparejo"
	if cuerpo is CollisionObject3D and cuerpo != barco:
		var capa := (cuerpo as CollisionObject3D).collision_layer
		if capa & Barco.CAPA_DIANAS == 0 and capa & (16 | 32 | 64) != 0:
			return "aparejo"
	return zona_de_casco(barco.to_local(donde))


## La zona del casco de un punto en ejes del barco. La proa mira a −Z y estribor es +X.
func zona_de_casco(p: Vector3) -> String:
	var s: Dictionary = barco.call("silueta_de_flotacion")
	var lo := -1.0
	var hi := 1.0
	if s.is_empty():
		var r: Vector2 = barco.get("recorte_radio")
		lo = -r.y
		hi = r.y
	else:
		lo = float(s["lo"])
		hi = float(s["hi"])
	var f := (p.z - lo) / maxf(hi - lo, 0.01)
	if f < Barco.ZONA_PROA:
		return "proa"
	if f > 1.0 - Barco.ZONA_POPA:
		return "popa"
	return "estribor" if p.x >= 0.0 else "babor"


func recibir(donde: Vector3, bala: Node) -> void:
	if hundido:
		return
	var m: Municion = bala.call("tipo") if bala != null and bala.has_method("tipo") \
		else Municion.de("rasa")
	var g: Dictionary = bala.get("golpe") if bala != null and bala.get("golpe") is Dictionary else {}
	var cuerpo: Object = g.get("collider")
	var normal: Vector3 = g.get("normal", Vector3.UP)
	var zona := zona_de(donde, cuerpo)
	var integ: Dictionary = barco.integridad
	if zona == "aparejo":
		integ["aparejo"] = maxf(float(integ["aparejo"]) - m.dano_aparejo, 0.0)
		# La lona no salta astillas; un palo o una percha sí.
		if not cuerpo is SoftBody3D:
			_astillas(donde, normal, 0.6)
		return
	var destrozada := float(integ[zona]) <= 0.0
	integ[zona] = maxf(float(integ[zona]) - m.dano_casco, 0.0)
	if m.dano_casco <= 0.0:
		return
	if m.abre_via and (_en_la_flotacion(donde) or destrozada):
		vias.append(zona)
	_astillas(donde, normal, 1.0)
	_agujero(donde, normal, m.radio)


func _en_la_flotacion(donde: Vector3) -> bool:
	var mar: float = Bala.superficie(donde.x, donde.z, barco.call("_altura_del_mar"))
	return donde.y <= mar + float(barco.get("franja_flotacion"))


## Metros que el agua embarcada hunde el casco por debajo de su flotación.
func calado_extra() -> float:
	return float(barco.get("calado_inundado")) * agua + _bajada


func _physics_process(delta: float) -> void:
	if barco == null:
		return
	if hundido:
		# A pique: se va al fondo a medio metro por segundo hasta que no asoma ni la perilla.
		_bajada = minf(_bajada + 0.5 * delta, float(barco.get("_alto")) + 4.0)
		return
	var entra := float(vias.size()) * float(barco.get("caudal_via"))
	agua = clampf(agua + (entra - float(barco.get("achique"))) * delta, 0.0, 1.0)
	if agua >= 1.0:
		hundido = true
		hundido_ya.emit()
		print("%s: se va a pique" % barco.get("nombre"))


func _astillas(donde: Vector3, normal: Vector3, cuanto: float) -> void:
	var a := Astillas.new()
	a.name = "Astillas"
	a.normal = normal
	a.cuantas = int(14 * cuanto)
	var raiz := barco.get_tree().current_scene
	if raiz == null:
		raiz = barco.get_tree().root
	raiz.add_child(a)
	a.global_position = donde


## Un agujero oscuro donde entró la bala. Es un `Decal` colgado del BARCO, así que navega, cabecea y
## escora con él; se proyecta a lo largo de la normal de la cara que tocó, con poca profundidad para
## no pintar las tablas de la otra banda. El mar no lo recibe: es transparente, y los decals solo
## pintan lo opaco.
func _agujero(donde: Vector3, normal: Vector3, radio_bala: float) -> void:
	var d := Decal.new()
	d.name = "Agujero"
	var lado := 2.6 * radio_bala * 2.0 + 0.05
	d.size = Vector3(lado, 0.16, lado)
	d.texture_albedo = _textura()
	d.upper_fade = 0.0
	d.lower_fade = 0.0
	barco.add_child(d)
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var x := n.cross(Vector3.UP)
	if x.length() < 0.01:
		x = n.cross(Vector3.RIGHT)
	x = x.normalized()
	d.global_transform = Transform3D(Basis(x, n, x.cross(n)), donde)
	_agujeros.append(d)
	while _agujeros.size() > AGUJEROS_MAX:
		var viejo: Node = _agujeros.pop_front()
		if is_instance_valid(viejo):
			viejo.queue_free()


## El agujero: negro en el centro, madera rota alrededor y borde que se funde con el forro.
static func _textura() -> GradientTexture2D:
	if _textura_agujero != null:
		return _textura_agujero
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.32, 0.45, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.015, 0.01, 1.0), Color(0.03, 0.02, 0.015, 1.0),
		Color(0.30, 0.20, 0.11, 0.95), Color(0.18, 0.12, 0.07, 0.45), Color(0.1, 0.07, 0.04, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_textura_agujero = t
	return t

class_name Carga
extends Resource

## Un bulto colocado en un barco: qué modelo, dónde va y cómo se apoya.
##
## Existe porque la carga NO debe estar dentro del modelo del casco. Hasta ahora los tres
## barriles y las tres cajas de la balandra venían soldados en `balandra.glb`: no se podían
## mover, ni quitar, ni reutilizar en otro barco, ni recogerlos algún día. Ahora cada bulto es
## un `.glb` propio en `assets/models/` y esto describe dónde se pone.
##
## Es un recurso y no un nodo por la misma razón que `Aparejo`: es DATO, no comportamiento.
## Un barco lleva una lista y `Barco` los instancia al arrancar; se pueden editar en el
## inspector o declarar en la subclase del barco (que es lo que hace `Balandra`).
##
## El modelo se guarda como RUTA y se carga con `load()` al montar, no con `preload`: con un
## preload, los cuatro barcos de la flota traerían todos los bultos a memoria desde el arranque
## aunque no se instancie ninguno. Es el mismo criterio que `Barco.ruta_jugador`.

## Ruta a un `.glb` cuyo origen esté en el CENTRO de su caja envolvente, que es la convención
## de la biblioteca de piezas. Si el origen está en la base, el bulto saldrá medio hundido.
@export_file("*.glb", "*.tscn") var modelo := ""

## Posición respecto al barco, en metros. Es la del CENTRO del bulto, no la de su base.
@export var posicion := Vector3.ZERO

## Grados sobre el eje Y. Solo Y a propósito: un bulto estibado se gira para que encaje, no
## se vuelca. Los seis de la balandra están medidos y todos giran solo en Y (55°, 152°, 12°,
## 105°, 63° y 128°). Si algún día hace falta un barril tumbado, esto pasa a Vector3.
@export_range(-180.0, 180.0) var giro := 0.0

## Multiplica el tamaño del modelo. En la balandra los barriles van a 0,768 y 0,522.
@export_range(0.05, 4.0) var escala := 1.0

## Levanta un colisionador de caja del tamaño del bulto, para que el jugador no lo atraviese
## al andar por cubierta. Se apaga para lo puramente decorativo o lo que quede fuera de paso.
@export var solido := true

## Nombre del nodo, para reconocerlo en el árbol al depurar. Si se deja vacío se toma del
## fichero del modelo.
@export var nombre := ""


## Instancia el bulto listo para colgar del barco. Devuelve null y avisa si el modelo falta,
## en vez de reventar: un barco al que le falte un `.glb` de carga debe seguir navegando.
func instanciar(capa_colision := 0) -> Node3D:
	if modelo == "":
		return null
	if not ResourceLoader.exists(modelo):
		push_warning("Carga: no existe el modelo '%s'" % modelo)
		return null
	var escena := load(modelo) as PackedScene
	if escena == null:
		push_warning("Carga: '%s' no es una escena instanciable" % modelo)
		return null
	var raiz := escena.instantiate() as Node3D
	if raiz == null:
		push_warning("Carga: '%s' no tiene raíz Node3D" % modelo)
		return null
	raiz.name = nombre if nombre != "" else modelo.get_file().get_basename()
	raiz.transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(giro)).scaled(Vector3.ONE * escala), posicion)
	if solido:
		_dar_cuerpo(raiz, capa_colision)
	return raiz


## Colisionador de caja ajustado a la geometría del bulto.
##
## Se mide con el AABB de las mallas y no con un tamaño a mano porque el mismo bulto se usa a
## varias escalas: la caja tiene que seguir al modelo, no repetir su medida en dos sitios.
## El `StaticBody3D` va DENTRO del bulto y sin la escala aplicada, así que la forma se mide en
## el espacio del modelo y la escala del nodo padre hace el resto.
func _dar_cuerpo(raiz: Node3D, capa: int) -> void:
	var caja := AABB()
	var primera := true
	for m in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := _relativo(mi, raiz) * mi.mesh.get_aabb()
		if primera:
			caja = a
			primera = false
		else:
			caja = caja.merge(a)
	if primera or caja.size.length() < 0.001:
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Colision"
	if capa != 0:
		cuerpo.collision_layer = capa
	var forma := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = caja.size
	forma.shape = bs
	forma.position = caja.get_center()
	cuerpo.add_child(forma)
	raiz.add_child(cuerpo)


## Transform de `n` respecto a `raiz`. Mismo criterio que `Barco._relativo`: se compone a mano
## en vez de usar `global_transform`, que aún no vale porque el nodo no está en el árbol.
func _relativo(n: Node3D, raiz: Node3D) -> Transform3D:
	var t := Transform3D()
	var x: Node = n
	while x != null and x != raiz:
		if x is Node3D:
			t = (x as Node3D).transform * t
		x = x.get_parent()
	return t

class_name AcabadoMadera
extends Resource

## Devuelve a la madera el relieve fino que el `.glb` no puede transportar.
##
## EL PROBLEMA. En Blender el relieve de la madera del barco no es una textura: es el grupo de
## nodos `RELIEVE_MADERA`, un **triplanar procedural** que proyecta `rough_wood_nor_gl_2k` tres
## veces por coordenadas de objeto, a escala 14, con ruido y bump encima. Tiene detalle
## ilimitado porque se calcula, no se muestrea de un atlas. Y **nada de eso viaja en glTF**, que
## solo transporta una imagen por canal: el `.glb` sale con el color correcto y la madera lisa.
##
## Y no se arregla horneando. Medido: el atlas de `madera_percha_h` reparte 2048² entre 21
## objetos que suman 16,4 m² y da **0,22 px/mm** (un píxel cada 4,5 mm); el casco, 106,5 m² con
## otro 2048², da **0,059 px/mm**, un píxel cada 17 mm. Para llegar a 1 px/mm el atlas de las
## perchas tendría que ser 8192² y el del casco 32768², que no es viable. La referencia de lo
## que se ve bien: la caja de la biblioteca está en 1,034 px/mm.
##
## LA SOLUCIÓN. Godot hace triplanar de serie, así que se reproduce lo de Blender sin hornear y
## sin necesitar una capa de UV nueva —el triplanar no usa UV—:
##
##   · el COLOR sigue saliendo del atlas horneado por UV1, que es lo que debe ser único de cada
##     pieza (el casco tiene partes de distinto tono y no puede repetirse);
##   · el RELIEVE se añade como capa de DETALLE con la textura repetida, proyectada en triplanar
##     por UV2, que a 1 repetición por metro da del orden de 2 px/mm en cualquier pieza,
##     independientemente de su tamaño.
##
## Es un recurso porque es DATO —qué textura, a qué escala, sobre qué materiales—, y quien lo
## aplica es el barco. Mismo criterio que `Aparejo` y `Carga`.

static var _blanco_cache: Texture2D = null

## Mapa de normales que se repite. Va en espacio tangente y NO debe importarse como sRGB.
@export_file("*.png", "*.jpg", "*.webp") var relieve := "res://assets/textures/madera_relieve_nor.jpg"

## Repeticiones por metro. En Blender el grupo usa escala 14 sobre coordenadas de objeto, que
## para un casco de 12 m son ~1,2 repeticiones por metro.
@export_range(0.1, 20.0) var repeticiones := 1.2

## Fuerza del relieve. Por encima de 2 la madera empieza a parecer piedra.
@export_range(0.0, 4.0) var fuerza := 1.0

## Gira la fibra 90°. El triplanar proyecta la MISMA textura en los tres planos, y la veta de
## `rough_wood` corre a lo largo de V (medido: recorriendo Y la imagen varía 0,0111 y
## recorriendo X 0,0132, y el canal R tiene el doble de desviación que el G, que es la firma de
## unas líneas verticales). En la cara superior Godot mapea U=x y V=z, así que la fibra sale a
## lo largo de la eslora; en el tablado de cubierta eso se ve cruzado respecto a las tablas.
@export var girar_fibra := false

## Materiales a los que se aplica, por nombre. Se enumeran en vez de aplicarlo a todo porque el
## relieve de madera no le sirve a un cabo, a un herraje ni a la lona de una vela.
@export var materiales: PackedStringArray = PackedStringArray([
	"mat_horneado_C",         # el casco
	"madera_percha_h",        # palos, perchas, vigotas, mesas, soportes
	"madera_botalon",
	"madera_timon",
	"madera_palos_h_bake",
	"cubierta_tablazon_bake",
])


## Aplica el acabado a los materiales de madera que encuentre bajo `raiz`.
##
## Modifica el material EN SITIO y no una copia: los materiales de un `.glb` son un recurso
## compartido, así que tocarlo una vez vale para todas las mallas que lo usan y para todas las
## instancias del barco. Es lo que se quiere aquí —el acabado es del material, no de la
## instancia— y además evita duplicar 15 materiales por barco.
func aplicar(raiz: Node) -> Dictionary:
	if relieve == "" or not ResourceLoader.exists(relieve):
		push_warning("AcabadoMadera: no existe la textura '%s'" % relieve)
		return {}
	var tex := load(relieve) as Texture2D
	if tex == null:
		return {}
	if girar_fibra:
		tex = _girada(tex)
	var hechos := {}
	var vistos := {}
	for m in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if mat == null or not materiales.has(mat.resource_name):
				continue
			if vistos.has(mat.get_instance_id()):
				hechos[mat.resource_name] = int(hechos.get(mat.resource_name, 0)) + 1
				continue
			vistos[mat.get_instance_id()] = true
			_poner(mat, tex)
			hechos[mat.resource_name] = int(hechos.get(mat.resource_name, 0)) + 1
	return hechos


func _poner(mat: BaseMaterial3D, tex: Texture2D) -> void:
	# El detalle va por UV2 en TRIPLANAR: sin UV, proyectado por las tres caras. Es lo que hace
	# el grupo de Blender con TEX_COORD, y lo que permite el mismo detalle en el casco de 12 m
	# que en una vigota de 4 cm.
	mat.uv2_triplanar = true
	mat.uv2_world_triplanar = false          # en espacio de OBJETO: se mueve con el barco
	mat.uv2_scale = Vector3.ONE * repeticiones
	mat.detail_enabled = true
	mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	mat.detail_normal = tex
	# El detalle mezcla albedo Y normal a la vez, y NO se puede dejar el albedo sin poner: sin
	# él Godot mezcla contra un color indefinido y el resultado sale sucio (medido: el contraste
	# de la imagen BAJABA un 30 %). Se le da un blanco opaco y modo MULTIPLICAR, que deja el
	# color del atlas exactamente como estaba y aprovecha solo la normal.
	mat.detail_albedo = _blanco()
	mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	mat.normal_enabled = true
	mat.normal_scale = fuerza


## La textura girada un cuarto de vuelta.
##
## OJO: en un MAPA DE NORMALES no basta con rotar los píxeles. Cada píxel codifica una pendiente
## (R el componente X, G el Y, con 0,5 = plano), así que al girar la imagen hay que girar
## también el vector, o el relieve queda iluminado desde donde no es y se ven los surcos
## invertidos —hundidos donde deberían sobresalir—. Para un cuarto de vuelta: R' = 1 − G y
## G' = R.
static func _girada(tex: Texture2D) -> Texture2D:
	var img := tex.get_image()
	if img == null:
		return tex
	img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.rotate_90(CLOCKWISE)
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(1.0 - c.g, c.r, c.b))
	return ImageTexture.create_from_image(img)


## Un píxel blanco opaco, para que el albedo de detalle no altere el color al multiplicar.
static func _blanco() -> Texture2D:
	if _blanco_cache == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_blanco_cache = ImageTexture.create_from_image(img)
	return _blanco_cache

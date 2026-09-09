class_name Balandra
extends Barco

## Balandra: cangreja (mayor con pico) + foque, aparejo de proa a popa, y bandera.
##
## Lo que la distingue del resto de la flota vive aquí, no repartido por la escena:
## es el único casco de la flota por el que se anda hoy, así que es la que declara sus
## mallas de cubierta y de casco para que `Barco` levante los colisionadores.
##
## Se declara en código y no como valores guardados en `balandra.tscn` porque es
## conocimiento del TIPO de barco, no un ajuste de esta instancia: cualquier balandra
## que se instancie tiene estas mallas se coloque donde se coloque.
##
## Va en `_ready` y no en `_init`: `balandra.tscn` HEREDA de `barco_base.tscn`, así que
## Godot construye el nodo con el script de la base y le cambia el script después — y
## cambiar el script de un objeto ya construido no vuelve a llamar a `_init`.

const MODELO_BARRIL := "res://assets/models/barril.glb"
const MODELO_CAJA := "res://assets/models/caja.glb"


func _ready() -> void:
	# `cubierta_min` es el panel central (9 m de los 12); `bodega`, el suelo de abajo.
	# Las cubiertas de proa y popa son del propio casco, a otra altura, y `Barco` las
	# deduce muestreándolo.
	colision_casco = "casco_lod0"
	colision_mallas_suelo = ["cubierta_min", "bodega"]
	# Si la instancia trae su propia carga puesta en el inspector, se respeta.
	if cargamento.is_empty():
		cargamento = _carga_de_salida()
	# El relieve de la madera: en Blender lo hace un grupo de nodos que glTF no exporta, así que
	# hay que reponerlo aquí. Sin esto el casco sale a 0,059 px/mm, un píxel cada 17 mm.
	if acabado_madera.is_empty():
		acabado_madera = _acabados_de_madera()
	super()


## El relieve de la madera, en dos grupos: la fibra no va en el mismo sentido en todas partes.
##
## El triplanar proyecta la misma textura en los tres planos, así que la veta cae siempre en la
## misma dirección del mundo. En los palos y las perchas queda bien; en el TABLADO de cubierta y
## en el forro del casco se ve cruzada respecto a las tablas, así que esas dos llevan la fibra
## girada un cuarto de vuelta.
func _acabados_de_madera() -> Array[AcabadoMadera]:
	var palos := AcabadoMadera.new()
	palos.materiales = PackedStringArray([
		"madera_percha_h", "madera_botalon", "madera_timon", "madera_palos_h_bake"])
	var tablas := AcabadoMadera.new()
	tablas.materiales = PackedStringArray(["mat_horneado_C", "cubierta_tablazon_bake"])
	tablas.girar_fibra = true
	return [palos, tablas]


## La estiba con la que sale la balandra: tres barriles y tres cajas en cubierta.
##
## Estos seis bultos venían soldados dentro de `balandra.glb` hasta el 7 de septiembre de 2026.
## Las cifras NO están puestas a ojo: son las de aquel modelo, medidas leyendo la caja
## envolvente de cada malla y pasándolas al espacio del barco por la basis del nodo `Modelo`.
##
## Esa basis es **X→(0,0,1), Y→(0,1,0), Z→(−1,0,0)**, y hay que MEDIRLA EN EL JUEGO
## (`tools/donde_esta_la_proa.tscn`), no leerla del `.tscn`: interpretándola a ojo del texto
## salió la transpuesta, y con ella los seis bultos aparecieron girados 180° y en la punta
## contraria del barco — los barriles a proa y las cajas a popa. Lo que confirma la buena es
## que el **botalón cae en Z negativo**, que es donde tiene que estar la proa.
##
## Los giros salen redondos y solo en Y (−125°, −28°, −168°, −75°, −117° y −52°); con la matriz
## mal compuesta habrían salido ángulos arbitrarios en los tres ejes.
##
## La Y es la del CENTRO del bulto, que es donde `Carga` lo coloca, no la de su base.
func _carga_de_salida() -> Array[Carga]:
	return [
		_bulto(MODELO_BARRIL, Vector3(-0.760, 2.090, 4.478), -125.0, 0.768, "barril_popa_estribor"),
		_bulto(MODELO_BARRIL, Vector3(1.050, 1.978, 3.181), -28.0, 0.768, "barril_popa_babor"),
		_bulto(MODELO_BARRIL, Vector3(0.956, 1.986, 3.906), -168.0, 0.522, "barril_pequeno"),
		_bulto(MODELO_CAJA, Vector3(-0.850, 1.938, -1.620), -75.0, 1.0, "caja_proa"),
		_bulto(MODELO_CAJA, Vector3(-1.180, 1.938, 0.500), -117.0, 1.0, "caja_media"),
		_bulto(MODELO_CAJA, Vector3(1.146, 1.938, 1.050), -52.0, 1.0, "caja_babor"),
	]


func _bulto(ruta: String, pos: Vector3, giro: float, escala: float, nom: String) -> Carga:
	var c := Carga.new()
	c.modelo = ruta
	c.posicion = pos
	c.giro = giro
	c.escala = escala
	c.nombre = nom
	return c

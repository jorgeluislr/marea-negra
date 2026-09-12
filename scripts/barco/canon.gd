class_name Canon
extends Node3D

## Una pieza de artillería montada en un barco: sabe a qué banda tira, dónde tiene la boca
## y cuándo puede volver a disparar.
##
## Es un NODO y no un recurso —al revés que `Carga` o `Aparejo`— porque tiene COMPORTAMIENTO
## y estado propio: la recarga corre para cada pieza por separado. `Artilleria` es el dato
## (dónde va cada una) y esto es lo que actúa, igual que `Aparejo` describe una driza y es la
## vela quien la mueve.
##
## En esta balandra el montaje es **a barbeta**: la regala solo levanta 0,41 m sobre la
## cubierta y no hay obra muerta para abrir portas, así que el ánima pasa por encima de la
## borda. Se midió antes de colocarlo (ver `Balandra._artilleria_de_salida`).

signal disparo(desde: Vector3, hacia: Vector3)
## Lo reemite la bala que salió de esta pieza, para que el barco y las pruebas no
## tengan que perseguir el proyectil por el árbol.
signal impacto(donde: Vector3, contra: Node)

## Geometría del modelo, medida sobre `canon.glb` y no puesta a ojo. Es una pieza de **a 3
## libras** (calibre 76 mm): 1,859 × 0,624 × 0,715 m, con el origen en el CENTRO de su caja
## (convención de la biblioteca), el ánima a 0,513 m del suelo de las ruedas y la boca en el
## extremo −X, que es hacia donde apunta.
##
## Se bajó de a 4 libras (84 mm, 2,055 m) el 12 de septiembre de 2026: el a 4 es la medida real
## de esa pieza, pero nuestro modelo tiene 24,5 calibres de esbeltez —un cañón LARGO— y las
## embarcaciones menores montaban piezas cortas, de 18-20, justamente para que cupieran. Con
## una manga de 3,95 m sobre 12 de eslora (3,04:1, cuando lo normal en balandras era 2,5-2,8)
## cualquier pieza va justa en esta cubierta.
const LARGO := 1.8593
const ALTO := 0.7149
const EJE_ANIMA_SOBRE_SUELO := 0.513
## Radio exterior del tubo donde cruza la borda (las fajas son lo más gordo). Importa porque
## lo que topa con la regala NO es el eje del ánima sino la generatriz de abajo, 10,7 cm más
## baja: con el eje pasando limpio, el tubo puede estar metido en la tabla.
const RADIO_TUBO := 0.107
## Las cuatro ruedas en el espacio del MODELO, para comprobar que la cureña apoya entera.
const RUEDAS := [Vector3(-0.0926, 0.0, 0.2873), Vector3(-0.0926, 0.0, -0.2873),
	Vector3(0.6159, 0.0, 0.2873), Vector3(0.6159, 0.0, -0.2873)]
## 0,567 − 0,395 = 0,172: el ánima queda por encima del centro de la caja.
const EJE_ANIMA_SOBRE_CENTRO := EJE_ANIMA_SOBRE_SUELO - ALTO * 0.5
const BOCA_LOCAL := Vector3(-LARGO * 0.5, EJE_ANIMA_SOBRE_CENTRO, 0.0)

@export_file("*.glb", "*.tscn") var modelo := "res://assets/models/canon.glb"
## +1 tira a estribor (+X del barco), −1 a babor. La proa mira a −Z, así que estribor es +X.
@export var lado := 1.0
@export var recarga := 5.0        ## Segundos entre disparos de la misma pieza.
## m/s en la boca. **Es una concesión al juego, no un dato**: un cañón de a 3 real daba 350-400
## y con eso tira a kilómetros —a 220 m/s un solo grado de cuña ya lleva la bala a 270 m—, así
## que la elevación dejaría de servir como control.
##
## Alcance MEDIDO con `tools/alcance_real.tscn` sobre la balandra, con el ánima a 1,592 m sobre
## el agua (mar en −0,882, boca a 0,710):
##
##     cuña   0° →  62,7 m        cuña   6° →  271,9 m
##     cuña   2° → 119,6 m        cuña   8° →  352,2 m
##     cuña   4° → 193,0 m        cuña  12° →  510,5 m
##
## Los números anteriores de este comentario (66 / 172 / 340 / 500) estaban CALCULADOS a mano
## suponiendo el ánima a 1,77 m, y esa altura no era la de la pieza montada sobre su dormido.
@export var velocidad_bala := 110.0
## Grados de elevación del tubo, los que daba la CUÑA de puntería metida bajo la culata.
##
## Desde el 11 de septiembre de 2026 mueve SOLO EL TUBO: el `.glb` trae la cureña y el tubo
## como dos objetos, con el tubo pivotando en el eje de los muñones. Antes, con el cañón de una
## pieza, la elevación giraba también la cureña y dejaba 4,9 cm de desnivel entre ruedas sobre
## 0,708 m de batalla — dos enterradas en el dormido y dos al aire.
@export_range(-3.0, 12.0) var elevacion := 0.0:
	set(v):
		elevacion = v
		_aplicar_punteria()
## Grados de giro lateral de la pieza entera sobre la cubierta, que es lo que se hacía con los
## espeques. Aquí sí gira la cureña con el tubo, porque es lo que pasaba de verdad.
@export_range(-15.0, 15.0) var giro_lateral := 0.0:
	set(v):
		giro_lateral = v
		_aplicar_punteria()
## Altura de la lámina de agua, que es donde cae el tiro. La pone el barco al montar la pieza.
@export var altura_mar := 0.0
@export var escena_bala: PackedScene
## Dormido: la plataforma sobre la que se monta la cureña. Sube el ánima para que el tubo pase
## por encima de la regala, que en esta balandra es alta para una pieza de a 3 libras — con la
## cureña directamente sobre la cubierta el tubo entra 2,9 cm en la madera a popa. Es además el
## montaje histórico de la artillería a barbeta. Con 0 no se monta ninguno.
@export var altura_dormido := 0.08

var _espera := 0.0


var _modelo: Node3D
var _tubo: Node3D
var _curena: Node3D
var _reposo_tubo := Basis.IDENTITY


func _ready() -> void:
	_montar_modelo()


func _process(delta: float) -> void:
	if _espera > 0.0:
		_espera = maxf(_espera - delta, 0.0)


## "babor" o "estribor". En texto y no como número porque es lo que se lee en el HUD y en las
## pruebas, y porque un signo suelto no dice de qué banda habla.
func banda() -> String:
	return "estribor" if lado > 0.0 else "babor"


## Dónde está la boca del ánima, en el mundo. Es de donde sale la bala y por donde se comprueba
## que la pieza no está apuntando a su propia madera.
func boca_global() -> Vector3:
	if _tubo != null:
		# En el espacio del TUBO la boca está a su largo del eje de muñones, no a media caja.
		return _tubo.global_transform * Vector3(-(LARGO * 0.5 + EJE_MUNON.x), 0.0, 0.0)
	return global_transform * BOCA_LOCAL


## Hacia dónde tira: el eje del TUBO, que es quien lleva la elevación. Así la línea de la guía
## sale del mismo sitio que apunta el bronce y no pueden discrepar.
func direccion_global() -> Vector3:
	var base := _tubo if _tubo != null else (_modelo if _modelo != null else self)
	return -base.global_transform.basis.x.normalized()


## Velocidad con que sale la bala.
func velocidad_salida() -> Vector3:
	return direccion_global() * velocidad_bala


## Dónde caerá el tiro si nadie se interpone: la parábola cortada por la lámina de agua.
## Devuelve la propia boca si el tiro nunca baja (no puede pasar con elevaciones normales).
func punto_de_caida() -> Vector3:
	var p0 := boca_global()
	var v0 := velocidad_salida()
	var t := Bala.tiempo_hasta(p0, v0, altura_mar)
	if t <= 0.0:
		return p0
	return Bala.punto(p0, v0, t)


## La parábola muestreada, para dibujarla. Mismo cálculo que el vuelo de la bala.
func trayectoria(pasos := 24) -> PackedVector3Array:
	var p0 := boca_global()
	var v0 := velocidad_salida()
	var t_fin := Bala.tiempo_hasta(p0, v0, altura_mar)
	var puntos := PackedVector3Array()
	if t_fin <= 0.0:
		return puntos
	for i in pasos + 1:
		puntos.append(Bala.punto(p0, v0, t_fin * float(i) / float(pasos)))
	return puntos


func listo() -> bool:
	return _espera <= 0.0


## Dispara si ha terminado de recargar. Devuelve si llegó a salir el tiro, para que quien
## manda la andanada sepa cuántas piezas respondieron.
func disparar() -> bool:
	if not listo():
		return false
	_espera = recarga
	var desde := boca_global()
	var vel := velocidad_salida()
	var hacia := direccion_global()
	disparo.emit(desde, hacia)
	_soltar_bala(desde, vel)
	_encender_fogonazo(desde, hacia)
	_tronar(desde)
	return true


## El estampido. Va en la pieza y no en `audio_barco.gd` por lo mismo que el fogonazo: es un
## sonido DE LA PIEZA, sale de su boca y cada una tiene su propia recarga.
##
## Se cuelga del ÁRBOL, igual que el humo y por la misma razón: la cola dura 4,9 s y el barco
## navega a 9 m/s, así que colgada del cañón el retumbo recorrería 44 m pegado a la boca. Un
## estampido se queda donde se disparó.
##
## Tres tomas y se elige al azar sin repetir la anterior. Una andanada son cuatro piezas casi a
## la vez, y con un archivo único el oído caza la repetición exacta al instante: suena a
## ametralladora en vez de a batería. El tono también se mueve un poco — dos piezas iguales
## cargadas por manos distintas no suenan idénticas.
##
## Los `.wav` los genera `audio_src/sintetizar_canon.py`: un cañonazo es onda de choque más gas
## en expansión, o sea ruido filtrado, que es justo lo que este proyecto sí sintetiza.
const SONIDOS := ["res://assets/audio/canon_1.wav", "res://assets/audio/canon_2.wav",
	"res://assets/audio/canon_3.wav"]

## Distancia a la que el estampido ya ha caído a la mitad. 40 m y no los 9 del fogonazo: el
## destello es luz y el trueno se oye a millas.
@export var alcance_sonido := 40.0
@export var volumen_db := 0.0

static var _ultima_toma := -1


func _tronar(desde: Vector3) -> void:
	if SONIDOS.is_empty():
		return
	var i := randi() % SONIDOS.size()
	if SONIDOS.size() > 1 and i == _ultima_toma:
		i = (i + 1) % SONIDOS.size()
	_ultima_toma = i
	if not ResourceLoader.exists(SONIDOS[i]):
		return
	var a := AudioStreamPlayer3D.new()
	a.name = "Canonazo"
	a.stream = load(SONIDOS[i]) as AudioStream
	a.unit_size = alcance_sonido
	a.max_distance = alcance_sonido * 12.0
	a.volume_db = volumen_db
	a.pitch_scale = randf_range(0.94, 1.06)
	var raiz := get_tree().current_scene
	if raiz == null:
		raiz = get_tree().root
	raiz.add_child(a)
	a.global_position = desde
	# Se borra solo al terminar: si no, cada disparo deja un nodo muerto en la escena para
	# siempre, y una andanada son cuatro por salva.
	a.finished.connect(a.queue_free)
	a.play()


## El humo se cuelga del ÁRBOL y no del cañón: si colgara del barco viajaría con él y la
## humareda navegaría pegada a la boca en vez de quedarse donde se disparó.
func _encender_fogonazo(desde: Vector3, hacia: Vector3) -> void:
	var f := Fogonazo.new()
	f.name = "Fogonazo"
	var raiz := get_tree().current_scene
	if raiz == null:
		raiz = get_tree().root
	raiz.add_child(f)
	f.global_position = desde
	f.encender(hacia)


## La bala se cuelga del ÁRBOL, no del cañón: una vez fuera del ánima ya no pertenece al barco
## y no debe navegar con él.
func _soltar_bala(desde: Vector3, vel: Vector3) -> void:
	var b: Bala
	if escena_bala != null:
		b = escena_bala.instantiate() as Bala
	if b == null:
		b = Bala.new()
	b.name = "Bala"
	b.impacto.connect(func(donde: Vector3, contra: Node): impacto.emit(donde, contra))
	var raiz := get_tree().current_scene
	if raiz == null:
		raiz = get_tree().root
	raiz.add_child(b)
	b.lanzar(desde, vel, altura_mar)


## Cuelga el `.glb` y lo orienta a su banda. El modelo apunta a −X, así que una pieza de
## estribor va girada media vuelta y una de babor se queda como viene.
func _montar_modelo() -> void:
	if modelo == "" or not ResourceLoader.exists(modelo):
		push_warning("Canon: no existe el modelo '%s'" % modelo)
		return
	var escena := load(modelo) as PackedScene
	if escena == null:
		return
	var m := escena.instantiate() as Node3D
	if m == null:
		return
	m.name = "Modelo"
	if lado > 0.0:
		m.rotation.y = PI
	# La elevación gira el tubo sobre su eje transversal. El signo depende de la banda porque
	# la pieza de estribor está media vuelta girada: sin esto, una apuntaría al cielo y la otra
	# al agua.
	add_child(m)
	_modelo = m
	_curena = m.find_child("canon_curena", true, false) as Node3D
	_tubo = m.find_child("canon_tubo", true, false) as Node3D
	if _tubo == null:
		push_warning("Canon: el modelo no trae el tubo separado; no habrá elevación")
	else:
		_reposo_tubo = _tubo.transform.basis
	_aplicar_punteria()
	if altura_dormido > 0.0:
		_montar_dormido()


## La plataforma bajo la cureña. Va colgada del CAÑÓN y no del modelo: del modelo heredaría
## también la elevación del tubo y quedaría en cuesta. El giro de banda sí se le aplica, para
## que quede alineada con la cureña — es lo que hace que las ruedas caigan sobre la tabla.
##
## Su planta sale de dónde están las ruedas (`RUEDAS`) más su radio, no de un tamaño a ojo: así
## cubre la cureña entera aunque se cambie la escala de la pieza.
func _montar_dormido() -> void:
	const R_RUEDA := 0.1187
	const MARGEN := 0.05
	var x0: float = RUEDAS[0].x - R_RUEDA - MARGEN
	var x1: float = RUEDAS[2].x + R_RUEDA + MARGEN
	var z1: float = absf(RUEDAS[0].z) + 0.03 + MARGEN
	var d := MeshInstance3D.new()
	d.name = "Dormido"
	var caja := BoxMesh.new()
	caja.size = Vector3(x1 - x0, altura_dormido, z1 * 2.0)
	d.mesh = caja
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.21, 0.14)
	mat.roughness = 0.9
	d.material_override = mat
	# Bajo las ruedas: el origen del cañón está a media altura de su caja, así que la cara de
	# arriba del dormido tiene que quedar justo donde apoyan.
	d.position = Vector3((x0 + x1) * 0.5, -ALTO * 0.5 - altura_dormido * 0.5, 0.0)
	if lado > 0.0:
		d.position.x = -d.position.x
		d.rotation.y = PI
	add_child(d)


## Eje de los muñones en el modelo, medido: el tubo pivota ahí. En X respecto al centro de la
## caja del cañón; la Z no hace falta porque el `.glb` ya trae el tubo con su origen puesto.
const EJE_MUNON := Vector3(0.0305, 0.0, 0.1315)


## Lleva la puntería al modelo: el giro lateral a la pieza entera, la elevación solo al tubo.
##
## El signo de la elevación depende de la banda porque la de estribor va con el modelo girado
## media vuelta: sin distinguirlo, una pieza apuntaría al cielo y la otra al agua.
func _aplicar_punteria() -> void:
	rotation.y = deg_to_rad(giro_lateral) * (-1.0 if lado > 0.0 else 1.0)
	if _tubo == null:
		return
	var signo := -1.0 if lado > 0.0 else 1.0
	_tubo.transform.basis = _reposo_tubo * Basis(Vector3.BACK, deg_to_rad(elevacion) * signo)


## Dónde están las cuatro ruedas, en el mundo. Lo resuelve la pieza y no quien pregunta, porque
## depende de la estructura del `.glb`: las ruedas cuelgan de la CUREÑA, que desde que el tubo
## se separó tiene transformación propia dentro del modelo. Midiéndolas desde el nodo `Modelo`
## salían a más de un metro de su sitio.
func ruedas_globales() -> Array[Vector3]:
	var base: Node3D = _curena
	if base == null:
		base = _modelo if _modelo != null else self
	var sale: Array[Vector3] = []
	for r in RUEDAS:
		sale.append(base.global_transform * (r as Vector3))
	return sale

class_name VelaFisica
extends TelaFisica

## Vela de tela física. Además de colgar y llenarse con el viento (eso lo hace `TelaFisica`),
## sabe hacer las tres cosas que se le hacen a una vela, y las hace ELLA:
##
##   · `izar()` / `arriar()` — mueve sus propias drizas y recoge el paño contra la percha.
##   · `trimar()`            — orienta su percha a sotavento siguiendo al viento.
##
## Las dos primeras son órdenes del `Barco`; el trimado no se ordena, lo manda el viento, así
## que la vela lo hace sola cada frame igual que la bandera se orienta sola. La mecánica de
## ambas está en su `Aparejo`, que es lo que comparte con una vela de shader.
##
## Cómo se recoge (lo que hace que el viento no la afecte estando arriada):
##
## Izada, solo están fijados los vértices de anclaje (los AZULES de `Col`, o sea el gratil
## cosido a los garruchos y el puño de escota). El resto del paño cae y se infla con el viento.
##
## Arriando se fija TODO el paño. Cada vértice recibe su anclaje en la posición exacta que
## tenía en ese instante — así no hay tirón — y de ahí se lleva suavemente a su sitio del lío,
## que es el que ya calcula la piel del modelo. Dos cosas salen gratis: un punto fijado ignora
## las fuerzas, así que **el viento deja de afectar al paño entre que se arría y se vuelve a
## izar** sin tocar el campo del área; y el paño queda pegado al barco mientras está recogido,
## en vez de quedarse atrás.
##
## Al izar se suelta al revés, y en el momento de soltar el paño está justo en la forma que
## tenía cuando se agarró, así que la física continúa sin salto.

## A qué orden del barco responde esta vela. El barco abre y cierra "la de proa" y "la de popa"
## (W y S); cada vela sabe cuál es.
@export_enum("Delantera", "Trasera", "Ambas") var mando := 1

## Sus drizas y su trimado. Cada vela necesita el SUYO: el recurso guarda estado.
@export var aparejo: Aparejo

@export_group("Arrastre")
## Hueso cuyo movimiento RÍGIDO arrastra todo el paño.
##
## NO FUNCIONA, y queda aquí para no repetirlo: aplicar a los puntos libres el movimiento
## rígido del hueso con `PhysicsServer3D.soft_body_move_point()` EMPEORA la vela. El método fija
## la posición pero no la posición ANTERIOR del punto, así que el solver deduce una velocidad
## falsa cada frame y el paño gana energía. Medido: el hinchado pasa de 0,296 a 0,733 m de media
## y de 1,240 a 1,782 m de pico, con 700 vértices por encima de 0,5 m en vez de 142; el
## estiramiento no mejora (10,1 %). Haría falta poder tocar la velocidad por punto, y Godot no
## la expone. Vacío = desactivado, que es como debe quedarse.
@export var hueso_marco := ""

@export_group("Recogida")
## Con 1,6 el paño queda recogido del todo al 62 % del recorrido de la driza.
@export_range(1.0, 4.0) var rapidez_recogida := 1.6
## Fracción del recorrido a partir de la cual se congela el paño (y con ello deja de afectarle
## el viento). Antes esto pasaba en cuanto la driza se movía un milímetro, y como no se soltaba
## hasta que el izado terminaba del todo, al abrir la vela "se quedaba pensando" todo el
## recorrido y solo se inflaba al final. Con el umbral alto el paño vive y responde al viento
## durante casi todo el arriado y el izado, y solo se congela al cerrarse por completo.
@export_range(0.0, 1.0) var arriado_agarre := 0.62
## Se suelta un poco antes de volver a agarrar (histéresis) para que no parpadee en el umbral.
## Al izar, esto es lo que hace que el paño se despliegue ANTES de terminar de izar.
@export_range(0.0, 1.0) var arriado_suelta := 0.55
@export_group("")

var _arriado := 0.0                            ## fracción del recorrido de la driza [0..1]
var _marco := -1                               ## hueso que arrastra el paño
var _marco_ant := Transform3D()                ## dónde estaba ese marco el frame anterior
var _marco_ok := false


func _etiqueta() -> String:
	return "vela_fisica"


func _montado(barco: Node3D) -> void:
	if aparejo != null:
		aparejo.preparar(_skel, barco)
	_marco = _skel.find_bone(hueso_marco) if hueso_marco != "" else -1


# ── Órdenes del barco ────────────────────────────────────────────────────────
## Sube el paño. Con `inmediato` se planta arriba sin animación (al arrancar la escena).
func izar(inmediato := false) -> void:
	if aparejo != null:
		aparejo.izar(inmediato)


## Baja el paño y lo recoge contra la percha.
func arriar(inmediato := false) -> void:
	if aparejo != null:
		aparejo.arriar(inmediato)


func esta_izada() -> bool:
	return aparejo == null or aparejo.esta_izada()


## Orienta la percha a sotavento. Público porque es lo que una vela sabe hacer, aunque hoy
## nadie se lo ordene desde fuera: lo dispara ella misma con el viento de cada frame.
func trimar(delta: float) -> void:
	if aparejo != null:
		aparejo.trimar(delta)


# ── Lo que la vela hace sola cada frame ──────────────────────────────────────
## El aparejo se mueve ANTES de que la base lea la pose del esqueleto, para que las anclas del
## paño se coloquen ya con la percha en su sitio y no un frame por detrás.
func _antes_de_pose(delta: float) -> void:
	if aparejo != null:
		aparejo.paso(delta)


## El marco del paso anterior va en coordenadas de mundo: si no se corre con el recentrado, el
## arrastre de abajo leería un salto de kilómetros y se llevaría el paño entero con él.
func _al_recentrar(d: Vector3) -> void:
	super(d)
	_marco_ant.origin -= d


## Se recoge o se despliega según lo que haya recorrido la driza, y el paño VIAJA con el marco.
func _tras_pose(_delta: float, mats: Array[Transform3D]) -> void:
	_arriado = aparejo.arriado_medido() if aparejo != null else 0.0
	if _arriado > arriado_agarre and not _recogiendo:
		_agarrar()
	elif _arriado < arriado_suelta and _recogiendo:
		_soltar()
	# Mientras se recoge no hace falta arrastrar: está todo fijado.
	if _marco >= 0 and _rid.is_valid() and not _recogiendo:
		var m_ahora := _skel.global_transform * mats[_marco]
		if _marco_ok:
			var delta_m := m_ahora * _marco_ant.affine_inverse()
			if not delta_m.is_equal_approx(Transform3D()):
				for k in _anclas.size():
					if _fijo[k] == 1:
						continue
					PhysicsServer3D.soft_body_move_point(
						_rid, k, delta_m * _cuerpo.get_point_transform(k))
		_marco_ant = m_ahora
		_marco_ok = true
	else:
		_marco_ok = false


## Cuánto se ha llevado ya cada vértice de donde se agarró a su sitio del lío. La fracción se
## mide DESDE el umbral de agarre, no desde cero: así vale 0 en el instante mismo del agarre
## —sin tirón, que es la razón de ser de `_agarrar()`— y llega a 1 con la vela cerrada del
## todo. Midiéndola desde cero, agarrar tarde daría un salto de metros.
func _fraccion_recogida() -> float:
	var frac := 0.0
	if _arriado > arriado_agarre:
		frac = (_arriado - arriado_agarre) / maxf(1.0 - arriado_agarre, 0.001)
	var s := clampf(frac * rapidez_recogida, 0.0, 1.0)
	return s * s * (3.0 - 2.0 * s)

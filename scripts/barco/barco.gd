class_name Barco
extends CharacterBody3D

## Barco de vela. Propulsión por viento; el jugador lleva el timón (A/D) y gestiona
## las velas y el ancla:
##   · Tecla W → abrir/cerrar vela DELANTERA
##   · Tecla S → abrir/cerrar vela TRASERA
##   · ESPACIO → soltar/levar ANCLA (detiene el barco)
##   · Tecla F → alternar entre gobernar y andar por cubierta
## Las velas afectan a la propulsión (superficie abierta) y al giro (balance de velas).
## Cada acción emite una SEÑAL para engancharle animación más adelante.
##
## Lo que es PROPIO del barco vive aquí, no en scripts-nodo sueltos colgados de la escena:
## el timón (antes `control_timon.gd`), los colisionadores por los que se anda en cubierta
## (antes `colisiones_barco.gd`) y el cambio barco ↔ a pie (antes `paseo_cubierta.gd`).
## Las diferencias entre embarcaciones van en subclases (`Balandra extends Barco`).

signal vela_delantera_cambiada(abierta: bool)
signal vela_trasera_cambiada(abierta: bool)
signal ancla_cambiada(anclada: bool)

# ── Navegación ───────────────────────────────────────────────────────────────
@export var velocidad_max := 12.0
@export var aceleracion := 4.0
@export var velocidad_giro := 1.0
## En cuántos segundos mata la quilla el movimiento de LADO. Es lo que decide cuánto derrapa el
## casco al virar: con 0 pivota (el movimiento salta a la proa nueva al instante) y cuanto mayor
## sea, más se desplaza de costado antes de enfilar.
##
## El ángulo de deriva en una curva sostenida sale de `velocidad_giro · resistencia_lateral`, así
## que con 0,45 rad/s y 0,40 s son unos 10°, que es lo que abate un velero virando con todo el
## timón.
@export var resistencia_lateral := 0.40
## Inercia de GUIÑADA: en cuántos segundos llega el barco a la velocidad de giro que le piden el
## timón y las velas (la constante T de Nomoto). El timón empuja la popa contra el agua; el casco,
## con todo su peso girando alrededor de su centro, tarda en coger el giro y tarda en soltarlo.
##
## **Sin ella el giro aparecía de golpe**: medido con `tools/escora_dinamica.tscn`, a los 0,1 s de
## meter la caña la balandra ya giraba a 25,8 °/s, su giro entero. Y como la escora del giro va con
## `v·ω`, también la escora saltaba con la tecla — "como si no la frenara el peso del barco".
@export var inercia_guinada := 1.2
## Lo que el viento de proa empuja hacia atrás al aparejo y a la obra muerta, en fracción del
## EMPUJE a toda vela (no de `velocidad_max`). Ver la propulsión: dentro de la zona muerta la vela
## no tira y esto la hace ciar.
@export_range(0.0, 0.5) var cia_en_el_ojo := 0.08
@export var angulo_muerto := 45.0
@export var angulo_optimo := 100.0
@export_range(0.0, 1.0) var empuje_delantera := 0.4   # propulsión que aporta la vela delantera
@export_range(0.0, 1.0) var empuje_trasera := 0.6     # propulsión que aporta la vela trasera
@export var sesgo_giro_velas := 0.5                    # giro por balance de velas (rad/s a plena vela)
@export var nombre := "Barco"                          # nombre para el HUD/selector
## Qué clase de barco es («balandra», «goleta»…). Va aparte del nombre para que el HUD pueda
## decir las dos cosas: el nombre es propio y el tipo es el aparejo.
@export var tipo := ""
@export var altura_flotacion := 1.74                   # Y a la que flota (línea de cubierta sobre el agua)
## Si este casco lleva TAPA DE SENTINA: una chapa opaca a la altura de la lámina, dentro del
## casco, que impide ver el mar por sus aberturas.
##
## Hace falta, y está medido: sin nada, por la rejilla de la escotilla de la balandra se ve el
## agua con sus reflejos, dentro del barco. Lo que había antes para esto era RECORTAR el agua
## (un `discard` en el shader dentro de una elipse en planta), y eso deja de servir en cuanto el
## casco cabecea y escora: la elipse no gira con él, así que abre un hueco de mar por una banda
## mientras deja entrar el agua por la otra, y desde fuera se ve el corte alrededor del casco.
##
## La tapa no tiene ese problema porque es GEOMETRÍA y viaja con el barco. Además el mar queda
## entero: no se le hace un agujero, simplemente hay madera tapándolo donde no debe verse.
@export var tapa_sentina := true
## Qué tramo de la eslora se tapa, en metros y en ejes del barco (z mínimo, z máximo). Con (0, 0)
## se coge el casco entero.
##
## Lo usan las dos formas de que no se vea el mar dentro: el recorte del agua y la tapa de
## sentina. **Solo hay que tapar por donde se ve el agua, que es la bodega y sus escotillas**;
## llegar de proa a popa no aporta nada y multiplica las ocasiones de asomar por algún lado al
## escorar. La idea es del usuario y es la buena: cuanto menos cubra, menos puede fallar.
@export var zona_interior := Vector2.ZERO
## Si el agua se RECORTA dentro de este casco: el shader del mar tira los fragmentos que caen
## dentro del volumen del barco, y así no hay mar ni por las escotillas ni en la bodega.
##
## Estuvo apagado una temporada y se puso en su lugar una tapa de sentina —geometría sólida
## flotando dentro del barco— porque el recorte era una elipse EN PLANTA que no se inclinaba con
## el casco. Eso era arreglar el síntoma: lo que pedía el recorte era la pose entera del barco, no
## su posición y su rumbo. Con la matriz inversa del casco el agujero cabecea y escora con él.
@export var recorta_el_agua := true
## Nombre de la malla que encierra el hueco por donde se ve el agua: la BODEGA. De ella sale, tal
## cual, la caja con la que el mar se recorta. Vacío = este casco no recorta.
@export var malla_bodega := ""
@export var recorte_radio := Vector2(1.0, 2.0)         # semiejes del recorte del casco (manga, eslora)
# ── Timón ────────────────────────────────────────────────────────────────────
## Gira el hueso del timón según la ENTRADA del jugador, no según el giro real del casco:
## así la caña responde al instante aunque el barco esté parado o anclado, que es lo que se
## ve en la realidad. No-op si el barco no lleva ese hueso riggeado.
@export_group("Timón")
@export var timon_hueso := "timon"
@export_range(0.0, 60.0) var timon_angulo_max := 35.0   ## Grados máximos a cada banda.
@export var timon_eje := Vector3(0, 1, 0)               ## Eje LOCAL del hueso sobre el que gira.
@export var timon_invertir := false                     ## Invierte el sentido del giro.
@export_range(0.5, 20.0) var timon_suavizado := 6.0     ## Rapidez con que la caña sigue a la entrada.

# ── Andar por cubierta ───────────────────────────────────────────────────────
@export_group("Cubierta")
@export var tecla_paseo := KEY_F
## Se deja vacío y se carga al bajar a cubierta por primera vez: con un `preload` aquí,
## los cuatro barcos de la flota traen el personaje en memoria desde el arranque.
@export var escena_jugador: PackedScene
@export var ruta_jugador := "res://scenes/character/player.tscn"
@export var altura_capsula := 0.9                       ## Media altura de la cápsula, para no nacer hundido.
@export var camara_path: NodePath = ^"CamaraNav"        ## Cámara de gobierno a la que se vuelve.

# ── Colisionadores de cubierta ───────────────────────────────────────────────
## Se generan en runtime a partir de las propias mallas del modelo, así que valen para
## cualquier casco de la flota sin volver a medir a mano:
##
##  - Las mallas de `colision_mallas_suelo` se convierten en colisionadores de malla
##    (trimesh). Son pocas caras (la cubierta de la balandra tiene 50) y así el suelo sigue
##    exactamente al modelo, incluidas las cubiertas de proa y popa a distinta altura.
##  - Del casco se saca la línea de regala muestreándolo por secciones a lo largo de su eje
##    largo: por cada sección se busca su punto más alto y la manga a esa altura. Con eso se
##    levantan dos cadenas de cajas por banda, una para la borda (con su cara superior a la
##    altura de la regala, así que se puede subir y andar por ella) y otra invisible por
##    encima que impide caerse por fuera.
##  - En cada sección se busca además la altura de cubierta cerca de la crujía (el punto más
##    alto por debajo de la regala) y se pone suelo donde la malla de cubierta no llega: en la
##    balandra el panel central cubre 9 m de los 12 y las cubiertas de proa y popa son del
##    propio casco, a otra altura.
##  - Y se cierran los dos extremos con una barrera transversal, porque ahí la regala se
##    junta y no hay banda que levantar: sin ellas se sale andando por la proa (medido).
##
## El casco NO se convierte en trimesh a propósito: son 23.930 triángulos y el barco se
## mueve, así que la forma tendría que reubicarse en el árbol de colisiones cada frame.
## Cajas cuesta una fracción de eso y para andar por cubierta dan igual de bien.
##
## Con `colision_casco` vacío no se monta nada: los barcos por los que aún no se anda
## (lancha, barca, goleta) no pagan el muestreo ni avisan de mallas que no tienen.
@export_group("Colisiones de cubierta")
@export var colision_casco := ""
@export var colision_mallas_suelo: Array[String] = []
@export_range(4, 40) var colision_secciones := 16
@export var colision_grueso_borda := 0.14   ## Grueso de la cadena de cajas de la borda.
## Cuánto sube la barrera invisible sobre la regala. **En CERO no se levanta**, que es como va
## desde que el personaje sabe nadar: un muro de aire de metro y medio por toda la banda impide
## caerse, sí, pero también saltar al agua, subir por los obenques desde la regala y pasar a la
## mesa de guarnición — y caerse por la borda de un barco que navega es parte del juego, no un
## fallo. Quien cae nada (`Jugador._nadar`) y vuelve a bordo con E.
##
## Subirla otra vez es poner aquí un número: el mecanismo sigue entero, incluido apartarla de la
## jarcia (`colision_paso_jarcia`), que es lo que hacía falta para que dejara subir.
@export var colision_alto_barrera := 0.0
@export var colision_margen_barrera := 0.02 ## Cuánto se separa hacia fuera, para no pisarla.
## Mallas de JARCIA por las que se trepa. En la franja de eslora que ocupan, la barrera se aparta
## hacia fuera hasta dejar libre el plano de los cabos: si no, cae justo encima de las mesas de
## guarnición y los peldanos de abajo de la escala quedan dentro de una caja de colisión.
##
## Medido con `tools/subir_por_obenques.tscn` antes de esto: **4 peldanos de 13** tapados por la
## barrera, y el personaje empujando y saltando subía 1,45 m y se paraba clavado en y = 3,90, que
## es el borde alto de la barrera. Vacío = el barco no tiene jarcia por la que subir.
@export var colision_jarcia := "obenque_*"
## Hueco que se deja entre los cabos y la barrera. Es el DIÁMETRO de la cápsula del personaje
## (0,40 de radio en `player.tscn`) y no su radio: a los obenques se sube desde la regala con el
## cuerpo POR FUERA y la escala contra el pecho, como en un barco de verdad, así que tiene que
## caber entero al otro lado de los cabos. Con el radio la barrera seguía mordiendo cinco
## peldanos de trece (`tools/subir_por_obenques.tscn`), que además son los de abajo — justo por
## donde se empieza.
@export var colision_paso_jarcia := 0.85
## Escalas por las que se trepa, una por patrón: los flechastes de cada banda. De cada grupo sale
## un `EscalaJarcia` con su altura, su ancho y hacia dónde sube, medido de las propias mallas.
##
## Trepar no se resuelve con colisionadores y está medido: ver el docstring de `EscalaJarcia`.
@export var colision_escalas: Array[String] = ["flechaste_b_*", "flechaste_e_*"]
## Capa 3: la caja del casco va en la 2 y llena el interior del barco, así que el personaje
## no puede compartir capa con ella o andaría 1,2 m por encima de la cubierta.
@export_flags_3d_physics var colision_capa := 4
@export var colision_dibujar := false       ## Poner a true para ver las cajas mientras se ajusta.

# ── Carga ────────────────────────────────────────────────────────────────────
## Bultos estibados en cubierta (barriles, cajas). Cada uno es un `Carga` con su modelo, su
## sitio y su giro; el barco los instancia al arrancar y los cuelga de sí mismo, así que
## navegan y cabecean con él.
##
## Antes venían soldados dentro del `.glb` del casco, y eso los hacía inamovibles: no se podían
## quitar, ni cambiar de sitio, ni reutilizar en otro barco. Lo que hay aquí es la lista; el
## dónde y el cómo los sabe cada `Carga`.
@export_group("Carga")
@export var cargamento: Array[Carga] = []

# ── Acabado de la madera ─────────────────────────────────────────────────────
## Devuelve a la madera el relieve fino que el `.glb` no transporta: en Blender lo genera un
## grupo de nodos triplanar, y glTF solo lleva imágenes. Ver `AcabadoMadera`.
##
## Es una LISTA porque no todas las piezas quieren la fibra en el mismo sentido: el tablado de
## cubierta y el forro del casco la llevan girada respecto a los palos y las perchas.
@export_group("Acabado")
@export var acabado_madera: Array[AcabadoMadera] = []

# ── Artillería ───────────────────────────────────────────────────────────────
## Las piezas que monta el barco, cada una con su sitio y su banda. Misma idea que
## `cargamento`: es una LISTA de datos, así que artillar más o menos es editarla, no
## tocar la lógica de tiro. Vacía, el barco no monta nada y no paga nada.
@export_group("Artillería")
@export var artilleria: Array[Artilleria] = []
## Altura de la lámina de agua: es donde acaba la parábola del tiro. Si se deja en INF se
## busca sola en la escena (el nodo del agua), que es lo que hace falta para que la misma
## balandra valga en el mundo y en una escena de pruebas con el mar a otra altura.
@export var altura_mar := INF
## Balas en la santabárbara. Cada disparo gasta una.
@export_group("")

@export_group("Daños")
## Fracción de la reserva de flotabilidad que mete UNA vía de agua por segundo. Con 0,012 una vía
## sola llenaría el barco en 83 s si nadie achicara.
@export var caudal_via := 0.012
## Lo que achican las bombas por segundo: vía y media. Con una vía el barco se mantiene seco; con
## tres, entra el doble de lo que sale y se va a pique en poco más de un minuto.
@export var achique := 0.018
## Metros por encima de la lámina en que un impacto todavía cuenta como en la flotación: el balance
## mete esa franja en el agua a cada bandazo, así que un agujero ahí embarca agua.
@export var franja_flotacion := 0.30
## Metros que se hunde el casco con la reserva llena, antes de irse a pique.
@export var calado_inundado := 0.45
## Cuánta velocidad le quita el agua embarcada, con la reserva llena: un casco anegado pesa y no anda.
@export_range(0.0, 1.0) var frenada_inundado := 0.6
@export_group("")

## Las zonas del casco, como fracciones de su eslora en la flotación desde la roda: la proa es el
## primer cuarto y la popa el último quinto; el centro se parte por crujía en babor y estribor. Son
## las del icono de daños del HUD, que las lee de aquí para no dibujar unas zonas y dañar otras.
const ZONA_PROA := 0.25
const ZONA_POPA := 0.2
## Capa 8: las DIANAS, la madera de verdad del casco y la cubierta, que es lo que mira la bala.
const CAPA_DIANAS := 128

## Balas en el pañol, por tipo (`Municion.TIPOS`). La rasa es la de siempre; la palanqueta y la
## metralla son cargas especiales y se embarcan menos.
var pertrechos := {"rasa": 60, "palanqueta": 15, "metralla": 10}
## Lo que se carga en la batería entera. Cambiarlo recarga el tipo en todas las piezas, y con él su
## velocidad de boca: la guía y el capitán de IA lo ven solos, porque preguntan a la pieza.
var municion_actual := "rasa":
	set(v):
		if not pertrechos.has(v):
			return
		municion_actual = v
		for c in _canones:
			c.municion = Municion.de(v)
## La reserva del tipo cargado. Es lo que gastan los disparos y lo que pinta el panel.
var municion: int:
	get:
		return int(pertrechos.get(municion_actual, 0))
	set(v):
		pertrechos[municion_actual] = v
## Agua embarcada, en fracción de la reserva de flotabilidad (0 seco, 1 a pique).
var agua_embarcada: float:
	get:
		return _averias.agua if _averias != null else 0.0
var hundido: bool:
	get:
		return _averias != null and _averias.hundido
var _averias: Averias
var _dianas: StaticBody3D

## Cuántas estaciones de flotación se reparten a lo largo de la ESLORA. De ahí sale la rejilla
## entera: el paso es la eslora entre este número, y a lo ancho se ponen las que quepan con ese
## mismo paso, así que los puntos están a distancia regular en las dos direcciones y no hay que
## dar una cifra por eje. Ver `_repartir_flotacion()`.
@export_range(3, 15) var muestras_flotacion := 9
## Calado en metros: cuánto casco hay bajo la lámina. Es el tope de emersión de un punto de
## flotación — más arriba de eso el punto está EN EL AIRE y ya no puede perder más empuje.
##
## Es lo que deja la proa colgando sobre la cresta en vez de tirar de ella hacia abajo, y por eso
## la caída posterior es un golpe y no un vaivén simétrico.
@export var calado := 0.5
## Periodo propio de ARFADA (subir y bajar), CABECEO y BALANCE, en segundos, y lo amortiguado que
## va cada uno en fracción del crítico (1 = vuelve sin pasarse, 0 = oscila para siempre).
##
## Son SEIS números y no un filtro porque un casco no persigue la superficie: tiene masa, y su
## empuje es un muelle. Un filtro de primer orden —lo que había— no puede pasarse nunca de su
## objetivo, así que la proa no podía quedarse colgando en la cresta ni caer después con fuerza;
## llegaba a la ola tarde y suave y ahí se quedaba. Con un sistema de segundo orden eso sale
## solo, y la amortiguación es la que decide cuántos balanceos tarda en calmarse.
## El periodo de ARFADA no está aquí a propósito: sale de `calado`, porque un cuerpo que flota
## oscila a `sqrt(g/calado)` y no a lo que se le diga. Con este calado son 1,42 s.
@export_range(0.05, 1.5) var amortiguacion_arfada := 0.45
@export var periodo_cabeceo := 1.8
@export_range(0.05, 1.5) var amortiguacion_cabeceo := 0.40
## El periodo de BALANCE tampoco se elige: sale de la manga y de la GM — ver `periodo_balance()`.
@export_range(0.05, 1.5) var amortiguacion_balance := 0.80
## Cuánto de la inclinación que le tocaría se le aplica, de 0 a 1, en cada eje.
##
## **Son dos y no una, y la diferencia es física, no de gusto.** La estabilidad longitudinal de
## cualquier casco (GML) es dos órdenes mayor que la transversal (GM): la eslora es tres veces la
## manga y entra al cubo. Un barco lastrado NO se pone paralelo a la ola al escorar —se queda a
## medio camino, que es lo que mide `obediencia_escora`— pero en cabeceo no tiene margen para
## desobedecer: se apoya en la ola y sigue su pendiente casi exactamente.
@export_range(0.0, 1.0) var obediencia_escora := 0.7
@export_range(0.0, 1.0) var obediencia_cabeceo := 1.0
## Altura metacéntrica GM, en metros: LA medida de estabilidad de un casco.
##
## Es la que decide cuánto se tumba con un par dado, venga del viento o de un giro, y por eso las
## dos escoras se calculan contra ella en vez de con un número suelto cada una: un barco más
## estable se tumba menos por todo a la vez, que es como funciona de verdad. Un velero pequeño
## anda por 0,6-1,5 m; esta balandra es un casco de carga, ancho y con la bodega baja.
@export var altura_metacentrica := 0.9
## Brazo del par escorante del GIRO, en metros: altura del centro de gravedad sobre el centro de
## resistencia lateral, que es por donde el agua empuja de vuelta al casco. Es lo que convierte
## la fuerza centrífuga en un par en vez de en un empujón de lado.
##
## **En este casco valdría 1,4 m y aquí está en 0,32, y conviene saber por qué.** La fórmula es
## correcta; lo que no es realista es lo cerrado que vira este barco: a 9 m/s alcanza 0,45 rad/s,
## o sea un radio de 20 m con 12 m de eslora, y eso son 0,41 g de aceleración centrípeta. Con el
## brazo de verdad la escora se iba a 22° de media y 33 de punta, que es tumbar la regala en el
## agua — y la física decía bien, el que exagera es el timón. Se compensa aquí porque bajar
## `velocidad_giro` cambiaría el manejo del barco y el juego de la IA; el día que el gobierno se
## haga realista, este número sube a 1,4.
@export var brazo_giro := 0.32
## Brazo del par escorante del VIENTO, en metros por unidad de peso del barco, con el viento
## justo por el través, a fuerza 1 y con todo el trapo arriba. Calibrado para que dé unos 4° con
## el GM de esta balandra: `tan(4°) · 0,9 = 0,063`.
@export var brazo_velico := 0.063


# Estado de las acciones (empieza navegando: ambas velas abiertas, sin anclar).
var vela_delantera := true
var vela_trasera := true
var anclado := false
## Con false el barco ignora el teclado: se pone al andar por cubierta, porque el personaje
## usa WASD para lo suyo y si no gobernarías el barco a la vez.
var gobierno := true

## Timón mandado, de -1 (todo a babor) a +1 (todo a estribor). Lo escribe QUIEN GOBIERNA —el
## mando del jugador o un capitán de IA— y lo leen el casco y la caña. El barco NO lee el
## teclado: `Input.is_key_pressed` es global, así que con dos barcos en el agua los dos
## obedecían la misma tecla. Medido antes del cambio: dos balandras giraban +26,21° las dos,
## idénticos a la centésima, que es la firma de estar leyendo la misma entrada.
var orden_timon := 0.0:
	set(v):
		orden_timon = clampf(v, -1.0, 1.0)

var velocidad := 0.0
var time := 0.0
var base_y := 0.0
## Altura, cabeceo y escora del casco, y sus velocidades: el estado del sistema de flotación.
## Ver `_seguir_al_mar()`.
var _y_mar := 0.0
var _cabeceo := 0.0
var _escora := 0.0
var _v_arfada := 0.0
var _v_cabeceo := 0.0
var _v_escora := 0.0
var _mar_leido := false
## Puntos de flotación en ejes del barco: (x a la banda, z a la eslora, peso). Los reparte
## `_repartir_flotacion()` una vez, porque no cambian.
var _flotacion: Array[Vector3] = []
## Sumas fijas de la rejilla: peso total y momentos de segundo orden. Son el denominador de las
## pendientes y no dependen de la ola.
var _flot_w := 0.0
var _flot_x2 := 0.0
var _flot_z2 := 0.0
## Altura de la lámina bajo el casco, promediada sobre la rejilla de flotación. La calcula
## `_seguir_al_mar()` y la usa la tapa de sentina: es LA MISMA agua sobre la que flota el barco.
var _agua_media := 0.0
## Perfil del casco en la flotación: medio ancho por rebanada y entre qué z va. Lo mide
## `_anchos_en_la_flotacion()` una vez y lo consume el recorte del agua.
var _anchos := PackedFloat32Array()
var _anchos_z := Vector2.ZERO
var _anchos_fallo := false
## Caja de la bodega en ejes del barco, para el recorte del agua. Ver `caja_recorte()`.
var _caja_bodega := AABB()
var _caja_fallo := false
## Velocidad angular del casco y el rumbo del paso anterior, para medirla. Ver `_medir_giro()`.
var _omega := 0.0
## Velocidad de guiñada que el casco LLEVA, en rad/s: la que el timón y las velas le piden pasada
## por `inercia_guinada`.
var _guinada := 0.0
var _rumbo_previo := 0.0
## Cuánto se echa atrás la tapa respecto a la madera que tocan sus rayos, en METROS. Lo justo
## para no rozar el casco cuando escora: con 3° y 2,4 m de puntal, la sección se corre 12 cm.
const MARGEN_TAPA := 0.18
## Cuánto sube el faldón desde el borde de la tapa, en metros.
const ALTO_FALDON := 0.22
## Cuánto se levanta la tapa sobre la lámina, en metros.
##
## Hay dos límites y la tapa tiene que caber entre ellos: por abajo, la ola dentro de su propia
## eslora sube y baja unos 35 cm respecto al centro, y si la pasa se ve el mar dentro; por
## arriba está la cubierta, a 1,17 m de la lámina en esta balandra, y si la toca aparecen
## MANCHAS NEGRAS sobre las tablas — que es lo que pasó al hacer que el alza creciera con el
## estado de la mar hasta 95 cm, y con el faldón encima llegaba a 1,40. No crece con la mar: se
## queda donde cabe.
const ALZA_TAPA := 0.42
## Cuánto puede subir o bajar la tapa dentro de la bodega respecto a su sitio, en metros. Ver
## `_mover_tapa()`, que es donde están los dos límites que lo fijan.
const MARGEN_ALTO_TAPA := 0.35
## Lados del contorno de la tapa (la mitad por banda).
const LADOS_TAPA := 64
## Qué grosor de casco se mira alrededor de la línea de flotación, en metros.
const BANDA_TAPA := 0.25
## Cuánto se mete el recorte del agua hacia DENTRO del casco por cada banda, en metros.
var _tapa: MeshInstance3D
var _tapa_mat: StandardMaterial3D

var _skel: Skeleton3D
var _timon_idx := -1
var _timon_reposo := Quaternion.IDENTITY
var _timon_angulo := 0.0

var _jugador: CharacterBody3D
var _andando := false
## Si el personaje se cayó por la borda y anda nadando por su cuenta.
var _al_agua := false
var _cuerpo_colisiones: StaticBody3D
## Las velas de este barco. Se recogen entre los HIJOS DIRECTOS, por el método que responden
## (`izar`), no por su tipo: al barco le da igual que una vela sea de tela física o de shader
## mientras sepa izarse. Solo hijos directos, no una búsqueda recursiva: las velas son piezas
## del barco puestas en su escena, no algo que aparezca en cualquier rincón del modelo.
var _velas: Array[Node] = []
var _canones: Array[Canon] = []
## Batería apuntada: "estribor", "babor", "proa" o "popa". Es la que dispara.
var banda_apuntada := "estribor"
## Con true están vivos los controles de artillería y se dibuja la guía. Lo enciende quien
## gobierna (el mando del jugador con B, o un capitán de IA cuando decide entrar en combate).
var modo_battle := false
## Integridad por zona del casco, de 1 (sana) a 0 (destrozada). Es la ÚNICA fuente: el HUD la
## lee y no guarda copia. Hoy nada la baja —el modelo de daños está por hacer—, pero las zonas y
## la escala quedan fijadas para que quien lo haga solo tenga que escribir aquí.
var integridad := {"proa": 1.0, "babor": 1.0, "estribor": 1.0, "popa": 1.0, "aparejo": 1.0}
## Línea de regala que deja `_montar_colisiones`, reaprovechada para saber a qué altura
## pasa la borda bajo cada pieza: es lo que decide si el tiro es a barbeta o por porta.
var _regala_centros: Array[float] = []
var _regala_altos: Array[float] = []
var _regala_eslora_z := true
## Alto del barco en metros, medido de sus mallas. Decide cuándo se ha hundido del todo tras el
## horizonte.
var _alto := 0.0

@onready var helm_position: Marker3D = $HelmPosition
@onready var camara: Camera3D = _buscar_camara()



## Monta la tapa de sentina: un cuenco con la forma REAL del casco en la flotación, que impide
## ver el mar por las aberturas del barco.
##
## La silueta se MIDE con rayos contra el propio casco, no se saca de `recorte_radio`. Aquellos
## semiejes describen la silueta en cubierta, que es más ancha y sobre todo más larga que el
## casco a la altura del agua —la roda y el codaste se inclinan—, así que la tapa asomaba por
## fuera y se veía una caja negra alrededor del barco.
##
## El faldón sube desde el borde en lugar de bajar. Bajando salía por debajo de la quilla: este
## casco cala 47 cm y el faldón medía 90. Y hacia arriba tapa igual de bien lo que hay que tapar,
## que es la visión oblicua desde cubierta hacia el hueco entre la tapa y la madera.
func _poner_tapa() -> void:
	var contorno := _medir_silueta()
	if contorno.is_empty():
		return
	var vs := PackedVector3Array()
	vs.append(Vector3.ZERO)
	for p in contorno:
		vs.append(Vector3(p.x, 0.0, p.y))
	var idx := PackedInt32Array()
	var n := contorno.size()
	for k in n:
		idx.append_array([0, 1 + k, 1 + (k + 1) % n])
	# Faldón hacia ARRIBA: una pared corta desde el borde, para que no se cuele el mar de
	# refilón por la holgura contra la madera.
	for k in n:
		vs.append(vs[1 + k] + Vector3(0.0, ALTO_FALDON, 0.0))
	for k in n:
		var a := 1 + k
		var b := 1 + (k + 1) % n
		var c := 1 + n + k
		var d := 1 + n + (k + 1) % n
		idx.append_array([a, b, c, b, d, c])
	var ns := PackedVector3Array()
	ns.resize(vs.size())
	ns.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_INDEX] = idx
	var malla := ArrayMesh.new()
	malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)

	_tapa_mat = StandardMaterial3D.new()
	# **Madera de sentina, no agua.** Era un gris azulado oscuro —"agua de sentina"— y por la
	# rejilla de la escotilla se leía como lo que es: una lámina gris metida dentro del barco. El
	# usuario lo describió como "gris y azul dentro de la bodega".
	#
	# Y no es cuestión de gusto: medido con `tools/por_la_rejilla.tscn`, que fotografía cada
	# escotilla con la tapa y sin ella, la tapa ocupa el **83-94 % del hueco de las CUATRO, en las
	# 24 tomas**, y lo que esconde es el suelo de madera de la bodega — quitándola solo se vería
	# mar en el 1,7 % bajo las centrales. Es decir, casi nunca tapa mar: tapa madera.
	#
	# OJO, aquí estuvo escrito que la escotilla de popa "cae fuera de la bodega modelada", y es
	# FALSO: las cuatro caen dentro de su planta, la de popa con 0,255 m de margen hasta el
	# mamparo. Lo que pasa por esa rejilla es que el agua SUBE por encima del suelo de la bodega,
	# que solo lo tiene 0,182 m sobre la lámina. El error salió de comparar la posición
	# longitudinal de la escotilla (|z| hasta 2,07) contra el SEMIANCHO de la bodega (1,148), que
	# son dos ejes distintos — y por eso las dos que salían "limpias" eran justo las dos con
	# |z| < 1,148.
	# El albedo es de madera CLARA aunque lo que se vea acabe siendo oscuro: la tapa está bajo la
	# cubierta, sin luz directa y con la exposición de la escena a −5 EV, así que un albedo oscuro
	# se va a negro puro y vuelve a cantar. Lo que tiene que parecerse es al suelo de la bodega,
	# que es la tabla que hay al lado y se ve marrón.
	_tapa_mat.albedo_color = Color(0.30, 0.20, 0.12)
	_tapa_mat.roughness = 1.0
	_tapa_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tapa = MeshInstance3D.new()
	_tapa.name = "TapaSentina"
	_tapa.mesh = malla
	_tapa.material_override = _tapa_mat
	_tapa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# La tapa es hija del casco y hereda su pose ENTERA, cabeceo y escora incluidos. Fue `top_level`
	# —siguiendo solo posición y rumbo, porque la lámina no se inclina— y eso valía mientras el
	# casco apenas se movía; en cuanto cabeceó de verdad (±11° en temporal, contra ±1,5° antes) la
	# tapa se quedó plana dentro de un barco inclinado y asomó por la cubierta y por el costado.
	# Medido con `tools/tapa_en_su_sitio.tscn`: el borde se salía 0,30 m de su hueco con la mar de
	# siempre y 0,81 en temporal.
	#
	# Encaja por construcción porque está CORTADA con la forma del casco: mientras viaje con él no
	# puede asomar por ningún sitio. Lo único que se le ajusta es a qué altura va dentro.
	add_child(_tapa)
	print("%s: tapa de sentina de %d lados, %.2f x %.2f m"
		% [nombre, contorno.size(), _ancho_de(contorno, true), _ancho_de(contorno, false)])


## La forma del casco a la altura del agua, en ejes del barco: se saca de su MALLA.
##
## Se probaron antes dos caminos peores. Rayos desde crujía hacia fuera: no encuentran nada, 0 de
## 64, porque la colisión del casco es la caja del propio `CharacterBody3D` y Godot descarta los
## golpes que nacen dentro de una forma convexa. Rayos desde fuera hacia dentro: encuentran esa
## misma caja, que es un prisma tan largo como el barco, y la tapa salía de 11,64 m en un casco
## que a la altura del agua no llega a ocho — asomaba por la roda y por el codaste.
##
## La malla dice la verdad: se toma la banda de vértices que está a la altura de la lámina y, por
## rebanadas a lo largo de la eslora, el ancho que tiene ahí. Donde no hay vértices en esa banda
## es que el casco ya se acabó, y la tapa se acaba con él.
## Medio ancho del casco a la altura del agua, rebanada a rebanada a lo largo de la eslora, y
## entre qué z del barco va. Todo en ejes del barco y sacado de la MALLA.
##
## Es el perfil real de la flotación, y lo usan las dos cosas que necesitan saber por dónde corta
## el casco el agua: el recorte del mar y la tapa de sentina. `recorte_radio` no vale para esto —
## describe la silueta en CUBIERTA, que en esta balandra mide 3,8 x 12 m contra los 2,43 x 10,41
## de la flotación, o sea 70 cm de más por banda: recortando con ella se abre un hueco de mar
## alrededor del barco.
func _anchos_en_la_flotacion() -> Dictionary:
	if _anchos_fallo:
		return {}
	if not _anchos.is_empty():
		return {"lo": _anchos_z.x, "hi": _anchos_z.y, "ancho": _anchos}
	var mi := _malla(colision_casco)
	if mi == null or mi.mesh == null:
		push_warning("%s: sin malla '%s', no se puede medir la flotación" % [nombre, colision_casco])
		return {}
	var a_local := _relativo(mi)
	# La lámina en REPOSO, no la de ahora: `global_position.y` sube y baja con la ola, así que
	# midiendo con ella la banda cae donde toque ese frame. Medido, la lancha llegó a dar un casco
	# de 0,11 x 1,26 m, y un barco lejano —hundido por la curvatura— no daba nada y soltaba un
	# aviso por frame.
	var y_agua: float = Oleaje.nivel - altura_flotacion
	var lo := INF
	var hi := -INF
	var puntos: Array[Vector2] = []
	for v in mi.mesh.get_faces():
		var p: Vector3 = a_local * v
		if absf(p.y - y_agua) > BANDA_TAPA:
			continue
		puntos.append(Vector2(p.x, p.z))
		lo = minf(lo, p.z)
		hi = maxf(hi, p.z)
	if puntos.size() < 32 or hi <= lo:
		push_warning("%s: el casco no tiene malla a la altura del agua" % nombre)
		# Se marca el intento para no repetir el aviso en cada frame: quien pregunta es el mar, y
		# pregunta sesenta veces por segundo.
		_anchos_z = Vector2.ZERO
		_anchos = PackedFloat32Array()
		_anchos_fallo = true
		return {}
	var n := LADOS_TAPA / 2
	var ancho := PackedFloat32Array()
	ancho.resize(n)
	ancho.fill(0.0)
	for p in puntos:
		var k: int = clampi(int((p.y - lo) / (hi - lo) * float(n - 1) + 0.5), 0, n - 1)
		ancho[k] = maxf(ancho[k], absf(p.x))
	# Una rebanada vacía entre dos llenas es un hueco del modelo, no el final del casco.
	for k in n:
		if ancho[k] > 0.0:
			continue
		for salto in range(1, n):
			var izq: float = ancho[maxi(k - salto, 0)]
			var der: float = ancho[mini(k + salto, n - 1)]
			if izq > 0.0 or der > 0.0:
				ancho[k] = minf(izq if izq > 0.0 else der, der if der > 0.0 else izq)
				break
	_anchos = ancho
	_anchos_z = Vector2(lo, hi)
	print("%s: flotación medida, %.2f x %.2f m en %d rebanadas"
		% [nombre, _ancho_max(ancho) * 2.0, hi - lo, n])
	return {"lo": lo, "hi": hi, "ancho": ancho}


func _ancho_max(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m


func _medir_silueta() -> PackedVector2Array:
	var m := _anchos_en_la_flotacion()
	if m.is_empty():
		return PackedVector2Array()
	var lo: float = m["lo"]
	var hi: float = m["hi"]
	var ancho: PackedFloat32Array = m["ancho"]
	var n := LADOS_TAPA / 2

	# Recortada a la zona que hace falta tapar, si el barco la declara.
	var z0 := lo
	var z1 := hi
	if zona_interior != Vector2.ZERO:
		z0 = maxf(lo, zona_interior.x)
		z1 = minf(hi, zona_interior.y)
		if z1 <= z0:
			z0 = lo
			z1 = hi
	var out := PackedVector2Array()
	var derecha := PackedVector2Array()
	var izquierda := PackedVector2Array()
	for k in n:
		var z: float = lo + (hi - lo) * float(k) / float(n - 1)
		if z < z0 or z > z1:
			continue
		var w: float = maxf(ancho[k] - MARGEN_TAPA, 0.02)
		derecha.append(Vector2(w, z))
		izquierda.append(Vector2(-w, z))
	if derecha.size() < 3:
		return PackedVector2Array()
	out.append_array(derecha)
	for k in range(izquierda.size() - 1, -1, -1):
		out.append(izquierda[k])
	return out


func _ancho_de(c: PackedVector2Array, en_x: bool) -> float:
	var lo := INF
	var hi := -INF
	for p in c:
		var v: float = p.x if en_x else p.y
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


## Pone la tapa a su altura dentro del casco cada frame: por encima de la ola, sin llegar a la
## cubierta. Del rumbo, el cabeceo y la escora no se ocupa nadie: es hija del barco.
##
## **Plana y alta, no ondulada.** Se probó darle la forma del agua con el mismo shader del
## oleaje, para que quedase pegada a la lámina esté donde esté la ola, y el resultado fue peor:
## en Gerstner el punto no solo sube, se CORRE hacia la cresta hasta sesenta centímetros en
## horizontal, y ese arrastre sacaba la tapa fuera del casco. Se veía como una mancha oscura
## flotando junto al barco — y se supo que era ella, y no una sombra, apagándola y repitiendo la
## misma foto.
##
## Plana, lo que hay que evitar es que la ola la pase por encima, y para eso se levanta por
## encima de la lámina lo que dé de sí la mar. Sitio hay: entre el agua y la cubierta de esta
## balandra median 1,17 m.
func _mover_tapa() -> void:
	if _tapa == null:
		return
	var g := global_transform
	# A qué altura le tocaría ir: sobre la lámina que hay bajo el barco. Como la tapa es hija del
	# casco, se pide en su Y LOCAL; y no hay que restar la curvatura del horizonte, que el casco ya
	# lleva puesta en su propia posición.
	# La altura del agua se toma PROMEDIADA sobre la rejilla de flotación, no en un punto: el casco
	# flota sobre esa media, y si la tapa mira un punto suelto las dos leen superficies distintas y
	# la tapa sube y baja dentro de la bodega sin motivo. Medido: la deriva pasa de 0,46 a 0,15 m
	# con la mar de siempre, y lo que se veía moverse por las rejillas de la escotilla era eso.
	var y: float = _agua_media + ALZA_TAPA
	var nominal: float = ALZA_TAPA + Oleaje.nivel - altura_flotacion
	# El tope no es cosmético: por arriba está la cubierta —a 1,64 m del origen en esta balandra, y
	# la tapa con su faldón ocupa hasta 1,46 con el margen entero gastado— y por abajo la lámina,
	# que si pasa la tapa deja ver el mar dentro. Sin él, en temporal la tapa derivaba 1,83 m y se
	# iba por encima de la cubierta.
	_tapa.position.y = clampf(y - g.origin.y, nominal - MARGEN_ALTO_TAPA,
		nominal + MARGEN_ALTO_TAPA)


## Lo que el barco se tumba por navegar, aparte de lo que le hace la ola: el viento en las velas
## y la fuerza centrífuga del giro. En radianes, positivo = estribor arriba.
##
## **Los dos salen de la misma cuenta física**, que es lo que los hace coherentes entre sí:
##
##     par escorante = par adrizante
##     M                = peso · GM · sen(φ)     →     tan(φ) = (M / peso) / GM
##
## Para el GIRO, el par es la fuerza centrífuga por su brazo: `m · (v²/R) · brazo`. Y `v²/R` no
## hay que calcularlo con el radio de la curva, que no se conoce: es `v · ω`, la velocidad por la
## velocidad angular, las dos medidas. Al dividir entre el peso, **la masa se cancela** — dos
## barcos de la misma forma y distinta carga se tumban igual en la misma curva, y eso es un
## resultado, no una simplificación.
##
## Esto es además lo que hace que la escora del giro NO sea un salto: ω no aparece de golpe al
## tocar el timón, crece según el barco empieza a virar de verdad, y con poca arrancada no crece
## casi nada. Antes era un número atado directamente al timón y se notaba brusco.
##
## Para el VIENTO, el par va con el CUADRADO de la componente de través del viento aparente —la
## fuerza sobre una vela va con el cuadrado de la velocidad— por el trapo que haya arriba. En
## popa cerrada un velero no escora por mucho que empuje, porque el empuje va en el plano de
## crujía.
func _escora_de_navegacion() -> float:
	var lado := transform.basis.x
	var lado2 := Vector2(lado.x, lado.z)
	if lado2.length() < 0.001:
		return 0.0
	lado2 = lado2.normalized()
	var ap: Vector3 = Viento.aparente(velocity)
	# Componente por el través en fracción de la velocidad del viento. Sale NEGATIVA cuando el
	# viento sopla hacia babor, y entonces el barco se tumba a babor, o sea estribor arriba: por
	# eso el signo se invierte.
	var traves: float = Vector2(ap.x, ap.z).dot(lado2) / maxf(Viento.velocidad_m_s, 0.01)
	# El par escorante decae con el COSENO AL CUADRADO de la escora: el barco tumbado le presenta
	# menos vela al viento y la fuerza deja de tirar por el través. Sin esto, con el viento a
	# fuerza 1,9 de la escena de temporal la balandra se acostaba 32° y ahí se quedaba, con la
	# regala dentro del agua; con la mar normal no cambia nada (a 4° el coseno vale 0,995).
	var cos2: float = cos(_escora) * cos(_escora)
	var m_viento := -brazo_velico * traves * absf(traves) * _factor_velas() * cos2
	# El signo del giro está MEDIDO, no razonado: ver `tools/escora.tscn`, que lo mide con la
	# escora del viento apagada porque si no se leen las dos mezcladas y sale al revés.
	var m_giro := -velocidad * _omega * brazo_giro / 9.81
	return atan((m_viento + m_giro) / maxf(altura_metacentrica, 0.05))


## Periodo propio de BALANCE, en segundos: la fórmula de la OMI (criterio de viento y balance,
## Código IS 2008), `T = 2·C·B / √GM`, con `C = 0,373 + 0,023·B/d − 0,043·L/100`.
##
## **Valía 2 s puestos a mano, y con eso el casco AMPLIFICABA las rachas.** El viento racha a 0,11,
## 0,30 y 0,53 Hz, y un balance de 0,5 Hz sigue la más rápida casi entera: medido con
## `tools/escora_dinamica.tscn`, el viento pedía de 1,5° a 7,5° y el casco iba de 0,1° a 9,3°, a
## 9,3 °/s — un barco de carga dando bandazos de bote. Con la manga, el calado y la GM de esta
## balandra salen 3,9 s: lo que un casco de 12 m con su peso tarda de verdad en ir y volver.
##
## Manga y eslora en la flotación son las de la elipse de flotación, que es lo que ya flota.
func periodo_balance() -> float:
	var manga: float = recorte_radio.x * 2.0
	var eslora: float = recorte_radio.y * 2.0
	var c: float = 0.373 + 0.023 * manga / maxf(calado, 0.05) - 0.043 * eslora / 100.0
	return 2.0 * c * manga / sqrt(maxf(altura_metacentrica, 0.05))


## Arrancada mínima, en m/s, para virar POR AVANTE: cruzar el ojo del viento sin empuje y salir
## al otro lado aún andando. Sale de la física del propio casco, no de un número:
##
## - lo que hay que recorrer sin empuje es el arco de la zona muerta entera, `R · 2·angulo_muerto`,
##   con `R = velocidad_max / velocidad_giro` el radio de giro con la caña a la banda;
## - sin empuje la frenan el agua, con el cuadrado de la velocidad, y el viento de proa en el
##   aparejo, una fuerza fija `K = cia_en_el_ojo · cos medio · fuerza²` (en la zona muerta la vela
##   flamea entera). Con las dos, `v² + K·v_max²` cae de forma EXPONENCIAL con la distancia:
##   `(v² + K·v_max²)(s) = (v₀² + K·v_max²) · exp(−2·s · aceleracion / v_max²)`;
## - y hay que llegar al otro lado con arrancada para que la caña aún muerda: `velocidad_max ·
##   cia_en_el_ojo · fuerza`, 0,36 m/s en la balandra, 2 °/s de giro.
##
## En la balandra son 14 m de arco y 0,97 m/s (la física sola da 0,83 sin margen). Con la
## `aceleracion` de 2 m/s² que tuvo —siete veces lo que su peso permite— salían 2,9, ceñía a 1,6, y
## el capitán perdía la virada en el ojo 25° antes de cruzarlo.
func velocidad_para_virar() -> float:
	var radio: float = velocidad_max / maxf(velocidad_giro, 0.01)
	var muerto := deg_to_rad(angulo_muerto)
	var arco: float = radio * 2.0 * muerto
	var v2 := maxf(velocidad_max * velocidad_max, 0.01)
	var f := maxf(Viento.fuerza, 0.05)
	var k: float = cia_en_el_ojo * (sin(muerto) / maxf(muerto, 0.01)) * f * f * v2
	var v_salida: float = velocidad_max * cia_en_el_ojo * f
	return sqrt(maxf((v_salida * v_salida + k) * exp(2.0 * arco * aceleracion / v2) - k, 0.0))


## Velocidad de guiñada que el casco lleva, en rad/s, positiva hacia babor (el sentido de
## `rotate_y`). Pública para quien gobierna: con inercia, hay que aguantar el giro antes de llegar.
func guinada() -> float:
	return _guinada


## Velocidad angular del casco, en rad/s, medida de su propio rumbo. Se filtra un poco porque
## derivar un ángulo frame a frame es ruidoso y ese ruido acabaría en la escora.
func _medir_giro(delta: float) -> void:
	if delta <= 0.0:
		return
	var proa := -transform.basis.z
	var rumbo := atan2(proa.x, proa.z)
	var w := wrapf(rumbo - _rumbo_previo, -PI, PI) / delta
	_rumbo_previo = rumbo
	_omega += (w - _omega) * clampf(delta / 0.15, 0.0, 1.0)


## Hacia dónde tira la propulsión: la proa, pero en el plano del agua.## Hacia dónde tira la propulsión: la proa, pero en el plano del agua.
##
## No vale `-basis.z` a secas desde que el casco cabecea: con la proa 2,5° arriba, esa dirección
## lleva medio metro por segundo de subida que no existe, y el barco se propulsaría hacia el
## cielo. Un barco avanza sobre el agua, no hacia donde mira su roda.
func _proa_horizontal() -> Vector3:
	var p := -transform.basis.z
	p.y = 0.0
	return p.normalized() if p.length() > 0.001 else -transform.basis.z


## Pone el cabeceo y la escora que pide la ola, conservando el rumbo.
##
## Se reconstruye la base entera en vez de ir girando sobre los ejes locales, que acumularía
## error. Y el rumbo se LEE de la base en vez de guardarse aparte: `rotate_y()` gira sobre el eje
## Y del padre, así que el timón sigue sumando al ángulo de rumbo por mucho que el casco esté
## inclinado, y el orden de Euler que Godot usa por defecto (YXZ) lo devuelve limpio. Así el
## timón, el sesgo de velas y todo lo que gira el barco siguen funcionando sin tocarlos.
func _aplicar_inclinacion() -> void:
	var eu := transform.basis.get_euler()
	transform.basis = Basis.from_euler(Vector3(_cabeceo, eu.y, _escora))


## Y a la que va el casco: su altura de flotación, el bamboleo, y la CURVATURA de la Tierra.
##
## La curvatura es lo que hace que un barco lejano se hunda de abajo arriba —primero el casco,
## después las velas, el tope del palo lo último—, que es como desaparece un barco de verdad; y
## es la misma que hunde el agua en `agua.gdshader`, así que el casco y su mar bajan juntos. Si
## solo se curvase el agua, un barco lejano quedaría flotando por encima de ella.
##
## Se resta al BARCO y no a su modelo para que la arboladura y los paños bajen con él: las velas
## son `SoftBody3D` en espacio de mundo y van donde vayan sus anclas, que cuelgan del esqueleto.
##
## Sobre el barco del jugador no hace nada, y no por un caso especial: la cámara lo acompaña, su
## distancia es de metros y la caída va con el CUADRADO de ella — a 100 m son ocho décimas de
## milímetro.
func _altura_de_flotacion() -> float:
	# El agua embarcada hunde el casco, y a pique se lo lleva al fondo.
	var y := _y_mar - (_averias.calado_extra() if _averias != null else 0.0)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return y
	var caida := Horizonte.caida_entre(global_position, cam.global_position)
	# Cuando ni el tope del palo asoma ya no hay nada que dibujar. Sin esto el barco seguiría
	# ahí abajo, gastando y asomando por los reflejos.
	if _alto > 0.0:
		visible = caida < _alto
	return y - caida


## El perfil del casco en la flotación: medio ancho por rebanada, en metros y en ejes del barco.
## Lo usa la tapa de sentina para cortar su silueta, y la batería para comprobar que la caja del
## recorte se queda por dentro del forro.
func perfil_de_flotacion() -> PackedFloat32Array:
	_anchos_en_la_flotacion()
	return _anchos


## La silueta del casco en la flotación: {lo, hi, ancho} —z de la proa y de la popa en ejes del
## barco, y medio ancho por rebanada—, o vacío si no se pudo medir. La usa la estela.
func silueta_de_flotacion() -> Dictionary:
	return _anchos_en_la_flotacion()


## La caja con la que se recorta el agua, en ejes del barco: **la bodega tal cual**.
##
## El usuario lo pidió con estas palabras —"si hacemos que el corte coincida con la bodega es
## suficiente"— y resulta que además es lo que arregla las dos mitades del defecto de golpe:
##
## - **No puede asomar por el costado.** La caja y el casco están los dos en ejes del barco, así
##   que giran juntos: lo que está dentro del casco lo está en cualquier pose. Antes el recorte
##   tomaba su planta del CASCO —2,09 m de manga contra 3,30, apenas 60 cm de holgura por banda— y
##   cualquier escora lo sacaba por el forro. La bodega deja 0,50 m a cada lado (semimanga 1,148
##   contra 1,65 del casco en la flotación) y no hay nada que se desplace respecto a nada.
## - **No deja un agujero bajo un barco levantado.** El recorte llevaba un margen vertical de
##   CINCO METROS (`recorte_margen_v`), así que al subir el casco sobre una cresta seguía borrando
##   agua muy por debajo de él, donde ya no hay casco que tape el hueco — y eso es lo que se veía
##   como una mancha lisa junto al barco en el mar de tormenta. Con la caja de la bodega, si el
##   agua queda por debajo de su suelo simplemente no se recorta: y no hace falta, porque ahí la
##   tapa el propio suelo de la bodega.
##
## Y por qué hay que recortar algo, habiendo bodega: **el agua se mete DENTRO de ella**. Su suelo
## está 0,182 m sobre la lámina en reposo (0,650 contra 0,468) y el casco se separa de la ola
## 0,069 m de media y 0,205 el peor con la mar de siempre, 0,358 y 1,19 en temporal. Cuando la
## supera, por la rejilla se ve mar en el hueco ENTERO — medido, el 14,7 % del encuadre que ocupa
## la rejilla, contra el 1,7 % de las escotillas centrales, que están más cerca del centro de
## cabeceo y casi nunca llegan a esa condición.
##
## Devuelve [] si este casco no declara bodega o no se encuentra: entonces no se recorta nada.
func caja_recorte() -> Array:
	if _caja_fallo:
		return []
	if _caja_bodega != AABB():
		return [_caja_bodega.position, _caja_bodega.end]
	if malla_bodega == "":
		_caja_fallo = true
		return []
	var mi := _malla(malla_bodega)
	if mi == null or mi.mesh == null:
		push_warning("%s: no encuentro la malla de bodega '%s'" % [nombre, malla_bodega])
		_caja_fallo = true
		return []
	_caja_bodega = _relativo(mi) * mi.mesh.get_aabb()
	print("%s: recorte del agua por la bodega, %.2f x %.2f m, de y=%.2f a %.2f"
		% [nombre, _caja_bodega.size.x, _caja_bodega.size.z,
			_caja_bodega.position.y, _caja_bodega.end.y])
	return [_caja_bodega.position, _caja_bodega.end]


## Reparte los puntos de flotación por el plano de flotación del casco: una rejilla REGULAR,
## del mismo paso en las dos direcciones, recortada a la elipse de `recorte_radio`.
##
## La rejilla es regular y el peso de cada punto el mismo a propósito: así el reparto de fuerzas
## sale de la FORMA del casco y no de una ponderación escrita a mano — donde el barco es ancho
## caben más puntos y ahí empuja más, que es lo que hace el agua. Los extremos de proa y popa se
## llevan pocos, que es justo lo que les corresponde por lo fino que es el casco ahí.
##
## Se calcula una vez: no cambia con la ola ni con el rumbo.
func _repartir_flotacion() -> void:
	_flotacion.clear()
	_flot_w = 0.0
	_flot_x2 = 0.0
	_flot_z2 = 0.0
	var n: int = maxi(muestras_flotacion, 3)
	var paso: float = recorte_radio.y * 2.0 / float(n)
	var filas: int = maxi(int(round(recorte_radio.x * 2.0 / maxf(paso, 0.01))), 1)
	for j in n:
		# Centro de cada estación, no su borde: con los bordes el primer punto cae en la punta de
		# la proa, donde el casco no tiene manga y no hay nada que flote.
		var z: float = -recorte_radio.y + paso * (float(j) + 0.5)
		var u: float = z / recorte_radio.y
		var semi: float = recorte_radio.x * sqrt(maxf(1.0 - u * u, 0.0))
		for i in filas:
			var x: float = -recorte_radio.x + recorte_radio.x * 2.0 * (float(i) + 0.5) / float(filas)
			if absf(x) > semi:
				continue          # fuera del casco: ahí no hay obra viva
			_flotacion.append(Vector3(x, 0.0, z))
			_flot_w += 1.0
			_flot_x2 += x * x
			_flot_z2 += z * z
	# Un casco tan fino que no recoge ningún punto no puede flotar: al menos el del centro.
	if _flotacion.is_empty():
		_flotacion.append(Vector3.ZERO)
		_flot_w = 1.0
	_flot_x2 = maxf(_flot_x2, 0.01)
	_flot_z2 = maxf(_flot_z2, 0.01)
	print("%s: %d puntos de flotación, paso %.2f m (%d estaciones x %d de banda)"
		% [nombre, _flotacion.size(), paso, n, filas])


## Flota el casco sobre la ola: lee el agua bajo cada punto de flotación y de ahí saca a qué
## altura queda, cuánto cabecea y cuánto escora. Se llama al principio del paso de física.
##
## **Por qué una rejilla de puntos y no la proa, la popa y las dos bandas.** Con cuatro puntos, el
## cabeceo salía de restar la altura del agua en dos puntos separados una ESLORA entera, y dos
## puntos separados una longitud de onda leen lo mismo: una ola de doce metros —de las que este
## mar tiene— se anulaba entera, y las más cortas, que son las de más pendiente, se quedaban a la
## mitad. Medido con `tools/cabeceo_en_la_mar.tscn`: con la mar de proa, dos puntos le pedían al
## casco 6,33° de pico a pico donde el agua bajo él tenía 13,1. Con la rejilla, 9,26.
##
## **Y el signo del cabeceo estaba al revés.** Girar +X en Godot sube la proa, que está en −Z, y
## la fórmula de los cuatro puntos hacía lo contrario: el parecido entre lo que el casco cabeceaba
## y lo que la ola le pedía salía **−0,82** en los cinco rumbos, contra +0,73 de la escora. O sea
## que el casco metía la proa justo cuando la ola se la levantaba, y por eso de proa a popa no se
## veía mar y de banda a banda sí. Ahora no hay signo que elegir: la inclinación sale del EMPUJE,
## y un punto que se hunde levanta su lado.
##
## **El casco tiene masa: es un muelle amortiguado, no un filtro.** Cada punto aporta empuje según
## lo hundido que esté (la hidrostática linealizada, que es lo que vale cerca de la flotación),
## eso da una aceleración en arfada, cabeceo y balance, y se integra. De ahí sale solo lo que un
## filtro de primer orden no puede dar: la proa se queda colgando al pasar la cresta, cae después
## con más fuerza de la que la ola pide, se hunde de más y vuelve a flote balanceándose hasta que
## se calma. Lo que lo remata es el tope de emersión: un punto que sale del agua no puede perder
## más empuje del que tenía (`calado`), así que colgando sobre la cresta el casco solo tiene su
## peso, como pasa de verdad.
##
## Los puntos se leen EN PLANTA —el casco se apoya en la ola, no en su propia inclinación— pero su
## altura sí lleva la inclinación de ahora: eso es lo que cierra el lazo y hace de muelle.
func _seguir_al_mar(delta: float) -> void:
	if _flotacion.is_empty():
		_repartir_flotacion()
	var g := global_transform
	var proa := -g.basis.z
	var lado := g.basis.x
	var ph := Vector2(proa.x, proa.z)
	var lh := Vector2(lado.x, lado.z)
	if ph.length() < 0.001 or lh.length() < 0.001:
		return
	ph = ph.normalized()
	lh = lh.normalized()
	var c := Vector2(g.origin.x, g.origin.z)
	# Altura de la lámina en cada punto, y la del propio casco ahí con la inclinación de ahora.
	# Con el orden de Euler de Godot (YXZ) y ángulos de pocos grados, un punto (x, z) del plano de
	# flotación queda a `y + x·sen(escora) − z·sen(cabeceo)`: +X sube la proa (−Z) y +Z sube
	# estribor (+X).
	var sc := sin(_cabeceo)
	var se := sin(_escora)
	var sum_d := 0.0
	var mojados := 0
	var mom_cab := 0.0
	var mom_esc := 0.0
	var sum_ola := 0.0
	var ola_cab := 0.0
	var ola_esc := 0.0
	for pt in _flotacion:
		var h: float = Oleaje.altura_en(c + ph * pt.z * -1.0 + lh * pt.x)
		# OJO al signo de z: el punto está a `pt.z` en ejes del barco, donde la proa es −Z, así que
		# avanzar hacia proa es restar por `ph`.
		var y_pt: float = _y_mar - altura_flotacion + Oleaje.nivel + pt.x * se - pt.z * sc
		# Emersión limitada al calado: fuera del agua no hay más empuje que perder.
		var d: float = maxf(h - y_pt, -calado)
		if h > y_pt:
			mojados += 1
		sum_d += d
		mom_cab += d * -pt.z
		mom_esc += d * pt.x
		var ho := h - (Oleaje.nivel)
		sum_ola += ho
		ola_cab += ho * -pt.z
		ola_esc += ho * pt.x
	# Pendientes: la que el empuje pide ahora mismo, y la que tendría el agua sola. La segunda es
	# la que permite obedecer a medias sin tocar el muelle — ver `obediencia_escora`.
	var pend_cab := mom_cab / _flot_z2
	var pend_esc := mom_esc / _flot_x2
	var pend_cab_ola := ola_cab / _flot_z2
	var pend_esc_ola := ola_esc / _flot_x2
	var err_y := sum_d / _flot_w
	_agua_media = sum_ola / _flot_w + Oleaje.nivel
	var err_cab := pend_cab + (obediencia_cabeceo - 1.0) * pend_cab_ola
	var err_esc := pend_esc + (obediencia_escora - 1.0) * pend_esc_ola

	# La escora de NAVEGACIÓN (viento y giro) es un ángulo de equilibrio, no una fuerza: se le pide
	# al muelle como un desplazamiento del cero. Así sigue saliendo de `altura_metacentrica` y toda
	# su física medida, y de paso se gana que llegue balanceándose en vez de de golpe.
	err_esc += sin(_escora_de_navegacion())

	# La frecuencia de ARFADA no se elige: un cuerpo que flota oscila a `sqrt(g/calado)`, y de ahí
	# sale que con el casco ENTERO fuera del agua —`sum_d` saturado a `-calado` en todos los
	# puntos— la aceleración valga exactamente `-g`. Es decir, que caiga como cae cualquier cosa.
	# Con un periodo puesto a mano no cuadraba: 1,6 s da 7,7 m/s² en vez de 9,81.
	var w_y: float = sqrt(9.81 / maxf(calado, 0.05))
	var w_c: float = TAU / maxf(periodo_cabeceo, 0.05)
	var w_e: float = TAU / periodo_balance()
	# **La amortiguación va con lo que esté MOJADO.** La frena el agua, así que donde no hay agua no
	# frena: con el casco al aire el término de amortiguación seguía actuando y lo sostenía —medido,
	# caía a 1,67 m/s² con la mar de siempre y a 5,92 en temporal, contra los 9,81 que le tocan—, y
	# eso es exactamente lo que se ve como un barco que vuela sobre el seno entre dos olas.
	#
	# **Salvo el BALANCE**, que no lo frenan los puntos de la flotación sino la QUILLA —honda, va
	# siempre mojada— y las velas contra el aire. Con la amortiguación recortada por lo mojado, en
	# cuanto la ola dejaba media banda en el aire el balance se quedaba sin freno y el casco se
	# tumbaba MÁS que lo que pedía la racha: medido con `tools/escora_dinamica.tscn`, 6,63° de pico a
	# pico contra 6,01 pedidos, y con el freno entero 4,06° a 2,9 °/s en vez de 5,8.
	var f_moj: float = float(mojados) / _flot_w
	if not _mar_leido:
		# Primer paso: se coloca donde le toca sin oscilación, o el barco nace dando un salto.
		_mar_leido = true
		_y_mar += err_y
		_cabeceo += err_cab
		_escora += err_esc
		_v_arfada = 0.0
		_v_cabeceo = 0.0
		_v_escora = 0.0
		return
	# Euler semi-implícito: con w·dt por debajo de 0,1 (1,6 s de periodo a 60 Hz da 0,065) es
	# estable de sobra y no hace falta nada más fino.
	_v_arfada += (w_y * w_y * err_y
		- 2.0 * amortiguacion_arfada * w_y * _v_arfada * f_moj) * delta
	_v_cabeceo += (w_c * w_c * err_cab
		- 2.0 * amortiguacion_cabeceo * w_c * _v_cabeceo * f_moj) * delta
	_v_escora += (w_e * w_e * err_esc
		- 2.0 * amortiguacion_balance * w_e * _v_escora) * delta
	_y_mar += _v_arfada * delta
	_cabeceo += _v_cabeceo * delta
	_escora += _v_escora * delta


## Alto del barco, del casco al tope, medido de sus mallas. Diferido porque el modelo se
## instancia con la escena, y saltando los `SoftBody3D`: un paño físico vive en espacio de mundo
## y su caja no dice nada de lo que mide el barco.
func _medir_alto() -> void:
	var bajo := INF
	var alto := -INF
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi is SoftBody3D or mi.mesh == null or not mi.is_inside_tree():
			continue
		var caja := mi.get_aabb()
		var t := global_transform.affine_inverse() * mi.global_transform
		for k in 8:
			var y: float = (t * caja.get_endpoint(k)).y
			bajo = minf(bajo, y)
			alto = maxf(alto, y)
	if alto > bajo:
		_alto = alto - bajo


func _ready() -> void:
	# Cada barco flota a SU altura (una balandra grande no flota igual que la lancha).
	position.y = altura_flotacion
	base_y = altura_flotacion
	_y_mar = altura_flotacion
	_repartir_flotacion()
	# NO se anuncia solo como el del jugador. Lo hacía en su `_ready`, y con eso el segundo
	# barco de la escena se declaraba "activo": el mar, el HUD, la cámara y las flechas de
	# viento se iban con el enemigo. Quién es el barco del jugador lo decide quien le sube el
	# jugador a bordo — `tomar_mando_jugador()`.
	_medir_alto.call_deferred()
	if tapa_sentina:
		_poner_tapa.call_deferred()
	_preparar_timon()
	_averias = Averias.new()
	_averias.name = "Averias"
	_averias.barco = self
	add_child(_averias)
	for h in get_children():
		if h.has_method("izar"):
			_velas.append(h)
		if h.has_method("configurar"):
			h.configurar(self)
	# Diferido, y por dos razones distintas: las mallas del .glb no están en el árbol hasta
	# después de este _ready (colisiones), y las velas se montan ellas también en diferido, así
	# que la primera orden tiene que ir detrás de su montaje.
	if colision_casco != "":
		_montar_colisiones.call_deferred()
		_montar_dianas.call_deferred()
	if not cargamento.is_empty():
		_montar_carga.call_deferred()
	if not acabado_madera.is_empty():
		_montar_acabado.call_deferred()
	if not artilleria.is_empty():
		_montar_artilleria.call_deferred()
	_mandar_velas.call_deferred(true)


## El barco ya no lee teclas de maniobra ni de artillería: eso es de quien gobierna
## (`MandoJugador` o un capitán de IA). Aquí queda solo el cambio timón ↔ cubierta, que es del
## barco porque es él quien instancia al personaje y le da sitio en `HelmPosition`.
func _unhandled_input(event: InputEvent) -> void:
	if not is_in_group("barco_activo"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == tecla_paseo:
			alternar_modo()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_mover_timon(delta)
	# Si el personaje desaparece (por ejemplo al cambiar de barco con TAB), volver al timón.
	if _andando and (_jugador == null or not is_instance_valid(_jugador)):
		_a_gobernar()


func _physics_process(delta: float) -> void:
	time += delta
	_medir_giro(delta)
	_seguir_al_mar(delta)

	if anclado:
		# Anclado: frena y se queda quieto (solo el balanceo del oleaje). No gira ni avanza.
		velocidad = move_toward(velocidad, 0.0, aceleracion * 3.0 * delta)
		velocity = _proa_horizontal() * velocidad
		_guinada = 0.0
		move_and_slide()
		position.y = _altura_de_flotacion()
		_aplicar_inclinacion()
		_mover_tapa()
		return

	# **El timón no mueve el barco: desvía el agua que pasa por él.** Sin arrancada no pasa agua y
	# no hay gobierno; con arrancada atrás el agua lo ataca por la otra cara y la caña obra al
	# revés. Por eso el giro va con la velocidad CON SIGNO y sin mínimo ninguno.
	#
	# Y es lineal a propósito: un barco con la caña a una banda describe un círculo de RADIO
	# constante, así que su velocidad angular es `v/R` — proporcional a la velocidad. Aquí el radio
	# sale de los dos números que ya había, `velocidad_max / velocidad_giro`, y son 10 m.
	#
	# Antes había un `giro_minimo` del 20 %, y con él el barco giraba parado: medido con
	# `tools/gobierno.tscn`, **−0,72 °/s sin velas y quieto, y −5,15 °/s de proa al viento**, que
	# es lo que se veía como un barco que da vueltas sobre sí mismo en el ojo del viento con solo
	# mantener la caña a una banda.
	var vel_rel := clampf(velocidad / maxf(0.01, velocidad_max), -1.0, 1.0)
	var vel_norm := absf(vel_rel)
	var pide := orden_timon * velocidad_giro * vel_rel
	# Sesgo de giro por balance de velas (trasera → orza; delantera → arriba).
	pide += _sesgo_velas(vel_norm)
	# Lo que piden timón y velas es un PAR, no un giro: el casco lo coge con su inercia.
	_guinada += (pide - _guinada) * clampf(delta / maxf(inercia_guinada, 0.01), 0.0, 1.0)
	rotate_y(_guinada * delta)

	# Propulsión: viento × ángulo × superficie de vela abierta.
	var objetivo := velocidad_max * factor_viento() * Viento.fuerza * _factor_velas()
	# Anegado anda menos, y a pique no anda.
	objetivo *= 0.0 if hundido else 1.0 - frenada_inundado * agua_embarcada
	# **El viento por la proa empuja hacia atrás, y hay que restarlo SIEMPRE.** La vela deja pasar
	# el viento cuando flamea, pero el aparejo, los palos y la obra muerta siguen recibiéndolo, y
	# eso hace ciar. Va con lo de cara que venga el viento, no como un caso aparte dentro de la
	# zona muerta: probado así primero, y el barco se quedaba clavado JUSTO EN EL BORDE —medido con
	# `tools/porque_no_dispara.tscn`, `factor_viento` positivo pero casi cero, velocidad 0,00
	# exacta durante 25 s y sin gobierno, porque sin arrancada el timón no hace nada—. Con la
	# resistencia continua, ahí cía un poco y puede salir.
	#
	# Que exista importa más que cuánto valga: es lo que permite salir del ojo del viento, porque
	# con arrancada atrás la caña obra al revés y el barco cae a la banda que se le pida.
	#
	# **Y es una FUERZA, no una velocidad que se resta.** Restada de `objetivo` entraba al cuadrado
	# en la ley de abajo: 0,08² de `aceleracion`, 0,002 m/s², unos 24 N contra 12,8 t. Con la masa
	# del casco eso no hacía ciar a nadie —medido con `tools/ojo_del_viento.tscn`, −0,055 m/s y 4,4°
	# girados en 30 s con la caña a la banda, y no salía nunca—. Ahora es `cia_en_el_ojo` del EMPUJE
	# a toda vela: 0,08 de 3,7 kN son unos 300 N, lo que el palo, la jarcia, la lona flameando y la
	# obra muerta de un casco de 12 m reciben con viento fresco. Va con lo DESVENTADA que esté la
	# vela (`1 − factor_viento`, el mismo número del flameo y del audio): la lona que porta ya tiene
	# su resistencia dentro de la polar, la que flamea no. Así la ceñida de 65° anda lo mismo que
	# antes (1,46 m/s contra 1,45) y de proa al viento sale en unos 30 s.
	var v2 := velocidad_max * velocidad_max
	var empuje := objetivo * absf(objetivo) / maxf(v2, 0.01)
	var w := Viento.direccion
	w.y = 0.0
	if w.length() > 0.001:
		# 1 = el viento justo de cara, 0 = de través o de popa.
		var de_cara: float = maxf(_proa_horizontal().dot(-w.normalized()), 0.0)
		var desventa: float = 1.0 - clampf(factor_viento(), 0.0, 1.0)
		empuje -= cia_en_el_ojo * de_cara * desventa * Viento.fuerza * Viento.fuerza
	# **Empuje contra la resistencia del agua, que va con el CUADRADO de la velocidad.** Con los
	# dos en la misma escala la velocidad de régimen de cada rumbo con viento a favor es
	# exactamente `objetivo`, como antes; lo que cambia es cómo se llega. Antes era `move_toward` a
	# `aceleracion` constante, igual para frenar que para arrancar, y aproado a 1,4 m/s el casco se
	# paraba en 0,7 s: no había virada por avante posible con un casco que tarda en girar. Ahora sin
	# empuje pierde arrancada poco a poco (`v₀ / (1 + a·v₀·t / v_max²)`), y con todo el empuje
	# arranca a `aceleracion`.
	velocidad += aceleracion * (empuje - velocidad * absf(velocidad) / maxf(v2, 0.01)) * delta

	# **El barco CONSERVA su movimiento: el timón lo guía, no lo empuja.** La velocidad es un
	# vector con su propia inercia, no un escalar clavado a la proa. Cuando la proa gira, el
	# movimiento sigue un rato en la dirección de antes y aparece una componente de LADO — la
	# deriva — que la quilla va disipando en `resistencia_lateral` segundos. Eso es lo que hace que
	# la popa barra hacia fuera y que la estela salga curva en vez de doblar en escuadra.
	#
	# Sin esto el casco pivotaba: medido con `tools/gobierno.tscn`, **0,0° entre la proa y el
	# movimiento real** durante toda una virada, o sea que el vector velocidad saltaba a la proa
	# nueva cada paso. El usuario lo describió como "se ve como si el timón empujara en una
	# dirección", y es exactamente eso: un cambio instantáneo de dirección sin inercia parece un
	# empujón de lado.
	var proa_h := _proa_horizontal()
	var banda := Vector3(-proa_h.z, 0.0, proa_h.x)
	var v_plano := Vector3(velocity.x, 0.0, velocity.z)
	# El movimiento de antes, descompuesto en los ejes de AHORA: la parte de lado es la deriva que
	# el giro acaba de crear.
	var deriva: float = v_plano.dot(banda)
	deriva -= deriva * clampf(delta / maxf(resistencia_lateral, 0.01), 0.0, 1.0)
	velocity = proa_h * velocidad + banda * deriva
	move_and_slide()
	position.y = _altura_de_flotacion()
	_aplicar_inclinacion()
	_mover_tapa()


# ── Acciones (con señal para animar más adelante) ────────────────────────────
func set_vela_delantera(v: bool) -> void:
	if vela_delantera == v:
		return
	vela_delantera = v
	vela_delantera_cambiada.emit(v)
	_mandar_velas()
	print("Vela delantera: ", "abierta" if v else "cerrada")


func set_vela_trasera(v: bool) -> void:
	if vela_trasera == v:
		return
	vela_trasera = v
	vela_trasera_cambiada.emit(v)
	_mandar_velas()
	print("Vela trasera: ", "abierta" if v else "cerrada")


func set_ancla(v: bool) -> void:
	if anclado == v:
		return
	anclado = v
	ancla_cambiada.emit(v)
	print("Ancla: ", "soltada (detenido)" if v else "levada")


## Da la orden a cada vela según el estado de su puesto en el aparejo. El barco decide QUÉ
## velas van abiertas —eso es cosa suya: sabe cuál es la de proa y cuál la de popa— y la vela
## decide CÓMO se iza: qué drizas mueve, cuánto recorren y cuándo recoge el paño.
func _mandar_velas(inmediato := false) -> void:
	for v in _velas:
		var abierta := vela_trasera
		match int(v.get("mando")):
			0:
				abierta = vela_delantera
			2:
				abierta = vela_delantera or vela_trasera
		if abierta:
			v.izar(inmediato)
		else:
			v.arriar(inmediato)


# ── Física de vela ───────────────────────────────────────────────────────────
# Superficie de vela abierta → cuánto propulsa (0 = todo cerrado; ~1 = todo abierto).
func _factor_velas() -> float:
	var f := 0.0
	if vela_delantera:
		f += empuje_delantera
	if vela_trasera:
		f += empuje_trasera
	# Lona agujereada, perchas tocadas y jarcia segada: el aparejo empuja en proporción a lo que
	# le queda. Va AQUÍ y no en `factor_viento`, que es la curva del CASCO con el viento y la usa
	# el capitán para elegir rumbo: un aparejo roto no ciñe menos, empuja menos.
	return f * float(integridad.get("aparejo", 1.0))


## Superficie de vela útil, de 0 a ~1: la que está izada por lo que queda del aparejo. Es la que
## propulsa y escora.
func superficie_velica() -> float:
	return _factor_velas()


# La trasera abierta tiende a ORZAR (girar hacia el viento); la delantera a ARRIBAR
# (girar en contra). Con ambas se equilibra. Escala con la velocidad (el giro es
# consecuencia del movimiento).
## Velocidad de giro, en rad/s, que pide el balance de las velas.
func _sesgo_velas(vel_norm: float) -> float:
	var s := 0.0
	if vela_trasera:
		s -= 1.0   # popa → ORZA (gira hacia el viento)
	if vela_delantera:
		s += 1.0   # proa → ARRIBA (aleja del viento; ayuda a salir de la zona muerta)
	if absf(s) < 0.001 or vel_norm < 0.001:
		return 0.0
	var wind := Viento.direccion
	wind.y = 0.0
	if wind.length() < 0.001:
		return 0.0
	var src := (-wind).normalized()   # de dónde viene el viento
	var bow := -transform.basis.z
	bow.y = 0.0
	if bow.length() < 0.001:
		return 0.0
	bow = bow.normalized()
	# Ángulo con signo de la proa hacia el origen del viento.
	var ang := atan2(bow.x * src.z - bow.z * src.x, bow.dot(src))
	return clampf(ang, -1.0, 1.0) * s * sesgo_giro_velas * vel_norm


## Factor de propulsión [0..1] según el ángulo entre la proa y el viento. Público porque no
## solo lo usa la propulsión: el audio saca de él la cadencia del flameo (cuánto viento NO está
## aprovechando la vela).
## Propulsión [0..1] con el rumbo ACTUAL.
func factor_viento() -> float:
	return factor_viento_en(-transform.basis.z)


## Propulsión [0..1] de un rumbo CUALQUIERA. Se pregunta al barco y no se calcula fuera porque
## la curva es del CASCO —su `angulo_muerto` y su `angulo_optimo`, 40° y 95° en la balandra— y
## quien se la recalcule por su cuenta acabará creyendo que ciñe más de lo que el barco ciñe.
## Misma razón por la que el tiro se decide con `Canon.punto_de_caida()` y no con una parábola
## propia.
func factor_viento_en(rumbo: Vector3) -> float:
	var wind := Viento.direccion
	wind.y = 0.0
	if wind.length() < 0.001:
		return 0.0
	wind = wind.normalized()
	var fwd := rumbo
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return 0.0
	fwd = fwd.normalized()
	var cos_ang := fwd.dot(-wind)
	var cos_muerto := cos(deg_to_rad(angulo_muerto))
	var cos_optimo := cos(deg_to_rad(angulo_optimo))
	var t := clampf((cos_muerto - cos_ang) / (cos_muerto - cos_optimo), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ── Timón ────────────────────────────────────────────────────────────────────
# Eje: el hueso apunta hacia arriba siguiendo el codaste, así que la pala barre girando
# sobre su propio eje (Y local), igual que el hueso 'vela'.
func _preparar_timon() -> void:
	_skel = _buscar_skeleton(self)
	if _skel == null:
		return
	_timon_idx = _skel.find_bone(timon_hueso)
	if _timon_idx >= 0:
		_timon_reposo = _skel.get_bone_rest(_timon_idx).basis.get_rotation_quaternion()


func _mover_timon(delta: float) -> void:
	if _timon_idx < 0:
		return   # este barco no lleva timón riggeado
	# Mismas teclas que el giro del casco (A = babor, D = estribor). El signo va al revés
	# que allí: con la orientación del hueso, la pala tiene que caer a la misma banda hacia
	# la que vira el barco.
	# Andando por cubierta el barco no lee el teclado: la caña vuelve al centro en vez de
	# responder a las teclas de andar del personaje.
	# El signo va al revés que en el casco: con la orientación del hueso, la pala cae a la
	# misma banda hacia la que vira el barco.
	var giro := -orden_timon
	if timon_invertir:
		giro = -giro
	var objetivo := giro * deg_to_rad(timon_angulo_max)

	# Seguimiento suave: la caña va y vuelve al centro sin saltos.
	_timon_angulo = lerpf(_timon_angulo, objetivo, clampf(timon_suavizado * delta, 0.0, 1.0))
	_skel.set_bone_pose_rotation(_timon_idx, _timon_reposo * Quaternion(timon_eje.normalized(), _timon_angulo))


# ── Modo: gobernar ↔ andar por cubierta ──────────────────────────────────────
## Al pasar a andar, el personaje se instancia como HIJO del barco: así el barco lo lleva
## consigo cuando navega y cabecea, que es lo que un CharacterBody3D en espacio de mundo no
## hace solo. Aparece en `HelmPosition`, que es donde estaría el timonel.
## Necesita los colisionadores de cubierta: sin ellos no hay cubierta que pisar.
func alternar_modo() -> void:
	if _andando:
		_a_gobernar()
	else:
		_a_andar()


func _a_andar() -> void:
	if escena_jugador == null:
		escena_jugador = load(ruta_jugador) as PackedScene
	if escena_jugador == null:
		push_warning("%s: sin escena de personaje ('%s')" % [nombre, ruta_jugador])
		return
	_jugador = escena_jugador.instantiate() as CharacterBody3D
	add_child(_jugador)
	var base: Vector3 = helm_position.position if helm_position != null else Vector3(0, 2.0, 0)
	_jugador.position = base + Vector3.UP * altura_capsula
	var cam := _jugador.find_children("*", "Camera3D", true, false)
	if not cam.is_empty():
		(cam[0] as Camera3D).make_current()
	gobierno = false
	_andando = true
	print("%s: a cubierta, en %v (pulsa %s para volver al timón)"
		% [nombre, _jugador.position, OS.get_keycode_string(tecla_paseo)])


func _a_gobernar() -> void:
	if _jugador != null and is_instance_valid(_jugador):
		_jugador.queue_free()
	_jugador = null
	_al_agua = false
	gobierno = true
	if camara != null:
		camara.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_andando = false


# ── Colisionadores de cubierta ───────────────────────────────────────────────
func _montar_colisiones() -> void:
	_cuerpo_colisiones = StaticBody3D.new()
	_cuerpo_colisiones.name = "Colisiones"
	_cuerpo_colisiones.collision_layer = colision_capa
	_cuerpo_colisiones.collision_mask = 0
	add_child(_cuerpo_colisiones)

	# --- suelos: la malla tal cual
	var suelos := 0
	for nombre_malla in colision_mallas_suelo:
		var mi := _malla(nombre_malla)
		if mi == null or mi.mesh == null:
			push_warning("%s: no encuentro la malla de suelo '%s'" % [nombre, nombre_malla])
			continue
		var cs := CollisionShape3D.new()
		cs.name = "Suelo_" + nombre_malla
		cs.shape = mi.mesh.create_trimesh_shape()
		cs.transform = _relativo(mi)
		_cuerpo_colisiones.add_child(cs)
		suelos += mi.mesh.get_faces().size() / 3

	# --- casco: línea de regala por secciones
	var casco := _malla(colision_casco)
	if casco == null or casco.mesh == null:
		push_warning("%s: no encuentro el casco '%s'" % [nombre, colision_casco])
		return
	var tr := _relativo(casco)
	var vs: PackedVector3Array = casco.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var ps := PackedVector3Array()
	ps.resize(vs.size())
	var lo := Vector3.INF; var hi := -Vector3.INF
	for i in vs.size():
		var p := tr * vs[i]
		ps[i] = p
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	# Eje largo del casco (eslora) y eje transversal (manga), en el espacio del barco.
	var tam := hi - lo
	var eslora_z: bool = tam.z >= tam.x
	var largo: float = tam.z if eslora_z else tam.x
	var paso := largo / float(colision_secciones)
	var a0: float = lo.z if eslora_z else lo.x

	var hechas := 0
	var altos: Array[float] = []
	var mangas: Array[float] = []
	var centros: Array[float] = []
	var cubiertas: Array[float] = []
	for s in colision_secciones:
		var c := a0 + paso * (float(s) + 0.5)
		var alto := -INF
		for i in ps.size():
			var p := ps[i]
			var u: float = p.z if eslora_z else p.x
			if absf(u - c) <= paso * 0.5 and p.y > alto:
				alto = p.y
		if alto == -INF:
			continue
		var manga := 0.0
		for i in ps.size():
			var p := ps[i]
			var u: float = p.z if eslora_z else p.x
			if absf(u - c) <= paso * 0.5 and p.y > alto - 0.15:
				var lat: float = absf(p.x) if eslora_z else absf(p.z)
				manga = maxf(manga, lat)
		# Altura de cubierta: lo más alto por debajo de la regala y cerca de la crujía.
		var cub := -INF
		for i in ps.size():
			var p := ps[i]
			var u: float = p.z if eslora_z else p.x
			if absf(u - c) > paso * 0.5:
				continue
			var lat2: float = absf(p.x) if eslora_z else absf(p.z)
			if lat2 < manga * 0.6 and p.y < alto - 0.20 and p.y > cub:
				cub = p.y
		centros.append(c)
		altos.append(alto)
		mangas.append(manga)
		cubiertas.append(cub if cub != -INF else alto)
		hechas += 1
	_regala_centros = centros.duplicate()
	_regala_altos = altos.duplicate()
	_regala_eslora_z = eslora_z

	# --- borda (se puede pisar) y barrera invisible por encima
	var suelo_y: float = lo.y
	var mi_cub := _malla(colision_mallas_suelo[0]) if not colision_mallas_suelo.is_empty() else null
	if mi_cub != null and mi_cub.mesh != null:
		suelo_y = (_relativo(mi_cub) * mi_cub.mesh.get_aabb()).position.y
	# Rango que ya cubre la malla de cubierta: fuera de ahí hay que poner suelo.
	var cub_min := INF; var cub_max := -INF
	if mi_cub != null and mi_cub.mesh != null:
		var ab := _relativo(mi_cub) * mi_cub.mesh.get_aabb()
		cub_min = ab.position.z if eslora_z else ab.position.x
		cub_max = cub_min + (ab.size.z if eslora_z else ab.size.x)
	# --- la franja que ocupa la jarcia, para apartar la barrera de ella
	var jarcia_de := INF
	var jarcia_a := -INF
	var jarcia_lat := 0.0
	if colision_jarcia != "":
		for n in find_children(colision_jarcia, "MeshInstance3D", true, false):
			var mj := n as MeshInstance3D
			if mj.mesh == null:
				continue
			var cj := _relativo(mj) * mj.mesh.get_aabb()
			var u0: float = cj.position.z if eslora_z else cj.position.x
			var u1: float = u0 + (cj.size.z if eslora_z else cj.size.x)
			jarcia_de = minf(jarcia_de, u0)
			jarcia_a = maxf(jarcia_a, u1)
			var l0: float = cj.position.x if eslora_z else cj.position.z
			var l1: float = l0 + (cj.size.x if eslora_z else cj.size.z)
			jarcia_lat = maxf(jarcia_lat, maxf(absf(l0), absf(l1)))

	for i in hechas:
		var c: float = centros[i]
		var alto: float = altos[i]
		var manga: float = mangas[i]
		# Suelo donde la malla de cubierta no llega (proa y popa del casco).
		if (c < cub_min or c > cub_max) and manga > colision_grueso_borda:
			var y_cub: float = cubiertas[i]
			var ancho: float = maxf(manga * 2.0 - colision_grueso_borda, 0.2)
			var pos_s := Vector3(0.0, y_cub - 0.05, c) if eslora_z else Vector3(c, y_cub - 0.05, 0.0)
			var tam_s := Vector3(ancho, 0.10, paso) if eslora_z else Vector3(paso, 0.10, ancho)
			_caja(pos_s, tam_s, Basis(), "SueloCasco_%d" % i)
		if manga < colision_grueso_borda:
			continue          # proa y popa: la regala se cierra, no hay banda que levantar
		for lado in [-1.0, 1.0]:
			var lat: float = (manga - colision_grueso_borda * 0.5) * lado
			var pos_borda := Vector3(lat, (alto + suelo_y) * 0.5, c) if eslora_z else Vector3(c, (alto + suelo_y) * 0.5, lat)
			var tam_borda := Vector3(colision_grueso_borda, maxf(alto - suelo_y, 0.05), paso) if eslora_z else Vector3(paso, maxf(alto - suelo_y, 0.05), colision_grueso_borda)
			_caja(pos_borda, tam_borda, Basis(), "Borda_%d_%s" % [i, "b" if lado < 0.0 else "e"])
			# La barrera se aparta donde está la jarcia, o tapa la escala por la que se sube.
			var fuera: float = manga + colision_grueso_borda * 0.5 + colision_margen_barrera
			if jarcia_lat > 0.0 and c >= jarcia_de and c <= jarcia_a:
				fuera = maxf(fuera,
					jarcia_lat + colision_paso_jarcia + colision_grueso_borda * 0.5)
			if colision_alto_barrera <= 0.0:
				continue
			var lat2: float = fuera * lado
			var pos_bar := Vector3(lat2, alto + colision_alto_barrera * 0.5, c) if eslora_z else Vector3(c, alto + colision_alto_barrera * 0.5, lat2)
			var tam_bar := Vector3(colision_grueso_borda, colision_alto_barrera, paso) if eslora_z else Vector3(paso, colision_alto_barrera, colision_grueso_borda)
			_caja(pos_bar, tam_bar, Basis(), "Barrera_%d_%s" % [i, "b" if lado < 0.0 else "e"])

	# --- tapones de proa y popa: sin ellos se sale andando por el extremo
	var extremos: Array[int] = []
	for i in hechas:
		if mangas[i] >= colision_grueso_borda:
			extremos.append(i)
	if extremos.size() >= 2:
		for i in [extremos[0], extremos[extremos.size() - 1]]:
			var c: float = centros[i]
			var alto: float = altos[i]
			var manga: float = mangas[i]
			var hacia: float = -1.0 if i == extremos[0] else 1.0
			var cc: float = c + hacia * paso * 0.5
			var y_cub: float = cubiertas[i]
			var h: float = alto + colision_alto_barrera - y_cub
			var pos_t := Vector3(0.0, y_cub + h * 0.5, cc) if eslora_z else Vector3(cc, y_cub + h * 0.5, 0.0)
			var tam_t := Vector3(manga * 2.0, h, colision_grueso_borda) if eslora_z else Vector3(colision_grueso_borda, h, manga * 2.0)
			_caja(pos_t, tam_t, Basis(), "Tapon_%s" % ("proa" if hacia < 0.0 else "popa"))

	print("%s: %d triangulos de suelo, %d secciones, %d cajas (eslora en %s, suelo y=%.2f)"
		% [nombre, suelos, hechas, _cuerpo_colisiones.get_child_count() - colision_mallas_suelo.size(),
			"z" if eslora_z else "x", suelo_y])
	_montar_escalas(eslora_z)


## Levanta una `EscalaJarcia` por cada grupo de flechastes: por dónde se trepa.
##
## Todo sale de las mallas — la subida, de unir el peldano más bajo con el más alto; el lateral,
## del eje largo de un peldano; el ancho, del más largo de ellos —, así que cualquier casco que
## traiga jarcia tiene sus escalas sin escribir un número.
##
## El área es generosa a propósito (1,4 m de fondo): hay que poder engancharse desde la cubierta,
## desde la regala y desde fuera, y una caja pegada al plano de la jarcia obligaría a acertar.
func _montar_escalas(eslora_z: bool) -> void:
	for patron in colision_escalas:
		var nodos := find_children(patron, "MeshInstance3D", true, false)
		if nodos.size() < 2:
			continue
		var centros: Array[Vector3] = []
		var cajas: Array[AABB] = []
		for n in nodos:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var c := _relativo(mi) * mi.mesh.get_aabb()
			cajas.append(c)
			centros.append(c.get_center())
		if centros.size() < 2:
			continue
		var bajo := centros[0]
		var cima := centros[0]
		var ancho := 0.0
		for i in centros.size():
			if centros[i].y < bajo.y:
				bajo = centros[i]
			if centros[i].y > cima.y:
				cima = centros[i]
			# El eje largo del peldano: el mayor lado de su caja, que es el propio cabo.
			var t := cajas[i].size
			ancho = maxf(ancho, maxf(t.x, maxf(t.y, t.z)))
		var subida := (cima - bajo)
		if subida.length() < 0.5:
			continue
		var largo := subida.length()
		subida = subida.normalized()
		# Lateral: a lo largo de los peldanos, y perpendicular a la subida para que los dos ejes
		# no se pisen (un flechaste no es exactamente horizontal ni la escala exactamente vertical).
		var lateral: Vector3 = Vector3(0, 0, 1) if eslora_z else Vector3(1, 0, 0)
		lateral = (lateral - subida * lateral.dot(subida)).normalized()
		# Fuera: perpendicular al plano de la escala, hacia el costado por el que se trepa.
		var fuera := subida.cross(lateral).normalized()
		var hacia: float = bajo.x if eslora_z else bajo.z
		if fuera.dot(Vector3(hacia, 0.0, 0.0) if eslora_z else Vector3(0.0, 0.0, hacia)) < 0.0:
			fuera = -fuera
		var e := EscalaJarcia.new()
		e.name = "Escala_" + String(patron).replace("*", "").rstrip("_")
		e.dir_subida = subida
		e.dir_lateral = lateral
		e.dir_fuera = fuera
		e.alto = largo
		e.ancho = ancho * 0.5
		var cs := CollisionShape3D.new()
		var caja := BoxShape3D.new()
		caja.size = Vector3(ancho + 0.8, largo, 1.4)
		cs.shape = caja
		cs.transform = Transform3D(Basis(lateral, subida, fuera),
			subida * (largo * 0.5) + fuera * 0.2)
		e.add_child(cs)
		add_child(e)
		e.transform = Transform3D(Basis(), bajo)
		print("%s: escala '%s' de %.2f m, %.2f de ancho, sube (%.2f, %.2f, %.2f) desde y=%.2f"
			% [nombre, e.name, largo, ancho, subida.x, subida.y, subida.z, bajo.y])


## Da a la madera del modelo su relieve. Diferido como todo lo que toca las mallas del `.glb`,
## que no están en el árbol hasta después de `_ready`.
func _montar_acabado() -> void:
	var total := 0
	var mats := 0
	for a in acabado_madera:
		if a == null:
			continue
		var hechos: Dictionary = a.aplicar(self)
		for k in hechos:
			total += int(hechos[k])
		mats += hechos.size()
	if total > 0:
		print("%s: relieve de madera en %d mallas (%d materiales)" % [nombre, total, mats])


## Instancia los bultos del `cargamento` y los cuelga del barco, dentro de un contenedor.
##
## El contenedor no lleva script: solo agrupa, para que la raíz del barco no se llene de
## barriles entre las velas y la cámara. Se cuelgan DEL BARCO (y no del nodo `Modelo`) por lo
## mismo que el jugador al andar por cubierta: así se mueven con el casco al navegar.
##
## Los bultos que no se puedan instanciar se saltan con un aviso; a un barco al que le falte
## un `.glb` de carga le sobra motivo para seguir navegando.
func _montar_carga() -> void:
	var contenedor := get_node_or_null(^"Cargamento") as Node3D
	if contenedor == null:
		contenedor = Node3D.new()
		contenedor.name = "Cargamento"
		add_child(contenedor)
	var puestos := 0
	for c in cargamento:
		if c == null:
			continue
		var bulto := c.instanciar(colision_capa)
		if bulto == null:
			continue
		contenedor.add_child(bulto)
		puestos += 1
	print("%s: %d bultos de carga de %d" % [nombre, puestos, cargamento.size()])


func _caja(centro: Vector3, tam: Vector3, base: Basis, nombre_caja: String) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = tam
	cs.shape = bx
	cs.name = nombre_caja
	cs.transform = Transform3D(base, centro)
	_cuerpo_colisiones.add_child(cs)
	if colision_dibujar:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = tam
		mi.mesh = bm
		mi.transform = cs.transform
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.3, 0.1, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		_cuerpo_colisiones.add_child(mi)


# ── Utilidades ───────────────────────────────────────────────────────────────
## Transform de un nodo respecto al barco, sin depender de global_transform.
func _relativo(n: Node) -> Transform3D:
	var t := Transform3D(); var x := n
	while x != null and x != self:
		if x is Node3D: t = (x as Node3D).transform * t
		x = x.get_parent()
	return t


func _malla(nombre_malla: String) -> MeshInstance3D:
	var l := find_children(nombre_malla, "MeshInstance3D", true, false)
	return l[0] as MeshInstance3D if not l.is_empty() else null


func _buscar_skeleton(raiz: Node) -> Skeleton3D:
	if raiz == null:
		return null
	for c in raiz.find_children("*", "Skeleton3D", true, false):
		return c as Skeleton3D
	return null


func _buscar_camara() -> Camera3D:
	var c := get_node_or_null(camara_path) as Camera3D
	if c != null:
		return c
	var l := find_children("*", "Camera3D", true, false)
	return l[0] as Camera3D if not l.is_empty() else null


## El personaje se ha caído al mar: deja de colgar del barco.
##
## Va a bordo como HIJO del casco para que la cubierta lo arrastre al navegar — un
## `CharacterBody3D` vive en espacio de mundo y no sigue a su padre por su cuenta —, y eso mismo
## es lo que sobra en el agua: colgando del barco, el náufrago viajaría con él a nueve nudos.
## `reparent` conserva la posición de mundo, así que cae donde cayó.
##
## `_jugador` se mantiene apuntando a él a propósito: el barco sigue en modo "a pie" y F sigue
## devolviendo el timón, que es la salida si uno se queda flotando lejos.
func hombre_al_agua(jug: Node3D) -> void:
	if jug == null or jug.get_parent() != self:
		return
	var mundo := get_parent()
	if mundo == null:
		return
	jug.reparent(mundo, true)
	_al_agua = true
	print("%s: hombre al agua en %v" % [nombre, jug.global_position])


## Vuelve a bordo al que se cayó, o el enganche de siempre si ya estaba en cubierta.
##
## Se entra por el rayo de interacción del propio personaje (su `collision_mask` incluye la capa
## del casco), así que basta nadar hasta el costado y mirar al barco.
func on_interact(player: Node3D) -> void:
	if _al_agua and player != null and player == _jugador:
		player.reparent(self, true)
		var base: Vector3 = helm_position.position if helm_position != null else Vector3(0, 2.0, 0)
		(player as Node3D).position = base + Vector3.UP * altura_capsula
		_al_agua = false
		print("%s: el náufrago vuelve a bordo" % nombre)
		return
	# Punto de enganche para cuando el jugador suba al timón.
	print("El jugador subió al timón del barco.")


# ── Artillería ───────────────────────────────────────────────────────────────

## Instancia las piezas y las cuelga del barco, dentro de un contenedor, igual que la carga:
## del BARCO y no del nodo `Modelo`, para que naveguen y cabeceen con el casco.
func _montar_artilleria() -> void:
	var contenedor := get_node_or_null(^"Artilleria") as Node3D
	if contenedor == null:
		contenedor = Node3D.new()
		contenedor.name = "Artilleria"
		add_child(contenedor)
	_canones.clear()
	for a in artilleria:
		if a == null:
			continue
		var c := a.instanciar()
		c.altura_mar = _altura_del_mar()
		c.municion = Municion.de(municion_actual)
		contenedor.add_child(c)
		_canones.append(c)
	if get_node_or_null(^"GuiaTiro") == null and not _canones.is_empty():
		var g := GuiaTiro.new()
		g.name = "GuiaTiro"
		add_child(g)
	print("%s: %d piezas de artillería (%d por banda)"
		% [nombre, _canones.size(), canones_de("estribor").size()])


## Las piezas de una banda. Se pregunta al cañón en vez de guardar dos listas: una sola fuente.
func canones_de(que_banda: String) -> Array[Canon]:
	var sale: Array[Canon] = []
	for c in _canones:
		if c.banda() == que_banda:
			sale.append(c)
	return sale


## Dispara la banda apuntada. Devuelve cuántas piezas llegaron a responder: las que estén
## recargando no salen, y eso es información para el HUD.
func disparar_banda() -> int:
	var salieron := 0
	for c in canones_de(banda_apuntada):
		if municion <= 0:
			break
		if c.disparar():
			salieron += 1
			municion -= 1
	return salieron


## La llama la BALA al alcanzar cualquier cuerpo de este barco (misma convención que la boya y que
## `on_interact`). El modelo de daños vive en `Averias`.
func recibir_impacto(donde: Vector3, _energia: float, quien: Node) -> void:
	if _averias != null:
		_averias.recibir(donde, quien)


## Si este barco tiene DIANAS: su casco y su cubierta como cuerpo de colisión propio. Con ellas la
## bala se salta la caja del `CharacterBody3D`, que lleva dentro el aire de las esquinas.
func tiene_dianas() -> bool:
	return _dianas != null


func vias_de_agua() -> int:
	return _averias.vias.size() if _averias != null else 0


func vias_en(zona: String) -> int:
	return _averias.vias_en(zona) if _averias != null else 0


## Deja el barco como salió del astillero: todas las zonas sanas, sin vías, seco y sin agujeros.
func reparar() -> void:
	if _averias != null:
		_averias.reparar()


## La zona que tocaría un impacto en `donde` contra el cuerpo `cuerpo` (ver `Averias.zona_de`).
func zona_de(donde: Vector3, cuerpo: Object = null) -> String:
	return _averias.zona_de(donde, cuerpo) if _averias != null else ""


## Las dianas: el casco y las mallas de cubierta tal cual, como cuerpo estático en la capa 8. Son
## las mismas mallas con las que se levantan las colisiones de cubierta, así que no hay que
## escribir una forma a mano para ningún barco que ya se pueda pisar.
func _montar_dianas() -> void:
	var mallas: Array[String] = [colision_casco]
	mallas.append_array(colision_mallas_suelo)
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Dianas"
	cuerpo.collision_layer = CAPA_DIANAS
	cuerpo.collision_mask = 0
	var hay := 0
	for nombre_malla in mallas:
		var mi := _malla(nombre_malla)
		if mi == null or mi.mesh == null:
			continue
		var cs := CollisionShape3D.new()
		cs.name = "Diana_" + nombre_malla
		cs.shape = mi.mesh.create_trimesh_shape()
		cs.transform = _relativo(mi)
		cuerpo.add_child(cs)
		hay += 1
	if hay == 0:
		cuerpo.free()
		return
	add_child(cuerpo)
	_dianas = cuerpo


## Altura de la regala bajo un punto del mundo, interpolando la línea que se muestreó al
## levantar las colisiones. Sin colisiones montadas devuelve -INF, que es lo honesto: no se
## sabe, en vez de inventar un cero que pasaría por bueno en una comprobación.
func altura_regala_en(pos_global: Vector3) -> float:
	if _regala_centros.is_empty():
		return -INF
	var p := to_local(pos_global)
	var u: float = p.z if _regala_eslora_z else p.x
	var mejor := 0
	var dist := INF
	for i in _regala_centros.size():
		var d: float = absf(_regala_centros[i] - u)
		if d < dist:
			dist = d
			mejor = i
	# En GLOBAL: los altos se muestrearon en el espacio del barco y quien pregunta trae
	# posiciones del mundo. Devolverlo en local es comparar peras con manzanas.
	return to_global(Vector3(0.0, _regala_altos[mejor], 0.0)).y


## Banda apuntada y fuego. Van por `match` aparte y no dentro del de las velas para que la
## artillería no se mezcle con la maniobra: son dos cosas distintas y se leen mejor separadas.
## Elige a qué batería se apunta: "proa", "popa", "babor" o "estribor".
func apuntar(que_banda: String) -> void:
	if _canones.is_empty():
		return
	banda_apuntada = que_banda


## Puntería fina de la batería apuntada, EN GRADOS: `dgiro` mueve las piezas con el espeque y
## `delev` mete o saca la cuña. Se dan incrementos y no valores absolutos porque así sirve igual
## al ratón (que da movimiento relativo) y a un capitán de IA corrigiendo el tiro.
func apuntar_fino(dgiro: float, delev: float) -> void:
	for c in canones_de(banda_apuntada):
		# Los topes son de la PIEZA, no de aquí: es su afuste el que los pone, y escritos en dos
		# sitios uno de los dos se queda atrás.
		c.giro_lateral = clampf(c.giro_lateral + dgiro, -Canon.ESPEQUE_MAX, Canon.ESPEQUE_MAX)
		c.elevacion = clampf(c.elevacion + delev, Canon.ELEVACION_MIN, Canon.ELEVACION_MAX)


## Puntería de la batería apuntada, para el HUD: grados de espeque y de cuña, y el alcance que
## sale de ellos. Se lee de la PRIMERA pieza; van todas a la vez.
func punteria() -> Dictionary:
	var piezas := canones_de(banda_apuntada)
	if piezas.is_empty():
		return {}
	var p: Canon = piezas[0]
	return {"lateral": p.giro_lateral, "elevacion": p.elevacion,
		"alcance": p.punto_de_caida().distance_to(p.global_position),
		"listas": piezas.filter(func(x: Canon): return x.listo()).size(),
		"total": piezas.size()}


## Dónde está la lámina de agua. Con `altura_mar` puesto a mano manda ese valor; si no, se
## busca el agua en la escena por su grupo o por su nombre. Devolver 0 a ciegas haría que el
## tiro cayese donde no es en cuanto el mar no esté en el cero.
func _altura_del_mar() -> float:
	if is_finite(altura_mar):
		return altura_mar
	var agua := get_tree().get_first_node_in_group("mar") as Node3D
	if agua == null:
		var raiz := get_tree().current_scene
		if raiz != null:
			agua = raiz.find_child("Water", true, false) as Node3D
	if agua != null:
		return agua.global_position.y
	# Devolver 0 en silencio es lo que hace que una herramienta mida OTRO juego: en esta
	# balandra el mar está en −0,882, así que un cero deja la lámina medio metro por encima de
	# la boca y el alcance cae de 62,7 m a 41,9. Se avisa para que se ponga `altura_mar` a mano.
	push_warning("%s: no encuentro el agua; el tiro se calculará con el mar en 0. "
		% nombre + "Pon `altura_mar` a mano si el barco va en una escena sin mar.")
	return 0.0


## Le pone al barco el mando del JUGADOR: teclado y ratón traducidos a órdenes. Lo llama quien
## sabe que este barco es el del jugador —el `GestorBarcos` al instanciarlo, o una herramienta
## de pruebas—, nunca el barco por su cuenta: dos balandras instanciadas a mano entran las dos
## en el grupo "barco_activo", así que ese criterio no distingue.
func tomar_mando_jugador() -> MandoJugador:
	var ya := get_node_or_null(^"MandoJugador") as MandoJugador
	if ya != null:
		return ya
	var m := MandoJugador.new()
	m.name = "MandoJugador"
	add_child(m)
	# El grupo va con el mando: el barco del jugador es el que lleva jugador. Así el mar, el
	# HUD, la cámara y las flechas siguen encontrándolo sin rutas fijas, y ningún enemigo puede
	# reclamar el puesto por el mero hecho de existir.
	add_to_group("barco_activo")
	return m


## Quién lleva el timón, si es que alguien lo lleva. La guía de tiro lo usa para saber si debe
## dibujarse: sin nadie al mando no hay a quien enseñársela.
func hay_mando() -> bool:
	return get_node_or_null(^"MandoJugador") != null

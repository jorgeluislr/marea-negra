# Balandra — documento de diseño

Ficha viva de la balandra de *Marea Negra*. Cada decisión de diseño se anota aquí con su
motivo. Si algo del modelo no coincide con este documento, **manda el documento**: se corrige
el modelo, no la ficha.

---

## 1. Época y tipo de barco

**Época elegida: 1700 – 1730.** La edad de oro de la piratería en el Caribe va de ~1650 a
~1730, y su auge real es el periodo posterior a la Guerra de Sucesión Española,
**1716 – 1726**: Barbanegra muere en 1718, Bartholomew Roberts en 1722, y hacia 1726 la
campaña de la Royal Navy había acabado con los últimos.

**Tipo: balandra de Bermudas / de Jamaica** (*Bermuda sloop*), c. 1700-1730. Es el barco
pirata característico del Caribe, y no por casualidad: un palo, aparejo de cangreja, botalón
largo, poco calado, y capaz de ceñir mejor y correr más que casi cualquier presa o
perseguidor. Nada de galeones — eso es otra cosa y otro siglo.

Consecuencias que se aplican en todo el barco:

- **No existe** cable de acero, tensor de rosca, cadena de barbiquejo (llega hacia 1780),
  acero inoxidable, enrollador ni aluminio.
- Todo el cabo es **cáñamo**. La jarcia firme va **alquitranada** (oscura); la de labor,
  **sin alquitranar** (rubia).
- Los herrajes son de **hierro forjado**, no fundido ni galvanizado.
- La tensión de la jarcia firme se da con **vigotas y acolladores**, nunca con tornillo.

---

## 2. Casco

| Dato | Valor | Nota |
|---|---|---|
| Eslora | **12,00 m** | de roda a codaste |
| Manga | 3,81 m | máxima |
| Alto de la borda | 2,06 – 2,36 m | sube hacia popa |
| Cubierta | 1,766 m | quilla en z = 0 |
| Material | **cedro de Bermudas** | ligero e imputrescible |

Origen: generación propia de Meshy, retopologizada. LOD0 en 24 192 tris, con decimado 0,8
sobre la obra viva.

---

## 3. Arboladura

| Percha | Largo | Ángulo | Posición | Material |
|---|---|---|---|---|
| Mástil | 8,65 m (8,47 sobre cubierta) | 9,3° a popa | 4,84 m de la roda = **0,403 · eslora** | pino, palo entero |
| Botavara | **6,99 m** | 5,3° a subir | garganta a 2,50 m | pino |
| Pico | 4,20 m | **25°** | garganta a 8,35 m | pino |
| Botalón | 4,91 m | **12,2° a subir** | 3,10 m fuera de la roda = 0,258 · eslora | pino |

Decisiones:

- **El mástil está bien donde está.** Medido contra la referencia: 0,403 de la eslora contra
  0,407. No se mueve.
- **La garganta del pico va alta** (0,77 del palo sobre cubierta) y el **pico tendido a 25°**
  para que su punta quede en 10,00 m, justo bajo el tope (10,24). Con la garganta baja que
  tenía antes, la mayor solo ocupaba el 45 % del palo y quedaba raquítica.
- **La botavara acaba en x = 6,05**, justo pasado el codaste (5,999) y sobre el timón, y sube
  5,3° para librar la **caña del timón** por 21,9 cm. Antes la atravesaba.
- **El botalón se apoya en la cabeza de roda, no encima de ella.** Medido en el modelo de
  referencia, su botalón peina 12,2°; el nuestro va ahora igual. Con esa inclinación el palo
  cruza la borda a la altura de la tapa de regala (x −5,5 a −6,0) y su mitad baja queda dentro
  de la madera de la roda, que es lo que le da el aspecto de ir encajado. **No hace falta
  almohada**: la almohada se puso cuando el palo pasaba por encima de la roda, y se ha retirado.
- **El talón lo sujetan dos bitas y la cabilla**, no un calzo. Acaba en x = −4,30, a 24 cm sobre
  la cubierta de proa (z 1,96), abrazado por dos postes en x −4,62 a −4,46 que suben hasta
  z 2,56, con la **cabilla** atravesándolo a 24 cm de su extremo (1,4 diámetros — menos, y la
  madera se raja).
- **La trinca va donde el palo cruza la madera** (x −5,80), con el **tope** 20 cm por delante
  (x −6,00) para que la trinca no resbale por la conicidad. Puesta más a proa no ata nada.
- El casco **no se corta** para alojar el palo. Se probó cortar la corona de la roda para hacerle
  un asiento limpio y se descartó: el palo ya queda medio enterrado en ella y no se ve el cruce.

---

## 4. Velamen

| Vela | Área | Lados (m) | % del total |
|---|---|---|---|
| Mayor (cangreja) | **33,42 m²** | gratil 5,76 · pujamen 6,75 · cabeza 4,09 · baluma 7,10 | 73,2 |
| Foque (yankee) | **12,25 m²** | gratil 8,10 · pujamen 4,57 · baluma 5,53 | 26,8 |
| **Total** | **45,67 m²** | SA / eslora² = **0,317** | rango real 0,25-0,40 ✔ |

- El foque es un **yankee**, de puño de escota alto (104,8°), que es el que llevan los cúters
  con botalón largo para que el pujamen no barra el palo.
- **J = 8,19 m = 0,68 de la eslora.** Ese triángulo de proa es de cúter: lo real sería
  repartirlo en dos velas (trinquetilla + foque). Decisión tomada: **una sola vela de proa**,
  y se acepta que quede pequeña para su base.
- Malla de cuadriláteros regulares (32×32 la mayor tras subdividir — 2 560 tris; 8×18 el foque)
  para poder deformarla. El foque acaba en **punta**, con 8 triángulos en el puño de driza.
- **La baluma va recta.** Se le puso el hueco de −5 % que tiene la referencia y no se leía bien,
  así que se deshizo (residuo de 3,9 cm). La curvatura de la vela se hará **en el juego**, con el
  esqueleto y el shader, no en la malla.
- **La barriga imita la de la referencia: 2,6 % de la cuerda de media, y con el signo
  alternando.** Medida en su modelo por bandas de altura sale +8,8 / −14,4 / +8,0 / +11,3 /
  +12,0 / +10,2 / +8,7 cm — o sea que su vela **no tiene una barriga limpia, ondula**. Eso es
  lo que la hace parecer tela y no plancha, más que la profundidad. La nuestra reproduce el
  efecto con una barriga floja más tres ondas de 1,7 a 3,1 m, y sale −13,5 / −16,5 / −17,3 /
  −14,4 / −14,0 / +13,4 / +13,8 / −13,4 cm, media 2,6 % contra su 2,5 %.
- La envolvente vale **cero exacto** en los tres cantos cosidos a percha (comprobado: 0,00 mm
  en gratil, pujamen y cabeza), así que los aros siguen encajados sin tocarlos.

### Su pujamen va empalomado, como el nuestro

Se midió un supuesto hueco de −9,8 % en el pujamen de la referencia y **era un artefacto**: la
caja con la que se recortó su vela (z > 2,40) le cortó el pie y el corte se leyó como un arco.
En el render de cerca se ve que su pujamen va **empalomado a la botavara con vueltas de cabo a
lo largo de todo el palo**, igual que el nuestro con aros. No se toca el pujamen ni se quitan
los aros, y **la balandra no es de vela suelta**.

Moraleja para la próxima: antes de sacar una conclusión de una malla recortada, comprobar que el
recorte no toca los límites de la caja. El indicador estaba a la vista — la caja iba de 2,40 y
la tela llegaba a 2,382.

### Lona horneada de la referencia

`lona_hornea`, 4096² (1,88 mm por texel), en la UV `UVHorneado` — que es la `UVMap` en metros
normalizada al mismo dominio de 7,70 m que las arrugas. No es baldosa: cubre la vela entera una
sola vez.

Cómo se hizo, que es lo reutilizable:

1. Aislar su paño **por color del atlas**, no por caja: se muestrea `base_color` en la UV de cada
   vértice y se queda con luminancia > 0,45. La madera está en 0,09-0,36 y la lona en 0,45-0,60,
   así que separa limpio. Con el filtro por caja entraba pico y mástil, y horneaba madera en la
   cabeza de la vela.
2. **Homografía de sus cuatro puños a los nuestros** en el plano xz — no hace falta retopología.
   Las esquinas del cuadrilátero se buscan en coordenadas **normalizadas**: con las crudas, su
   pico y su garganta salían el mismo punto (su pico va casi horizontal) y la homografía se iba
   a 10⁶.
3. Su paño se pega a nuestra superficie evaluando nuestra barriga y(u,v) con un polinomio, y se
   hornea *selected to active* con 30 cm de distancia de rayo.
4. Los huecos que quedan (4 %) se rellenan en **dos escalas con interpolación lineal** más el
   grano de una zona buena. Con relleno por pirámide y vecino más cercano salen cuadros.
5. El nivel se baja **×0,158** — su textura está pintada a 0,62 de luminancia lineal y esta
   escena espera 0,047 — y luego ×1,71 para el blanco quemado. Su contraste fino se sube **×2,3**
   porque el especular y el 28 % de translúcido meten un término plano que se lo come.

Nuestra lona propia (paños, puntadas, falso y arrugas) sigue en el archivo como `lona_vela` con
usuario falso: se vuelve a ella cambiando el material de la vela.

### Lona

Lino (*duck*) cosido en paños. Reglas del material:

- **Paño liso.** Ni tonos por paño ni puntadas: solo color, moteado y la unión. La versión con
  paños de 47 / 56 / 49 cm y puntadas en diagonal está aparcada — sus números quedan más abajo.
- **El paño no lleva costura ninguna.** La costura va **solo en el falso**.
### El falso: por densidad, no por relieve

Un falso se llama **tabling**: el canto de la vela doblado y cosido, que es lo que refuerza el
paño para coser la relinga. **Sin geometría añadida** — la vela es un plano de 1 217 vértices y
1 152 caras, y así se queda.

**El número que zanja el asunto.** El falso emula unos 2 mm de espesor. A 3 m con un 60 mm el
encuadre son 1,80 m sobre 1 500 px, o sea **1,2 mm por píxel**: esos 2 mm son **1,7 píxeles**. Ni
normales, ni geometría, ni paralaje pueden hacer que se lea como volumen algo que mide píxel y
medio. Se probaron las tres — lomo de normales, surco más rampa, y una tira aparte de 512 tris a
2 mm — y ninguna da la sensación de capa, porque el problema no es la técnica sino la escala.

Lo que **sí** se lee a distancia de juego es el **ancho** de la banda (8 cm = 67 px a 3 m) y su
**línea de canto**. Así que el falso se distingue por lo que físicamente lo distingue:

- **Traspasa menos luz, porque son dos capas de tela.** El translúcido va a **0,28 en el paño y
  0,11 en el falso**, con la máscara verde de `Col` gobernando el `Mix Shader`. A contraluz la
  banda se ve claramente más oscura, que es la señal más honesta y la que funciona a cualquier
  distancia. Es la única de todas las pruebas que se nota sin acercarse.
- **La banda, un 4,5 % más densa** en el color; el paño doblado pesa más.
- **Línea de canto al 30 %** en el punto donde acaba el doblado, con 0,55 mm de surco en
  normales. Una línea sí se lee a 1,2 mm por píxel; un espesor no.

**Dos costuras, no una**, que es como se cose un tabling: la **plana** por dentro (v = 0,925) y la
**redonda** dando la vuelta al canto exterior (v = 0,045), donde va la relinga, desfasadas medio
paso. **2 puntadas por pulgada = 12,61 mm**, lo que especifica Steel para forros y falsos: 47 por
baldosa, así que el paso divide la baldosa y sigue siendo cíclico. Hilo de 8 mm en la plana y
9,5 mm en la redonda. La costura hunde el paño 0,28 mm a los lados del hilo (que resalta 0,38 mm)
y añade **frunces** de 0,16 mm con el paso de la puntada.

En la tira, **v = 0 es el borde exterior de la vela y v = 1 el canto de dentro** — medido
comparando los vértices del borde de malla con su `UVFalso` (salen todos en v = 0,004), no
supuesto. La primera vez se puso la puntada en el centro por no mirar esto.

**Y una trampa de la escena**, por si algún día hace falta una sombra de contacto pequeña: los dos
soles tenían `shadow_filter_radius = 1`, que difumina la sombra un píxel y **borra cualquier
contacto de 2 mm**. Está a 0, con `shadow_ray_count` a 4 y `shadow_step_count` a 12.

### El paño es `hessian_380` recoloreado, en tres escalas

La trama sale de **`hessian_380`** de Poly Haven (CC0, baldosa de **27,39 cm**), en
`fuentes/blend/tex/hessian_380/`. Se usa **recoloreada**: se le toma la luminancia y se multiplica
por nuestro blanco amarillado, así que del original queda el tejido y no el marrón de yute.

Y el hallazgo que importa: **a su escala real la trama no llega al juego.** Son 0,134 mm por
texel, así que pasados unos 40 cm de cámara el mipmap la promedia y el paño sale liso. Un escaneo
de 27 cm es material de primer plano. Por eso la lona va en **tres escalas a la vez**:

| Capa | Baldosa | Para qué |
|---|---|---|
| `hessian_380` recoloreado | 27,39 cm | el tejido, de cerca (< 1 m) |
| `lona_moteado` | 1,521 m, celdas de 8,5 mm | el moteado, que es lo que se ve a 3-25 m |
| `lona_manchas` | 5 m | la variación de gran escala |

Medido en render: detalle fino **7,97 %** a 1 m y **2,01 %** a 4 m. Sin la capa de moteado, a 4 m
no queda nada.

### Calibrada contra la lona de la referencia

La lona del modelo de Meshy se midió en render plano sin luz (Workbench FLAT + TEXTURE), a
2,2 mm/px. Lo que dio, y lo que se copió:

| Medida | Referencia | Nuestra |
|---|---|---|
| Color base | sRGB 0,871 / 0,816 / 0,732 | subido a **blanco amarillado**: en render 0,926 / 0,894 / 0,800 |
| Tono (lineal, respecto al verde) | 1,16 · 1 · 0,785 | ajustado por ganancia por canal medida en render |
| Grano fino (σ / media) | **4,0 %** | 11,5 % → **4,2 %** |
| Tamaño del grano | moteado de **8 mm** | era trama de 3 mm → moteado de 8,5 mm |
| Variación lenta | 2,0 % | 2,7 % |

El grano se rebajó **sin borrar las puntadas**: se atenúa solo la desviación pequeña
(< 0,027 lineal) y se conserva la grande, que es la del hilo. Atenuar todo por igual apaga la
costura, que es justo lo que se quería ver.

Ojo con una trampa de este proyecto: el sol va a 600 W/m² con exposición −4,3 EV, así que la
lona se pinta oscura (el mapa está en 0,29 de 1,0) y la luz la sube ×1,5. Eso deja la textura
usando un tercio del rango de 8 bits, con la pérdida de tono que eso supone. Si algún día se
recalibra la escena, la lona se repinta al nivel real.

### El color se ajusta midiendo el render, no la textura

El tono de la textura no predice el del render: entran el especular, el 28 % de translúcido y la
luz del cielo. El método que funciona es **renderizar un primer plano de paño, medir la mediana
y aplicar la ganancia por canal en lineal** — dos iteraciones bastan. Ajustar mirando la textura
dejó la vela 8 % oscura y fría.

### Dónde están las texturas

Las que usa el barco ahora: `fuentes/blend/tex/` (y empaquetadas dentro del `.blend`).

Las versiones anteriores, rescatadas de los respaldos a `fuentes/blend/tex/historico/`:

| Archivo | Qué es |
|---|---|
| `lona_panos__con_puntadas_1540.png` | 2048², paños de 47/56/49 cm con sus tonos y **puntadas en diagonal**. Detalle fino 11,5 % |
| `lona_baldosa_color__baldosa_1139.png` | 1024², la lona **anterior** a los paños, de cuando la baldosa era otra. Detalle fino 11,3 % |
| `lona_panos.png` (en `tex/`) | la actual: paño liso en blanco amarillado, detalle fino 4,2 % |

### Las texturas generadas se pierden: hay que darles archivo

`lona_arrugas`, `lona_panos` y `lona_manchas` aparecieron un día con su contenido original,
perdiendo horas de graduado, y el mayor salió **negro** — un mapa de normales en negro apunta
hacia atrás. Una imagen creada con `images.new()` vive en memoria y no es de fiar.

Ahora las doce texturas tienen archivo en `fuentes/blend/tex/` y van **empaquetadas**. Y ojo con
la trampa: **`Image.reload()` en una imagen empaquetada restaura el paquete, no el archivo del
disco**, así que `save()` seguido de `reload()` deshace lo que acabas de escribir. El orden
correcto es: `unpack(REMOVE)` → escribir píxeles → `save()` → `pack()`. Nunca `reload()`.

### Arrugas (aparcadas)

Están hechas y desconectadas: los nodos siguen en `lona_vela` pero la normal va directa de los
paños y el color no pasa por la oclusión. Se reconectan enlazando `arr_cod` al mapa de normales y
`mul_arrugas` al color base.

Mapa propio, `lona_arrugas` de 2048², **no es baldosa**: cubre un dominio de 7,70 m que
contiene la vela entera, con extensión EXTEND, así que cada vela tiene sus arrugas y no repiten.
Lleva la normal en RGB y la oclusión en el alfa.

- 19 pliegues en abanico desde los **cuatro puños** — 7 desde el de escota, que es el que más
  arruga, 5 desde la amura, 4 desde la garganta, 3 desde el pico — más **4 caídas largas** casi
  paralelas a la baluma.
- Cada pliegue **vale cero en el puño**, crece en los primeros 20 cm y se apaga con la
  distancia: `A · s/(s+0,18) · (1−s/L)^1,15`. Una arruga que empieza con toda su profundidad en
  la esquina se lee como un pinchazo, no como un pliegue.
- Profundidad ≤ 10 mm, pendiente 11° (p99,9) y 16,5° máxima; oclusión ≤ 10 %. Con oclusión más
  fuerte parecen manchas.
- Se combina con la normal de los paños en tangente por **whiteout** (las x e y se suman, la z se
  multiplica), no por mezcla: mezclar promedia y se pierden las dos.

---

## 5. Jarcia firme y de labor

| Pieza | Cantidad | Cómo se toma |
|---|---|---|
| Obenques | 3 por banda | vigota y acollador sobre **mesa de guarnición**, con cadena de hierro forjado al costado |
| Estay de proa | 1 | del tope al **herraje del botalón**, 25 cm por dentro de la punta |
| Barbiquejo | 1 | de la punta del botalón a la roda |
| Barbiquejos laterales | 2 | de la punta del botalón a los costados de proa |
| Flechastes | 13 por banda | entre obenque de proa y medio |

Amarres de flechaste: sección triangular con el **vértice hacia dentro** (un aro pegado al
obenque y dos por fuera), camino de 8 lados, mordiendo 1 mm el obenque.

**Alquitranado, aplicado de verdad.** La regla estaba escrita desde el principio y la jarcia
seguía rubia. Hay dos materiales: `cabo_envejecido` (rubio, sin alquitranar) y
`cabo_alquitranado` (× 0,42 · 0,37 · 0,32 sobre el color base). Van alquitranados **47 objetos**
— estay, barbiquejo, los dos laterales, los seis obenques, los 26 flechastes con sus nudos y los
acolladores. Siguen rubios los de labor: escotas del foque, racamentos de botavara y pico, la
trinca del botalón y el amarre del pie del mástil.

### Cómo se amarra un cabo grueso: gaza y trinca

Los cabos llegaban a los cáncamos y se quedaban ahí por arte de magia. Un cabo de este grosor se
amarra formando una **gaza**: el chicote pasa por el hueco del herraje — entra por un lado y sale
por el otro —, vuelve sobre el firme y se **trinca** contra él.

**El patrón bueno lo modeló el usuario**, en `gaza_vigota_bq`: **367 tris, 168 vértices**, dos
componentes (el lazo y la trinca). Las otras seis se generan **copiándolo**, no regenerándolas.

Lo que corrigió y hay que respetar: **el lazo envuelve la vigota por el grueso de su canto**, no
alrededor de su diámetro. Medido en su malla, la caja local va de −14,8 a +2,2 cm en la dirección
del cabo, ±3,4 cm en el plano del disco y **±5,7 cm en la normal del disco** — o sea que el plano
del lazo contiene la normal de la vigota. Es lo que hace un cabo metido en la **garganta** del
canto, y era el error de mis cuatro intentos: yo lo enrollaba en el plano del disco.

**Cómo se copia.** Se extraen las coordenadas del patrón en el marco de su herraje —
`[d, w, d×w]` con `d` = dirección del cabo hacia el herraje y `w = n_disco × d` — y se vuelven a
plantar en el marco del destino. Escala 1,0 en los cabos de 44 mm y **0,71** en el estay, que es
de 31 mm.

**Cómo se replica el patrón, y cómo NO.** El marco se saca de la **geometría del propio patrón**,
no de dónde esté colocado: PCA sobre sus vértices da el eje largo `a1` y el fino `a3`, el sentido
de `a1` se decide por qué mitad se abre más en `a3` (esa es la del lazo), y se coloca haciendo
coincidir su punto más avanzado con el centro del herraje más 2,2 cm. Así da igual dónde viva la
malla.

Intentarlo al revés — deducir el marco de la posición del objeto — costó tres pasadas y se llevó
el patrón por delante: la función de copia borra el objeto destino antes de escribir, y para la
vigota `bq` **el destino era el propio patrón**. Sobrevivió como malla huérfana, pero las
colocaciones ya hechas heredaron el error y quedaron a 5,5 m del herraje. Dos reglas de aquí:

- Nunca escribir sobre el objeto que se está usando como fuente: copiar su malla a un datablock
  aparte con usuario falso **antes** de empezar.
- Verificar cada colocación con tres números, no a ojo: **cos_pata ≈ 1** (las patas siguen el
  cabo), **cos_plano = 1** (el plano del lazo contiene el eje del aro o la normal del disco) y
  **corona a 0 cm** del herraje. Con esos tres se detecta al instante un giro de 180° o un plano
  cambiado, que es lo que pasó cuatro veces.

**El marco no es el mismo en la vigota que en el aro de hierro.** El plano del lazo es el que
contiene `d` y `d×w`, así que hay que elegir `w` según por dónde tiene que pasar el cabo:

- **Vigota**: el lazo va en la garganta del canto → `w = n_disco × d`.
- **Aro de hierro del cranse**: el lazo tiene que **enhebrar el aro perpendicular** → hay que
  poner el eje del aro en el plano del lazo, o sea `w = eje_aro × d`. Con `w = d × eje_aro`, que
  fue el primer intento, el lazo gira **en el plano del aro** y no lo atraviesa: se ve apoyado
  encima en vez de pasando por dentro.

| Pieza | Tris | Nota |
|---|---|---|
| 7 gazas (patrón copiado) | 367 cada una, **2 569** en total | antes 5 600 con las hélices generadas |
| Garganta en las tres vigotas | 92 cada una | rebaje de **11 mm** en el canto, donde muerde la gaza |

**Y la lección de método**: cuatro intentos generando la trinca por procedimiento (manguito liso,
aro hueco, hélice doble, ocho entre ramales) y ninguno servía. El usuario lo resolvió a mano en
uno. Para geometría de este tamaño — un detalle de 10 cm que solo se ve a menos de 3 m — sale más
rápido que él modele una y yo mida y replique, que iterar a ciegas desde renders.

### El hierro: negro que refleja, no niquelado

`herraje_hierro` estaba en **Metallic = 1 con rugosidad 0,52**, y así un metal refleja el cielo
entero: de ahí el aspecto cromado. Dos intentos y el que vale:

| | Metallic | Color base | Rugosidad | Resultado |
|---|---|---|---|---|
| Antes | 1,0 | 0,055 | 0,52 | cromado |
| Intento 1 | 0,70 | 0,145 | 0,62-0,86 | **más claro aún**: con metallic 0,7 entra un 30 % de difuso, y en esta escena un albedo de 0,145 se va a blanco |
| Ahora | **1,0** | **0,020** | **0,28-0,46** por ruido | negro con reflejo nítido teñido al 2 % |

La clave: en un metal el color base **tiñe el reflejo**, no es albedo difuso. Para hierro negro que
refleje hay que dejar Metallic en 1 y bajar el color base, no al contrario. La rugosidad va por un
ruido de coordenadas de objeto para que la banda no tenga un brillo uniforme de plástico.

### Los tres herrajes que faltaban

| Pieza | Dónde | Qué es | Tris |
|---|---|---|---|
| `cranse_botalon` | (−8,85, 0, 3,273), **25 cm por dentro de la punta** | abrazadera de hierro con cuatro cáncamos. El **estay y el barbiquejo comparten la gaza de abajo** — donde el estay estaba antes, por debajo del palo — y los dos laterales van a las de los costados. No va en la punta: el palo sobresale 25 cm por delante | 736 |
| `vigota_alta/baja_*`, `acollador_*`, `cancamo_*` | roda a (−5,47, 0, 1,00) y costados a (−3,19, ±1,67, 1,88) | **vigota, acollador y cáncamo** por cada uno de los tres cabos, reutilizando las piezas de los obenques a escala 0,60. Van a **3,5 cm del forro**, con la cara de la vigota paralela a la tablazón, y el cabo entra 4,5 cm dentro de la vigota alta | 184 cada uno |
| `cuellos_mastil` + `tamborete_mastil` | z = 9,05 y 9,25 | los **cuellos** de madera donde asientan las gazas de los obenques, y el **tamborete** de hierro por encima | 24 + 96 |

**El radio del mástil no es constante y el mapa de vértices engaña.** `mastil_v3` solo tiene
anillos a z ≈ 9,0 (16 vértices, r = 0,1019), 10,0 (r = 0,050) y 10,2 (r = 0,0507): entre 2 y 8,5 m
no hay ni un vértice, así que medir por franjas devuelve vacío. El tamborete se puso primero con
r = 0,055 y **quedó dentro del palo**, invisible. El perfil útil es
`r(z) = 0,1019 − 0,0519 · (z − 9,0)`.

De labor, hecho hasta ahora (cáñamo sin alquitranar, Ø 32 mm):

| Cabo | Recorrido |
|---|---|
| Escotas de foque | del puño de escota (−4,11 / 2,81) a la regala en x −2,60, una por banda |

El puño de escota de una vela de proa **no se amarra a ninguna percha**: cuelga libre y lo
gobiernan las escotas. La de sotavento va tesa y la de barlovento holgada, con seno — que es
como se reconoce de un vistazo por qué banda entra el viento.

---

## 6. Reglas de herraje que ya están resueltas

- **Aro sobre percha**: concéntrico o descentrado, siempre con la fórmula
  `e = Rm − rs − (r_percha + juego) / cos(π/N)`. El punto que más se acerca a la madera **no
  es un vértice, es el centro de una arista**.
- **Aro sobre paño**: el eje del tubo cae en el punto medio entre las dos puntadas del falso.
- **Aros de extremo**: a la misma distancia libre del puño que lo que el tubo entra en la
  tela, medido cara a cara.
- **La amura es un solo amarre**: no se doblan un envergue de botavara y un garrucho de
  mástil en el mismo punto.

---

## 7. Pendiente, por orden de valor

1. **Maniobra de labor**: drizas de pico y garganta, amantillo y escota de mayor. Cabo rubio, sin
   alquitranar. Las escotas del foque ya están.
2. **Esqueleto** para izar (driza), abrir (escota) y ondear la lona.
3. Limpieza de vértices ocultos en los soportes de percha, y paso de esos soportes a la
   biblioteca.
4. **El botalón es corto para el tipo.** Medido en el modelo de referencia: casco de 7,7 m con
   3,6 m de botalón fuera de la roda, o sea **0,47 de la eslora**; el nuestro sale 3,10 / 12,00 =
   **0,26**. Las balandras de Bermudas llevaban botalones muy largos. Alargarlo agranda J, que ya
   está en 0,68 de la eslora, así que la decisión va junto con la de repartir el triángulo de
   proa en dos velas.
5. **Faltan las gazas del resto de la jarcia.** Las siete de proa están hechas con el patrón;
   los seis obenques siguen muriendo en el aire arriba en los cuellos y abajo en las mesas de
   guarnición. Se hacen copiando `gaza_vigota_bq` con su marco, como estas.

---

## 8. Errores ya cometidos, para no repetirlos

- **Sumar un vector de mundo a `v.co`** en objetos con rotación propia manda la pieza a otro
  sitio. Las dos quijadas tienen 3° y 39° en Y: la del pico acabó 78 cm alta. Se transforma
  `matrix_world`, no los vértices.
- **`closest_point_on_mesh` da falsos positivos** en prismas convexos cuando el punto más
  cercano cae en una arista. El test correcto es "detrás de *todos* los planos".
- **Nada de ruido no periódico** en una baldosa: se ve el corte.
- **Nada de parches dentro de una baldosa**: repiten en retícula. Los parches van únicos, o
  como geometría aparte.
- Una función que **borra el datablock de imagen antes de recrearlo** deja los nodos del
  material sin imagen. Un Normal Map en negro apunta hacia atrás y la superficie sale negra.
- **Alinear una pieza con una rotación de un solo eje deja el giro libre.** Las vigotas de los
  barbiquejos se montaron mapeando su eje largo a la dirección del cabo con una rotación de
  Rodrigues, y **el giro sobre ese eje quedó arbitrario**: la cara del disco se metió en la
  tablazón. Una vigota tiene dos direcciones que importan — su eje largo y la normal de su cara —
  así que hay que mapear el **triedro completo**: eje largo → dirección del cabo, normal de la
  cara → **normal del casco** (de `closest_point_on_mesh`), y la tercera por producto vectorial.
  Vale para cualquier pieza que no sea de revolución.
- **Si se mueve el extremo de un estay, hay que arrastrar la vela y sus aros.** Ha pasado dos
  veces: al bajar el botalón y al llevar el estay al cáncamo del cranse (16,37 cm). El foque se
  queda atrás y el gratil se separa — la segunda vez llegó a **17,2 cm**, con aros de 4,3 cm de
  radio, así que los aros dejaban de abrazar el cabo. El arreglo es el mismo mapa afín: se
  desplazan los puños de driza y amura por su posición a lo largo del estay (`s · d`), la baluma
  se queda quieta, y a los aros se les aplica la misma cizalla. Compruébalo midiendo la distancia
  del gratil al eje del estay: tiene que quedar por debajo del radio del aro.
- **Rehacer una malla sin UV** con un material que va por UV la deja de un solo color plano
  (le pasó al estay y a los dos racamentos).

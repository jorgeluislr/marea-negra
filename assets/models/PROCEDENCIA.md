# Procedencia y licencias de los modelos 3D

Este fichero existe porque **los metadatos de origen no sobreviven al pipeline**. Al reexportar
desde Blender, el `.glb` pierde todo rastro: `asset.generator` pasa a decir
`Khronos glTF Blender I/O` y el stream NTFS `Zone.Identifier` que escribió el navegador al
descargar desaparece. Verificado: los cuatro `.glb` del proyecto no conservan ningún ADS y no
queda copia de los originales de descarga en disco.

El formato glTF admite un campo `asset.copyright` y la extensión `KHR_xmp_json_ld`, pero **Meshy
no rellena ninguno de los dos**: el JSON de sus `.glb` solo declara `generator` y `version`, y las
texturas JPEG embebidas no llevan EXIF, XMP, IPTC ni comentario. No hay forma de auditar la
licencia desde el fichero. Este documento es el registro.

Última verificación: 27 de agosto de 2026.

---

## Cadena de derechos

    Imagen 2D (Meshy, herramientas de pago)
        └─► Modelo 3D (Meshy, plan de pago)
                └─► Retopología (Tripo, plan de pago)
                        └─► Marcado, rigging y horneado (Blender, trabajo propio)
                                └─► Materiales en mosaico (Poly Haven, CC0)
                                        └─► Juego (Godot)

**La forma no introduce material de terceros.** No se usaron imágenes de referencia externas: el
2D también se generó en Meshy, así que la cláusula de materiales de origen (que condiciona los
derechos comerciales a que las referencias subidas no infrinjan derechos ajenos) no aplica.

Sí hay dos eslabones de terceros, los dos acotados y documentados más abajo: **Tripo**, que no
aporta forma nueva sino que reescribe la malla que se le sube, y las **texturas CC0** de Poly
Haven, que no son modelos sino materiales aplicados a geometría propia.

---

## Barcos — generación propia, plan de pago

Licencia: **propiedad privada plena** (Meshy ToU §3.2, rama de plan de pago). Sin atribución, sin
royalties, sin restricciones de uso comercial.

| Fichero | Bytes | Exportador | Notas |
|---|---|---|---|
| `lancha.glb` | 62 005 696 | Blender glTF I/O v5.2.39 | Riggeada: huesos `raiz`, `vela`, `driza`, `timon` |
| `barca.glb` | 49 724 972 | Blender glTF I/O v4.5.47 | Sin riggear. Se llamaba `balandra.glb` hasta el 19/08/2026 |
| `goleta.glb` | 43 577 600 | Blender glTF I/O v4.5.47 | Sin riggear |
| `lancha_pre_marcado.glb` | 61 862 672 | Blender glTF I/O v5.2.39 | Instantánea previa al marcado; derivado de `lancha.glb` |

Fechas de generación aproximadas por las texturas exportadas: lancha 9 de agosto de 2026,
balandra 10 de agosto de 2026, goleta 10 de agosto de 2026.

`lancha.glb` se reexportó el 19 de agosto de 2026 (61 946 464 bytes) al sustituir el tramo bajo
del mástil, así que su tamaño ya no coincide con el de la tabla.

### Originales de descarga

Se conservan **sin renombrar y con su `Zone.Identifier` intacto** en `fuentes/crudo/`. Son el
eslabón que prueba la procedencia; los `.glb` de `assets/models` son derivados y ya no la llevan.

| Original | MB | Descargado | Barco |
|---|---|---|---|
| `Meshy_AI_Balandra_Gaff_Rigged__0819161322_…` | 134,1 | 2026-08-19 18:13 | balandra cangreja, calidad ultra |
| `Meshy_AI_Canoa_Pirata_a_Vela_3_0809175659_…` | 47,4 | 2026-08-09 19:57 | lancha |
| `Meshy_AI_Balandra_Pirata_3D_0809213249_…` | 44,9 | 2026-08-09 23:32 | balandra de vela cuadra |
| `Meshy_AI_Goleta_Pirata_3D_0810152223_…` | 39,5 | 2026-08-10 17:22 | goleta |

Las imágenes 2D de partida están en `fuentes/crudo/referencias/`, también con su ADS. La de la
balandra cangreja se generó con **GPT Image 2 dentro de Meshy**, que es lo que mantiene intacta la
cadena: la herramienta es de Meshy, así que no hay referencia externa subida.

**Evidencia:** los modelos están en la biblioteca de la cuenta de Meshy del titular, con su
timestamp de generación. Eso es prueba más sólida que cualquier metadato en el fichero.

**Corrección (19 de agosto de 2026): el UUID de Meshy sí es recuperable.** Este documento
afirmaba lo contrario, y era falso: lo que había perdido el ADS eran los `.glb` reexportados de
`assets/models`, no las **descargas originales**. Éstas conservaban intacto su stream
`Zone.Identifier`, y dentro va el `HostUrl` de la descarga, que incluye el UUID:

| Barco | UUID de Meshy | Original |
|---|---|---|
| Balandra cangreja (nueva) | `907778fc-396f-43e1-afcd-d4915d51e00a` | `Meshy_AI_Balandra_Gaff_Rigged__0819161322_image-to-3d-texture.glb` |
| Balandra de vela cuadra | `aea101ff-252b-446b-a630-8e93a7cdb824` | `Meshy_AI_Balandra_Pirata_3D_0809213249_image-to-3d-texture.glb` |
| Canoa → lancha | `2b560cd4-44db-4f14-832b-aa8fba7cf18a` | `Meshy_AI_Canoa_Pirata_a_Vela_3_0809175659_image-to-3d-texture.glb` |
| Goleta | `10e03e64-7734-4281-b11d-c05718da68bc` | `Meshy_AI_Goleta_Pirata_3D_0810152223_image-to-3d-texture.glb` |

### Generaciones por piezas y reintentos del casco

A partir del 20 de agosto se abandonó el modelo entero y se generó **una pieza por trabajo**, que
es lo que da a cada una el atlas completo (ver `fuentes/prompts_meshy.md`). Estos originales no
estaban registrados:

| Original | MB | Descargado | UUID | Ver. | Pieza |
|---|---|---|---|---|---|
| `Meshy_AI_Balandra_Casco_3D_0820221542_…glb` | 88,3 | 2026-08-21 00:15 | `d44ece41-c147-406e-bcf6-86c58413bbb5` | 4 | casco, 1ª tanda |
| `Meshy_AI_Balandra_Cubierta_3D_0820221554_…glb` | 68,6 | 2026-08-21 00:15 | `c0a91c60-788b-48d5-a085-f1e111752b2b` | 4 | cubierta detallada |
| `Meshy_AI_Balandra_Cubierta_Bas_0820230603_…glb` | 55,9 | 2026-08-21 01:06 | `d388bfb9-393d-4b2b-b89f-e70b4d29e0bf` | 4 | cubierta lisa |
| `Meshy_AI_Balandra_Timon_3D_0820221601_…glb` | 71,6 | 2026-08-21 00:16 | `a13a7b37-d39c-4800-a340-34157eb38055` | 4 | timón, 1ª versión |
| `Meshy_AI_Balandra_Casco_3D_0825213421_texture.glb` | 74,1 | 2026-08-25 23:34 | `01a03ab7-74f3-7a26-8f11-00c13cf614fc` | **7** | casco retexturizado |
| `Meshy_AI_Balandra_Casco_3D_0825213854_texture_fbx.zip` | 147,1 | 2026-08-25 23:39 | `01a03ab7-74f3-7a26-8f11-00c13cf614fc` | **7** | el mismo, en FBX |
| `Meshy_AI_Balandra_Casco_3D_0826151502_texture.glb` | 100,7 | 2026-08-26 17:15 | `01a03e71-a3ce-7626-b069-3912c9a387b4` | **7** | casco definitivo |
| `Meshy_AI__0826210934_texture.glb` | 109,3 | 2026-08-26 23:09 | `d53bbc1b-7e14-4ea9-ab7a-294a822a5a1d` | 4 | timón, 2ª versión |
| `Meshy_AI__0826231559_texture.glb` | 86,4 | 2026-08-27 01:16 | `01a04058-9ef9-76f4-b0c8-9c380cd2570a` | **7** | casco con tablazón modelada, **trae el timón montado** |
| `Meshy_AI__0826233101_texture.glb` | 102,2 | 2026-08-27 01:31 | `5fe63c1a-4baa-46eb-8fd0-4027124540f5` | 4 | el mismo, retexturizado a **8192²** |
| `Meshy_AI__0827005500_texture.glb` | 89,7 | 2026-08-27 02:55 | `289e0cc8-9348-4e87-995a-932a2cfb0468` | 4 | otro retexturizado a 8192² del **mismo modelo base** |
| `Meshy_AI__0828152338_texture.glb` | 103,5 | 2026-08-28 17:23 | `01a048f0-a96d-768c-a816-8f2898b99d2b` | **7** | casco con tablazón modelada, **sin timón**, atlas 8192² — es el que está en juego como `casco_v4` |

| `Meshy_AI__0829140717_texture.glb` | 121,9 | 2026-08-29 17:03 | `56793b13-75d8-4c87-99b1-53ec8355fc38` | 4 | **barril**, malla completa |
| `Meshy_AI_barril_pirata_tri_3k_0829150333_texture.glb` | 100,6 | 2026-08-29 17:03 | `b28ef7f6-78f9-4ed1-99a3-34026e63fb4d` | 4 | el mismo, remallado a 3k en Meshy — se descartó por pérdida de detalle |

El `.zip` de FBX comparte UUID con su `.glb`: es la misma generación descargada en otro formato.
Se conserva porque **glTF solo transporta triángulos** y el FBX era el único camino para traer los
cuadriláteros del remallado de Meshy.

**Hallazgo (27 de agosto de 2026): los UUID de versión 7 sí codifican la fecha.** Los tres
marcados arriba con un 7 llevan en sus primeros 48 bits la marca de tiempo Unix en milisegundos,
y decodificada cuadra con la descarga:

| UUID | Generado (UTC) | Descargado (local) |
|---|---|---|
| `01a03ab7-74f3-7a26-…` | 2026-08-25 20:58:16 | 2026-08-25 23:34 |
| `01a03e71-a3ce-7626-…` | 2026-08-26 14:20:30 | 2026-08-26 17:15 |
| `01a04058-9ef9-76f4-…` | 2026-08-26 23:12:24 | 2026-08-27 01:16 |
| `01a048f0-a96d-768c-…` | 2026-08-28 15:15:26 | 2026-08-28 17:23 |

Meshy usa v7 en los trabajos de retexturizado y remallado, y v4 en los de imagen-a-3D, así que
la fecha solo se recupera de los primeros. Para el resto sigue valiendo lo de abajo.

El sello del nombre del fichero es la **hora de exportación en UTC**, no la de generación: va unos
minutos por detrás del UUID (3 min en `01a04058`, 8 min en `01a048f0`). Sirve para ordenar, no como
fecha de creación.

A diferencia de los props, los UUID de versión 4 **no** codifican la fecha: el
timestamp hay que seguir sacándolo de la biblioteca de la cuenta. El contenido literal de los
streams está transcrito en `fuentes/crudo/_zone_identifier_respaldo.txt`, capturado antes de
mover los ficheros por si un `cp` futuro los borra.

**Suscripción verificada:** factura y recibo de Meshy con periodo de validez declarado en la
descripción, **4 de agosto → 4 de septiembre de 2026**. Cubre las tres generaciones con margen
(lancha 9/08, balandra y goleta 10/08). Conservar los PDF fuera del proyecto.

---

## Props — descargas de Meshy Community

Licencia: **CC0 1.0 Universal** (Meshy ToU §3.3: todo lo liberado a la página Community queda
dedicado al dominio público). Uso comercial sin restricciones, sin atribución obligatoria. CC0
es irrevocable: un cambio posterior de los términos de Meshy no afecta a lo ya descargado.

CC0 **no es vírico**: integrar estos componentes en los barcos no impone ninguna condición al
fichero resultante.

Ubicación: `fuentes/crudo/props/` (movidos desde `Downloads` el 19 de agosto de 2026 con
`Move-Item`, verificando que el `Zone.Identifier` sobrevivía al salto de volumen `C:` → `E:`).

| Modelo | UUID Meshy | Creado (UTC) | Descargado | MB |
|---|---|---|---|---|
| Create_a_hyper_realis | `0193bc3f-be11-7185-a24a-8822140a4fa4` | 2024-12-12 19:01:54 | 2026-08-14 22:14 | 18,5 |
| Antique_Treasure_Chest | `0197920f-7b95-7c39-ab8a-d70da9a704c4` | 2025-06-21 10:36:17 | 2026-08-14 19:15 | 9,7 |
| Wooden_Crate | `01984fe7-135a-7a30-96f3-693aaa10cee5` | 2025-07-28 07:20:00 | 2026-08-14 19:09 | 15,9 |
| Sack_of_Plenty | `0198a76e-5084-7cd3-8fd5-6b85a7421fd3` | 2025-08-14 07:14:41 | 2026-08-14 19:09 | 6,8 |
| Barrel_Bliss | `019903b2-fa06-79ae-a138-3ca79d7bfd41` | 2025-09-01 05:14:45 | 2026-08-14 19:09 | 27,8 |
| kiste_holz | `01999702-8c0a-7e96-9954-ec6c33e30433` | 2025-09-29 19:45:50 | 2026-08-14 19:14 | 20,2 |

Las fechas de creación se obtuvieron descodificando el UUID, que es un **UUIDv7**: sus primeros
48 bits son el timestamp Unix en milisegundos. El número del nombre de fichero (`0814170950`) no
es la fecha de generación sino el momento de la exportación/descarga en UTC.

### Caso aparte

| Modelo | UUID Meshy | Creado (UTC) | Descargado | MB |
|---|---|---|---|---|
| Triune_Radiance | `019f2c94-b065-7ab1-9cac-17e3b16df995` | 2026-07-04 10:02:49 | 2026-07-04 12:15 | 18,8 |

Generado y descargado el mismo día con trece minutos de diferencia (12:02:49 y 12:15 hora
local, UTC+2), y el único con `generator: meshy-scene` y sufijo `_generate` en vez de `_texture` —
patrón de generación propia, no de descarga de galería.

**Queda fuera del periodo facturado verificado** (4/08 → 4/09/2026). El ciclo de facturación
ancla en el día 4 de cada mes y este modelo es del 4 de julio, lo que apunta a que la suscripción
arrancó ese mismo día: si existe un recibo del ciclo 4/07 → 4/08 emitido antes de las 12:02 hora
local del 4 de julio, queda cubierto por propiedad plena. Pendiente de comprobar en el correo.

**Sin consecuencias prácticas:** si no estuviera cubierto caería en la rama de plan gratuito
(CC BY 4.0), que también permite uso comercial, solo con el crédito «Model created with Meshy –
CC BY 4.0 License». Y este modelo no está integrado en el juego: sigue en `Downloads`, sin usar.

---

## Retopología — Tripo, plan de pago

**El casco que está en el juego es una retopología de Tripo.** Es el eslabón de terceros más
importante de la cadena y no estaba registrado.

| Salida | MB | Descargado | Entrada que se subió |
|---|---|---|---|
| `fuentes/casco_retopo_tripo.glb` | 15,1 | 2026-08-26 18:11 | `casco_simetrico_sin_textura.glb`, malla propia ya espejada |
| `fuentes/timon_retopo_tripo.glb` | 20,4 | 2026-08-26 23:45 | `Meshy_AI__0826210934_texture.glb`, sin texturas |

**Evidencia:** los dos conservan su stream `Zone.Identifier` con `HostUrl=https://studio.tripo3d.ai/`.
El primero además con `ReferrerUrl` del mismo dominio. Los trabajos están en la biblioteca de la
cuenta de Tripo del titular.

Lo que aporta Tripo es **topología, no forma**: se le sube una malla propia y devuelve la misma
superficie con menos vértices — medido, 2,1 mm de desviación sobre 11,93 m en el casco y 0,95 mm
sobre 2,37 m en el timón. No introduce geometría inventada ni texturas nuevas: la textura se
hornea después en Blender desde el original de Meshy, porque la suscripción no permite descargar
el atlas completo a 8K.

**Pendiente de verificar:** la cláusula de propiedad de las salidas en los términos de Tripo para
plan de pago. Hasta leerla y transcribirla aquí, este eslabón queda **sin licencia confirmada**.
Es el único punto abierto del documento. Conservar la factura fuera del proyecto, como la de Meshy.

---

## Materiales de textura — CC0 de terceros

A diferencia de los barcos y los props, que salen de Meshy, estos son **texturas PBR en mosaico**
descargadas de bibliotecas públicas. No son modelos: son materiales que se aplican a geometría
propia, y su papel es romper el techo de densidad del atlas de Meshy. Ver la sección «Resolución
de textura» del skill compartido para el criterio.

Todas están bajo **Creative Commons CC0 1.0** (dominio público): uso comercial permitido, **sin
atribución obligatoria** y sin condiciones que se arrastren al trabajo derivado. Se registran aquí
igualmente, por la misma razón que se registran los UUID de Meshy: dentro de un año nadie recuerda
de dónde salió un fichero, y una cadena de propiedad solo vale si está escrita.

| Material | Origen | Autores | Baldosa | Se usa en |
|---|---|---|---|---|
| `rough_wood` | [Poly Haven](https://polyhaven.com/a/rough_wood) | Rob Tuytel | 0,5 × 0,5 m | **mástil** (`biblioteca/mastil.blend`) y **casco** (`casco_v3_madera`), este a **dos escalas a la vez**: el color a 1,5 m y el relieve a 0,35 m. Ver la nota de abajo |
| `weathered_planks` | [Poly Haven](https://polyhaven.com/a/weathered_planks) | Dario Barresi, Dimitrios Savva | 2,0 × 2,0 m | **cubierta** (`cubierta_tablazon`) y **casco** (`casco_tablazon`, capa de detalle triplanar) |
| `weathered_brown_planks` | [Poly Haven](https://polyhaven.com/a/weathered_brown_planks) | Dimitrios Savva, Rico Cilliers | 1,8 × 1,8 m | descartada: retícula de juntas |
| `washed_grey_oak_veneer` | [Poly Haven](https://polyhaven.com/a/washed_grey_oak_veneer) | Poly Haven | 1,0 × 1,0 m | descartada dos veces: como color por falta de contraste, y como relieve por lo mismo — se probó en el casco y quitaba el detalle |
| `hessian_380` | [Poly Haven](https://polyhaven.com/a/hessian_380) | colormass (fotografía), Rico Cilliers (proceso) | 0,2739 × 0,2738 m | **velas** (`lona_vela`): la trama del paño. Se usa **recoloreada** — se le toma la luminancia y se multiplica por nuestro blanco amarillado, así que del original queda el tejido y no el marrón de yute |

**Una baldosa, dos escalas.** El casco usa `rough_wood` para el color a 1,5 m de lado y para el
relieve a 0,35 m, con proyecciones triplanares independientes. No es un capricho: los nudos de ese
escaneo miden 10-20 cm de la baldosa, y a 1,5 m salían como **abolladuras** en el mapa de normales
—confundibles con un defecto de malla— mientras que a 0,35 m los mismos nudos son veta de 3-5 cm.
El color, en cambio, necesita la escala grande: a 0,35 m sus téxeles caen por debajo del píxel a
distancia de trabajo y se promedian a nada. Densidades resultantes: 1,365 téxeles/mm el color,
**5,85 el relieve**.

Los originales viven en `fuentes/crudo/materiales/<nombre>/`, a 2K y en JPEG, con los mapas de
color, normal (OpenGL) y **ARM** — oclusión, rugosidad y metalicidad empaquetadas en R, G y B, que
es lo que `StandardMaterial3D` de Godot lee por canal.

**Se empacan dentro de cada `.blend` de biblioteca**, aunque eso duplique el material entre piezas.
Es una decisión consciente: la alternativa —un `materiales.blend` enlazado— ahorra unos 5 MB por
pieza pero mete una dependencia entre ficheros, y la convención del proyecto es que cada `.blend`
sea autónomo y se pueda mover sin romper nada. Con seis u ocho piezas de madera la duplicación
ronda los 40 MB, que no compensa perder esa robustez.

`fuentes/crudo/materiales/mastil_baldosa/` **no** es de terceros: es una baldosa que se intentó
fabricar recortando la propia textura horneada del mástil. Salió empastada y se descartó — el
atlas de origen no tiene ninguna región nítida— pero se conserva como registro del intento.

## Condiciones a mantener

1. **No publicar los barcos en la página Community de Meshy.** La §3.3 convierte en CC0
   irrevocablemente todo lo liberado ahí. Sería la única forma de perder la exclusividad de los
   modelos propios sin pretenderlo.
2. **Guardar el justificante de suscripción** de pago cubriendo las fechas de generación.
3. **Preservar la procedencia de las descargas futuras** antes de tocarlas con Blender: dejar el
   `.glb` original sin renombrar en `fuentes/crudo/`, con su `Zone.Identifier`, y anotar la fila
   en este fichero. Leer el ADS con:

       Get-Content "<fichero>.glb" -Stream Zone.Identifier

   **Mueve los originales solo con PowerShell** (`Move-Item` / `Copy-Item`), que sí arrastra los
   streams NTFS incluso entre volúmenes — verificado en el traslado de `C:` a `E:` del 19 de
   agosto. El `cp` y el `mv` de Git Bash **no copian streams alternativos**: dejan el fichero
   idéntico en apariencia y sin ninguna señal de que la procedencia se ha ido. Verifica siempre
   el stream en destino después de mover.

4. Opcionalmente, estampar `asset.copyright` al exportar desde Blender. No prueba nada frente a
   terceros, pero evita volver a perder el rastro en el siguiente reexport.

---

## Nota sobre protegibilidad

Los modelos son de generación puramente automática, así que la malla desnuda probablemente **no
sea protegible por derechos de autor** (tanto la Oficina de Copyright de EE. UU. como el marco
español y europeo exigen autoría/originalidad creativa humana). Esto no limita el uso comercial
—la ausencia de copyright no es una prohibición— pero sí debilita la capacidad de impedir que un
tercero reutilice un `.glb` extraído del build. El rigging, el marcado de partes y los pesos sí
son trabajo humano con autoría clara. Solo sería relevante si algún día se vendieran los modelos
como assets, no para el juego propio.

---

## Qué se distribuye con el juego y qué no

**Los recibos y facturas de Meshy NO van en el proyecto ni en el build.** Contienen datos
personales y fiscales del titular (nombre, dirección de facturación, NIF, últimos dígitos de la
tarjeta, números de factura). Un build de Godot se desempaqueta con herramientas públicas en
minutos, y este directorio tiene `.gitignore` preparado para un repositorio que todavía no existe:
cualquiera de las dos vías convertiría esa documentación en pública. La prueba de licencia no
necesita viajar con el producto; si una plataforma la pide, se envía en ese momento.

Los justificantes viven en **`licencias/`**, en la raíz del proyecto, para tenerlos localizados
junto al resto. Estar dentro del proyecto es compatible con no distribuirlos, siempre que se
mantengan las dos barreras:

| Barrera | Qué evita |
|---|---|
| `licencias/.gdignore` (fichero vacío) | Godot omite el directorio: no lo escanea, no lo importa y no lo exporta al build |
| `licencias/` en `.gitignore` | Queda fuera del repositorio cuando se haga `git init` |
| `fuentes/.gdignore` | Igual para las fuentes en crudo y los `.blend`: sin él, Godot importaría los `.glb` originales como escenas duplicadas, y los `.blend` si algún día se activa su importador nativo |
| `fuentes/` en `.gitignore` | Deja fuera del repositorio 2,7 GB de binarios que no son entregables |

Ninguna de las dos protege frente a comprimir la carpeta del proyecto y compartirla: en ese caso
hay que excluirla a mano. Si algún día se crea `export_presets.cfg`, añadir `licencias/*` al
`exclude_filter` del preset como tercera barrera.

Detalle en `licencias/LEEME.md`.

**Lo que sí hay que incluir en el build: el aviso de licencia de Godot.** El motor es MIT, y la MIT
exige que el aviso de copyright y el texto de la licencia acompañen a las distribuciones. Es la
única atribución obligatoria que tiene este proyecto — ninguno de los assets la requiere, pero el
motor sí. Godot da el texto en tiempo de ejecución:

    Engine.get_license_text()      # texto de la licencia MIT del motor
    Engine.get_copyright_info()    # avisos de los componentes de terceros del motor

Basta una pantalla de créditos que los muestre.

## Fuentes

- Meshy, Terms of Use (última actualización 7 de marzo de 2026) — §3.2 propiedad del contenido
  de usuario, §3.3 licencia Community: https://www.meshy.ai/terms-of-use
- Meshy Help Center, uso comercial de los assets:
  https://help.meshy.ai/en/articles/16102098-can-i-use-meshy-assets-commercially
- Meshy Help Center, venta en otras plataformas:
  https://help.meshy.ai/en/articles/9992022-can-i-sell-the-models-on-other-platforms
- Tripo, Terms of Service — **pendiente de leer y transcribir** la cláusula de propiedad de las
  salidas para plan de pago: https://www.tripo3d.ai/
- Poly Haven, licencia CC0 de todos sus assets: https://polyhaven.com/license

No constituye asesoramiento legal. Es el registro de lo verificado en los términos publicados.

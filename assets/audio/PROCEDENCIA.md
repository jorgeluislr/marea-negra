# Procedencia y licencias del audio

Igual que `assets/models/PROCEDENCIA.md`, pero para sonido — y aquí **importa más**, porque en
sitios como Freesound la licencia va **por archivo**, no por autor ni por sitio. Un mismo autor
puede tener sonidos CC0 y CC-BY-NC mezclados.

**Regla: se rellena la fila en el momento de descargar.** Dentro de seis meses no se sabrá de
dónde salió cada crujido, y un archivo sin procedencia hay que tirarlo aunque suene bien.

## Qué licencias valen

| licencia | ¿comercial? | qué obliga |
|---|---|---|
| **CC0** (Creative Commons 0) | sí | nada |
| **CC-BY** (Attribution) | sí | acreditar autor y fuente en los créditos |
| CC-BY-NC (NonCommercial) | **NO** | inservible para este proyecto |
| Sampling+ | ambigua | evitar |

Cuidado con el filtro *Approved for Free Cultural Works* de Freesound: **no es CC0**, agrupa CC0
y CC-BY juntos. Y el filtro es orientativo: la licencia buena es la de la página del archivo.

## Originales

Los descargados van sin renombrar a `fuentes/crudo/audio/`, **movidos con PowerShell** para no
perder el stream NTFS `Zone.Identifier`, que guarda la URL de origen y es la prueba de
procedencia (`cp`/`mv` de Git Bash lo tiran en silencio). En `assets/audio/` va la copia con el
nombre que usa el juego.

## Registro

| archivo en el juego | uso | original | fuente | autor | licencia | fecha |
|---|---|---|---|---|---|---|
| `driza.wav` | izar/arriar vela | `465605__codefhd__saildeploy.wav` | [freesound 465605](https://freesound.org/people/codefhd/sounds/465605/) | codefhd | **CC0** | 2026-09-04 |
| `ambiente_proa.wav` | cama ambiente del barco | `852108__myloop__sailboat-bow.wav` | [freesound 852108](https://freesound.org/people/myLoop/sounds/852108/) | myLoop | **CC0** | 2026-09-04 |
| `ambiente_puerto.wav` | ambiente de la isla/puerto | `648593__elenalostale__ambience-port-pirates.wav` | [freesound 648593](https://freesound.org/people/Elenalostale/sounds/648593/) | Elenalostale | **CC0** | 2026-09-04 |
| `viento_calma.wav` | ambiente, viento flojo | — | generado | propio | propia | 2026-09-04 |
| `viento_fuerte.wav` | ambiente, viento fuerte | — | generado | propio | propia | 2026-09-04 |
| `mar.wav` | *(sin usar: lo sustituyo `ambiente_proa`)* | — | generado | propio | propia | 2026-09-04 |
| `flameo_vela.wav` | lona desventada (bucle) | — | generado | propio | propia | 2026-09-04 |
| `flameo_golpe_1.wav` | latigazo de lona | — | generado | propio | propia | 2026-09-04 |
| `flameo_golpe_2.wav` | latigazo de lona | — | generado | propio | propia | 2026-09-04 |
| `flameo_golpe_3.wav` | latigazo de lona | — | generado | propio | propia | 2026-09-04 |
| `flameo_golpe_4.wav` | latigazo de lona | — | generado | propio | propia | 2026-09-04 |
| `agua_casco.wav` | agua en el costado, por velocidad | — | generado | propio | propia | 2026-09-04 |

Los marcados como **generado** los sintetiza `audio_src/sintetizar_sfx.py` (ruido filtrado y
resonadores). Son originales del proyecto: sin licencia de terceros que rastrear, y
reproducibles ejecutando el script.

## Créditos a incluir en el juego

Solo hacen falta para los CC-BY. De momento, ninguno: todo lo de arriba es CC0 o propio.

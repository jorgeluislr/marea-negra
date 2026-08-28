# Modelos del juego

**Los `.glb` y sus texturas no estan en el repositorio.** Solo se versionan los
`.import` y esta documentacion.

## Por que

Los modelos actuales son mallas de **autoria**, no de juego: entre 40 y 62 MB
cada uno, con atlas de hasta 8192 pixeles. Git —y Git LFS mas aun— guarda cada
version completa, sin deltas utiles sobre binarios ya comprimidos, asi que cada
reexportacion costaria su peso entero en la cuota. Con la cuota gratuita de 1 GB
eso da para unas cinco reexportaciones de los tres barcos.

Volveran al repositorio cuando existan las versiones reducidas para juego
(objetivo: 20-40 mil triangulos y texturas de 2048, unos pocos MB por barco).

## Como conseguirlos

No se regeneran solos: hay que exportarlos desde los `.blend` de trabajo, que
tampoco estan en el repositorio (`fuentes/blend/`, excluido por tamano). Pidelos
a quien tenga la copia de trabajo y dejalos en este mismo directorio con estos
nombres exactos:

    barca.glb
    goleta.glb
    lancha.glb

Los `.import` versionados se encargan del resto: al abrir el proyecto, Godot los
importa conservando los `uid://` que ya usan las escenas.

Mientras falten, Godot avisara de ficheros ausentes al abrir el proyecto. Es lo
esperado, no un error de configuracion.

## Procedencia y licencias

En `PROCEDENCIA.md`, que si esta versionado.

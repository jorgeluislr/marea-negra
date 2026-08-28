# Marea Negra

Juego 3D de piratas (Godot 4.7) con navegación de barco y exploración/combate a pie, estilo Pirates of the Caribbean.

## Estructura del proyecto

```
marea_negra/
├── project.godot
├── scenes/
│   ├── world/        # Escenas de nivel/mundo (islas, mar, main_world.tscn)
│   ├── ship/         # Escena(s) de barco y sus variantes
│   ├── character/    # Jugador y NPCs
│   └── ui/           # HUD, menús
├── scripts/          # Scripts .gd sueltos usados por las escenas
├── assets/
│   ├── models/       # Modelos exportados desde Blender (.glb)
│   ├── textures/      # Texturas
│   └── audio/         # Música y efectos de sonido
└── blender_src/       # Archivos fuente .blend (no se exportan directo al juego)
```

## Estado actual (placeholder funcional)

- `scenes/character/player.tscn`: cápsula controlable en primera/tercera persona simple.
  WASD para moverse, Shift para correr, Espacio para saltar, mouse para mirar, E para interactuar.
- `scenes/ship/ship.tscn`: caja controlable como barco. W/S acelera y frena, A/D gira el timón.
  Tiene un balanceo (bobbing) simple como placeholder de oleaje.
- `scenes/world/main_world.tscn`: mar (plano), una "isla" (caja), cielo procedural, luz direccional,
  una instancia de jugador y una de barco.

Todo esto usa geometría primitiva de Godot (cápsulas, cajas, planos) para poder probar el
gameplay antes de tener arte final. La idea es reemplazar cada mesh/material por los modelos
reales que vengan de Blender sin tener que tocar la lógica de los scripts.

## Flujo de trabajo Blender → Godot

1. Modela y anima en Blender, trabajando en **metros reales** (1 unidad Blender = 1 metro).
   Los barcos y personajes de Pirates of the Caribbean son grandes: mide referencias reales
   (un galeón mediano ronda 30-40m de eslora) para que la escala se sienta bien en Godot.
2. Antes de exportar: aplica todas las transformaciones (`Ctrl+A` → Rotation & Scale) y
   asegúrate de que las normales estén correctas.
3. Exporta con **glTF 2.0** (`File > Export > glTF 2.0`), formato `.glb` (binario, todo en un
   archivo) para assets simples, o `glTF Separate` si quieres texturas editables aparte.
   - Godot usa Y-up; el exportador de Blender ya hace esa conversión automáticamente.
   - Activa "+Y Up" (viene por defecto) y exporta solo lo necesario (deselecciona cámaras/luces
     de Blender si no las necesitas en el juego).
4. Guarda el `.glb` exportado directamente dentro de `assets/models/` (usa subcarpetas si el
   proyecto crece, ej. `assets/models/ships/`, `assets/models/characters/`).
5. Godot importa el `.glb` automáticamente. Arrástralo a una escena o instáncialo como
   `PackedScene` para reemplazar los meshes primitivos actuales.
6. Guarda el archivo fuente `.blend` en `blender_src/` (no se usa en el juego directamente,
   pero lo necesitas para futuras ediciones). Estos archivos pueden pesar mucho — considera
   usar Git LFS si el repo crece.

## Próximos pasos sugeridos

- Reemplazar la cápsula del jugador por un modelo con animaciones (idle, correr, trepar,
  espada) usando un `AnimationTree`.
- Reemplazar la caja del barco por un modelo de galeón/bergantín con velas, y separar el
  casco de las velas para poder animarlas con el viento.
- Sistema de embarque/desembarque real: al interactuar con el barco, ocultar/desactivar al
  jugador y mover la cámara y el control al timón (`HelmPosition` ya existe en `ship.tscn`).
- Agua de verdad: shader de agua con oleaje (vertex displacement) en vez del plano estático,
  y flotación física del barco basada en la altura de la ola bajo el casco.
- Combate: espada cuerpo a cuerpo a pie, cañones en el barco (raycast o proyectiles físicos),
  daño al casco y al velamen.
- Mundo: varias islas, sistema de viaje en el mar abierto, puertos donde comprar/vender y
  aceptar misiones.
- Input Map: mover los controles hardcodeados (`Input.is_key_pressed`) al Input Map del
  proyecto para permitir remapeo de teclas desde un menú de opciones.

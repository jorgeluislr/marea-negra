<#
    Sincroniza "Marea Negra" con una carpeta de Google Drive para escritorio.

    Sube SOLO lo que git no guarda: los ficheros que .gitignore deja fuera del
    repositorio (fuentes de Blender, .glb, audio, relieve, memorias...). El
    codigo, las escenas y las pruebas van a GitHub y no se duplican en Drive
    (decidido con el usuario el 18-10-2026; antes copiaba el proyecto entero).
    La lista sale de `git ls-files --others --ignored`, asi que no hay que
    mantener extensiones a mano.

    De eso deja FUERA todo lo que es respaldo de recuperacion ante fallo (11,2 GB de
    instantaneas de sesion, 6,3 GB de ficheros recuperados de un .blend
    truncado y 1 GB de .blend1 automaticos de Blender), la cache de Godot y la
    carpeta licencias/, que lleva datos personales y no debe viajar a una
    carpeta compartida.

    Por defecto SIMULA: no escribe nada y solo dice que copiaria. Anade
    -Ejecutar para copiar de verdad.

        .\sincronizar_drive.ps1              # simula
        .\sincronizar_drive.ps1 -Ejecutar    # copia de verdad

    El destino por defecto es G:\My Drive\marea_negra, la carpeta que Google
    Drive para escritorio monta en streaming. Si la unidad cambia de letra,
    pasala con -Destino.

    La copia solo anade y actualiza: lo que renombres o borres en local se
    queda en Drive hasta que lo quites alli.
#>
[CmdletBinding()]
param(
    [string] $Destino = 'G:\My Drive\marea_negra',

    [string] $Origen = 'E:\Godot\Game3D\marea_negra',

    [switch] $Ejecutar
)

$ErrorActionPreference = 'Stop'

# Carpetas excluidas, a cualquier profundidad. "respaldos" cubre de una vez
# fuentes\blend\respaldos y fuentes\blend\biblioteca\respaldos.
$carpetasFuera = @(
    'respaldos',    # instantaneas de sesion: 11,2 GB
    '.git',         # Drive corrompe repositorios git al sincronizar a medias
    '.godot',       # cache regenerable del editor
    '.import',
    '__pycache__',
    'licencias',    # datos personales: nunca a una carpeta compartida
    'capitan', 'capitan_baja_unido',  # EN PAUSA (18-10-2026): el usuario aun no decide si se queda
                                      # con este modelo; lo que ya hay online del capitan no se toca.
                                      # Quitar estas dos y 'capitan*.blend' para volver a subirlo.
    'worktrees'     # .claude\worktrees: copias enteras del proyecto que crean las sesiones de
                    # Claude (0,87 GB la primera, 18-10-2026). .claude\memoria SI sube: no va a git.
)

# Ficheros excluidos por patron o por nombre.
$ficherosFuera = @(
    '*.blend1', '*.blend2', '*.blend3',   # respaldos automaticos de Blender
    '*.bak',                              # 3,2 GB en dos ficheros
    '*.pyc',
    'balandra_piezas_recuperado.blend',   # 1,8 GB rescatados de un .blend truncado
    'balandra_piezas_rec2.blend',         # 1,3 GB, segundo intento del mismo rescate
    '*_pre_marcado*', '*_pre_etiqueta*',  # modelos anteriores a marcar las partes
    '*_respaldo*', '*_viejo*',
    'capitan*.blend',                     # EN PAUSA, ver arriba
    'desktop.ini', 'Thumbs.db'
)

if (-not (Test-Path -LiteralPath $Origen)) {
    throw "No existe el origen: $Origen"
}

# Si la unidad de Drive no esta montada, robocopy la crearia como carpeta local
# y la copia acabaria en el disco en vez de en la nube, en silencio.
$raiz = [System.IO.Path]::GetPathRoot($Destino)
if (-not (Test-Path -LiteralPath $raiz)) {
    throw "No esta montada la unidad $raiz. Arranca Google Drive para escritorio."
}
if (-not (Test-Path -LiteralPath $Destino)) {
    throw "No existe la carpeta de destino: $Destino. Creala en Drive antes de sincronizar."
}

# Lo que git NO guarda, con rutas sin escapar (acentos incluidos).
$ignorados = & git -C $Origen -c core.quotepath=false ls-files --others --ignored --exclude-standard
if ($LASTEXITCODE -ne 0) {
    throw "git no pudo listar los ficheros ignorados de $Origen"
}

function Fuera([string] $ruta) {
    $partes = $ruta -split '/'
    foreach ($c in $carpetasFuera) { if ($partes[0..($partes.Count - 2)] -contains $c) { return $true } }
    $nombre = $partes[-1]
    foreach ($f in $ficherosFuera) { if ($nombre -like $f) { return $true } }
    return $false
}

$lista = $ignorados | Where-Object { $_ -and -not (Fuera $_) }

# Que hay que copiar: lo que no esta en Drive o difiere en tamano o fecha (2 s de tolerancia,
# la misma que robocopy /FFT).
$porCopiar = @()
$bytes = 0
foreach ($r in $lista) {
    $o = Join-Path $Origen ($r -replace '/', '\')
    $d = Join-Path $Destino ($r -replace '/', '\')
    $fo = Get-Item -LiteralPath $o -ErrorAction SilentlyContinue
    if ($null -eq $fo) { continue }
    $fd = Get-Item -LiteralPath $d -ErrorAction SilentlyContinue
    if ($null -eq $fd -or $fd.Length -ne $fo.Length -or
        [math]::Abs(($fo.LastWriteTimeUtc - $fd.LastWriteTimeUtc).TotalSeconds) -gt 2) {
        $porCopiar += $r
        $bytes += $fo.Length
    }
}

Write-Host ''
Write-Host "Origen:  $Origen"
Write-Host "Destino: $Destino"
Write-Host ("Ficheros fuera de git: {0}; por copiar: {1} ({2:N2} GB)" -f $lista.Count, $porCopiar.Count, ($bytes / 1GB))
$porCopiar | Group-Object { ($_ -split '/')[0..[math]::Min(1, ($_ -split '/').Count - 2)] -join '/' } |
    Sort-Object Count -Descending | Select-Object -First 12 |
    ForEach-Object { Write-Host ("  {0,5}  {1}" -f $_.Count, $_.Name) }

if (-not $Ejecutar) {
    Write-Host ''
    Write-Host 'MODO SIMULACION: no se copia nada. Anade -Ejecutar para copiar.' -ForegroundColor Cyan
    exit 0
}

# Copia por carpeta: robocopy acepta la lista de ficheros de un directorio.
$opciones = @(
    '/FFT',         # marcas de tiempo con 2 s de tolerancia: Drive no da mas
    '/DST',         # ajusta el horario de verano
    '/R:2', '/W:5', # 2 reintentos, 5 s de espera
    '/NP',          # sin porcentaje por fichero
    '/NJH', '/NJS'
)
$registro = Join-Path $env:TEMP ('marea_negra_drive_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date))
$codigo = 0
foreach ($g in ($porCopiar | Group-Object { Split-Path ($_ -replace '/', '\') -Parent })) {
    $sub = $g.Name
    # @( ) obligatorio: con un solo fichero PowerShell da un texto suelto, no una lista, y robocopy
    # recibia el nombre mal (error 123, 18-10-2026).
    $nombres = @($g.Group | ForEach-Object { Split-Path ($_ -replace '/', '\') -Leaf })
    & robocopy.exe (Join-Path $Origen $sub) (Join-Path $Destino $sub) @nombres @opciones "/LOG+:$registro" | Out-Null
    $codigo = [math]::Max($codigo, $LASTEXITCODE)
}

Write-Host ''
Write-Host "Registro: $registro"

# Robocopy devuelve un mapa de bits: 0-7 es exito (0 = nada que hacer,
# 1 = copiados, 2 = extras en destino, 4 = desajustes). 8 o mas es fallo real.
if ($codigo -ge 8) {
    Write-Host "robocopy termino con codigo ${codigo}: hubo errores, revisa el registro." -ForegroundColor Red
    exit 1
}

Write-Host "robocopy termino con codigo $codigo (correcto)." -ForegroundColor Green
exit 0

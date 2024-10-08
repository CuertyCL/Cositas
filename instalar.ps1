# Script dedicado a la instalación de aplicaciones
# La aplicaciones tienen que descargarse obligatoriamente desde GitHub para un correcto funcionamiento
# del script

# El funcionamiento del script es el siguiente:
#
# - Primero se descarga la información del último release. La información viene contenida en un archivo Json
# - Se leerá el Json, y se buscará el URL especifico del archivo a descargar. Esto se logrará buscando el link que contenga
# el patrón de nombre especificado
# - Al ya tener el URL, se comenzará la descarga en el directorio TEMP
# - Una vez descargado, si el archivo es un instalador, simplemente se iniciará la instalación
# - Si el archivo es un comprimido ".zip", se descomprime en la carpeta Programs, luego se crea un acceso directo en caso de ser necesario,
# para finalmente añadir los valores necesarios al registro de windows.

# Función para saber el nombre de usuario de la sesión actual.
# El resultado se concatenará para la variable $appdata_dir
function Get-Username {
    $username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    for ($i = 0; $i -le $username.Length; $i++) {
        if ($username[$i] -eq "\") {
            break
        }
    }

    return $username.Substring($i+1)
}


# Variables relacionadas a directorios del sistema. En lo posible, no se ocuparán variables de entorno, debido a su volatilidad.
# Sin embargo, se asumirá que existen dichos directorios, ya que son escenciales para el comportamiento de windows.

[string] $appdata_dir = "C:\Users\" + (Get-Username) + "\Appdata"  # Directorio destinado a APPDATA. De esta variable derivan las siguientes.
[string] $temp_dir = $appdata_dir + "\Local\Temp"  # Directorio donde se descargarán los archivos temporalmente
[string] $program_dir = $appdata_dir + "\Local\Programs"  # Directorio donde se instalarán los programas portables.
[string] $start_menu_dir = $appdata_dir + "\Roaming\Microsoft\Windows\Start Menu\Programs\"  # Directorio donde se ubican los accesos directos de los programas.

# Variables relacionadas al registro de Windows
[string] $registry_uninstall_key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\"
[string] $registry_program_info = "HKCU:\Software\RepoInstaller\"

# Variables relacionadas a variables de entorno del Usuario
$user_path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)  # Obtiene la variable PATH de Usuario

# Variable que indica la ruta del Json que contiene información acerca de programas.
# Funciona como una especie de base de datos simple.
$programs_json = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/CuertyCL/Cositas/main/Programas.json" -UseBasicParsing)
$parsed_json = $programs_json.Content | ConvertFrom-Json

$modify_program_file = "https://raw.githubusercontent.com/CuertyCL/Cositas/main/modificar.ps1"

# Función que, en lo posible, devuelve la versión del programa.
# En caso de no encontrarla, se devuelve un texto vacío
function Get-Version {
    param (
        [string] $executable
    )

    $version = ((Get-ChildItem $executable).VersionInfo).ProductVersion 

    if ($null -eq $version) {
        return ""
    }

    return $version 
}


# Función que encuentra el tamaño del programa completo.
# Esto lo hace sumando recursivamente los archivos dentro del directorio del programa.
# IMPORTANTE: El valor obtenido es una aproximación, y no siempre refleja el tamaño real del programa
function Get-Size {
    param (
        [string] $program_install_dir
    )

    $size = ((Get-ChildItem ($program_install_dir+"\*") -Recurse) | Measure-Object -Sum Length | Select-Object Sum).Sum / 1024

    $kb_size = [math]::Round($size)
    
    return $kb_size  # El valor final se devuelve en KiloBytes
}


function Add-Shortcut {
    param (
        [string] $shortcut_name,
        [string] $executable
    )

    $WshShell = New-Object -COMObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($start_menu_dir+$shortcut_name+".lnk")
    $Shortcut.TargetPath = $executable
    $Shortcut.Save()
}


# Función que se encarga de instalar correctamente un programa.
function Install-Programs {
    param (
        [Parameter(Mandatory=$true)]
        $program_json_file, # Archivo con información de los programas.

        [Parameter(Mandatory=$true)]
        [int] $op,  # Opción ingresada por el usuario.

        [string] $program_name = $program_json_file.programs.name[$op-1],  # Nombre del programa

        [string] $program_exec = $program_json_file.programs.executable[$op-1],  # Nombre del ejecutable principal del programa

        [string] $program_author = $program_json_file.programs.author_repo[$op-1],  # Nombre del autor del repositorio del programa. No necesariamente el creador original

        [string] $program_repo = $program_json_file.programs.repo[$op-1],  # Nombre del repositorio del programa

        [string] $publisher = $program_json_file.programs.publisher[$op-1],  # Nombre del autor, organización, etc, del programa 

        [string] $treatment = $program_json_file.programs.treatment[$op-1],  # Determina como se debe tratar el archivo. El valor de esta variable determina el comportamiento de la función

        [string] $file_pattern = $program_json_file.programs.file_pattern[$op-1],  # Patrón que se debe buscar para encontrar el URL del programa

        [bool] $addShortcut = $program_json_file.programs.addShortcut[$op-1],  # Identifica si se debe crear un Acceso Directo

        [string] $arg_list = $program_json_file.programs.arg_list[$op-1]  # Opciones para usar en el instalador (En caso de que "treatment sea EXE").
    )

    if ($program_name -eq "Visual Studio Code") {
        $program_json_url = "https://code.visualstudio.com/sha"
    } else {
        $program_json_url = ("https://api.github.com/repos/" + $program_author + "/" + $program_repo + "/releases/latest")
    }

    $program_json = $temp_dir + "\programinfo.json"
    $program_file = ""

    if ($treatment -eq "EXE") {
        $program_file = $temp_dir + "\program.exe"
    } else {
        $program_file = $temp_dir + "\program.zip"
    }

    Write-Host "Instalando $program_name"
    Write-Host "Obteniendo informacion del Programa..."

    # Descarga el Archivo con información
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing -URI $program_json_url -OutFile $program_json 

    $jsonContent = Get-Content -Raw -Path $program_json | ConvertFrom-Json

    if ($program_name -eq "Visual Studio Code") {
        $product = $jsonContent.products | Where-Object { $_.platform.prettyname -eq 'Windows User Installer (x64)' -and $_.build -eq 'stable' }
        $program_url = $product.url
    } else {
        $product = $jsonContent.assets | Where-Object { $_.name -like $file_pattern }
        $program_url = $product.browser_download_url  # Asigna el URL encontrado a una variable 
    }

    Write-Host "Descargando Archivo del Programa..."
    Invoke-WebRequest -URI $program_url -OutFile $program_file

    
    # Instala el programa
    if ($treatment -eq "EXE") {
        Write-Host "Ejecutando Instalador..."
        Start-Process ($program_file) -Wait -ArgumentList ($arg_list)
    } else {
        Write-Host "Descomprimiendo Archivo..."
        Expand-Archive -Force -Path ($program_file) -DestinationPath ($program_dir+"\"+$program_name)

        
        
        # Se añade el directorio donde se ubica el ejecutable a la variable PATH.
        # Esta es la única ocasión donde se usan variables de entorno.
        Write-Host "Anadiendo Ruta a la Variable PATH..."
        
        # Primero se encuentra el directorio donde se ubica el ejecutable
        $exe_dir = (Get-ChildItem -Path ($program_dir+"\"+$program_name) -Recurse $program_exec).Directory.FullName
        
        # Agrega el directorio al PATH
        [System.Environment]::SetEnvironmentVariable("Path", $user_path+";"+$exe_dir, [System.EnvironmentVariableTarget]::User)

       
        # Agrega los valores necesarios en el registro de Windows
        Write-Host "Anadiendo registros..."

        # Crea la llave del programa en el registro, en caso de no existir
        $name_without_space = $program_name.Replace(" ", "")

        if (-NOT (Test-Path -Path ($registry_uninstall_key+$name_without_space))) {
            New-Item -Path $registry_uninstall_key -Name $name_without_space | Out-Null
        }

        $registry_program_path = $registry_uninstall_key+$name_without_space

        # Añade los valores correspondientes en la llave
        Set-ItemProperty -Path $registry_program_path -Name "DisplayName" -Value ($program_name) -Type "String"
        Set-ItemProperty -Path $registry_program_path -Name "DisplayIcon" -Value ($exe_dir+"\"+$program_exec) -Type "String"
        Set-ItemProperty -Path $registry_program_path -Name "DisplayVersion" -Value (Get-Version -executable ($exe_dir+"\"+$program_exec)) -Type "String"
        Set-ItemProperty -Path $registry_program_path -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd") -Type "String"
        Set-ItemProperty -Path $registry_program_path -Name "InstallLocation" -Value ($program_dir+"\"+$program_name) -Type "String"
        Set-ItemProperty -Path $registry_program_path -Name "EstimatedSize" -Value (Get-Size -program_install_dir ($program_dir+"\"+$program_name)) -Type "DWORD"

        if (-NOT ($null -eq $publisher)) {
            Set-ItemProperty -Path $registry_program_path -Name "Publisher" -Value ($publisher) -Type "String"
        }

        if ($addShortcut -eq $true) {
            Write-Host "Creando Acceso Directo..."
            Add-Shortcut -executable ($exe_dir+"\"+$program_exec) -shortcut_name $program_name
        }

        if ($treatment -eq "JAVA") {
            Write-Host "Configurando Variable JAVA_HOME..."
            $java_home = (Get-ChildItem ($program_dir+"\"+$program_name)).FullName
            [System.Environment]::SetEnvironmentVariable("JAVA_HOME", $java_home, [System.EnvironmentVariableTarget]::User)
        }

        if ($program_name -eq "Apache NetBeans") {
            "netbeans_jdkhome=$([System.Environment]::GetEnvironmentVariable("JAVA_HOME", [System.EnvironmentVariableTarget]::User))" >> ($program_dir+"\"+$program_name+"\netbeans\etc\netbeans.conf")
        }

        Invoke-WebRequest -Uri $modify_program_file -OutFile ($program_dir+"\"+$program_name+"\modificar.ps1")
        Set-ItemProperty -Path $registry_program_path -Name "ModifyPath" -Value ("powershell.exe -ExecutionPolicy Bypass -File `"" + $program_dir + "\" + $program_name + "\modificar.ps1`"") -Type "String"


        # A Continuación se definirán los valores relacionados a la información obtenida en el archivo "Programas.json".
        # Cada dato del archivo se alamcenará como un valor dentro del registro de windows. Esto con el fin de facilitar la reinstalación de los programas.
        # Estos valores serán guardados dentro de la clave "HKCU:\Software\RepoInstaller\{nombre del programa}".

        if (-NOT (Test-Path -Path ($registry_program_info))) {
            New-Item -Path "HKCU:\Software\" -Name "RepoInstaller" | Out-Null
        }

        if (-NOT (Test-Path -Path ($registry_program_info+$name_without_space))) {
            New-Item -Path $registry_program_info -Name $name_without_space | Out-Null
        }

        $addShortcutValue = if ($addShortcut) { 1 } else { 0 }

        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "Name" -Value $program_name -Type "String"
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "Author_Repo" -Value $program_author -Type "String"
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "Repo" -Value $program_repo -Type "String"
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "Publisher" -Value $publisher -Type "String"
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "Treatment" -Value $treatment -Type "String"
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "file_pattern" -Value $file_pattern -Type "String"
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "Arg_List" -Value $arg_list -Type "String"
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "AddShortcut" -Value $addShortcutValue -Type "DWORD"
    }
    
    # Elimina Archivos Temporales
    Remove-Item -Path $program_json
    Remove-Item -Path $program_file
}

# Función para obtener los números válidos
function Obtener-NumerosValidos {
    param (
        [Parameter(Mandatory = $true)]
        [int[]]$NumerosValidos
    )
    $numeros = @()
    
    Write-Host "Ingresa los números de los programas, separados por comas (por ejemplo, 1,2,3,4)"
    while ($true) {
        $entrada = Read-Host -Prompt " "
        $partes = $entrada -split ','

        $esValido = $true
        $numeros = @()  # Limpiar la lista antes de intentar llenarla con nueva entrada

        foreach ($parte in $partes) {
            if ($parte.Trim() -match '^\d+$' -and [int]$parte.Trim() -in $NumerosValidos) {
                $numeros += [int]$parte.Trim()
            } else {
                $esValido = $false
                break
            }
        }

        if ($esValido) {
            return $numeros  # Retornar la lista de números válidos
        }
    }
}

# Ejemplo de uso de la función
Write-Host "Que Programa quieres Instalar?"
for ($i = 0; $i -le ($parsed_json.programs.name.Length-1); $i++) {
    "$($i+1). " + $parsed_json.programs.name[$i]
}

$numerosValidos = 1..$parsed_json.programs.name.Length
$numerosElegidos = Obtener-NumerosValidos -NumerosValidos $numerosValidos

foreach ($numero in $numerosElegidos) {
    Install-Programs -program_json_file $parsed_json -op $numero
}

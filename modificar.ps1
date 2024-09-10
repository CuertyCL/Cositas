# Script dedicado a la manipulación de los archivos de los programas portables.
# El script será capáz de realizar 2 acciones: Comprimir y Reinstalar

# Este script debe ubicarse obligatoriamente en la carpeta raíz del programa.

# Comprimir: Comprime la carpeta raíz del programa en un archivo .zip, y así devolverlo a su estado portable.
# Al mismo tiempo, se eliminará dicha carpeta, generando así una especie de transformación más que crear una copia del mismo.

# Reinstalar: Vuelve a descargar el programa desde los repositorios, borra la carpeta raíz del programa, y descomprime el archivo descargado.
# Esta opción también puede servir para actualizar el programa, aunque hay que tener cuidado con los archivos de configuración que están
# dentro de la carpeta raíz


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

[string] $appdata_dir = "C:\Users\" + (Get-Username) + "\Appdata"  # Directorio destinado a APPDATA. De esta variable derivan las siguientes.
[string] $temp_dir = $appdata_dir + "\Local\Temp"  # Directorio donde se descargarán los archivos temporalmente
[string] $program_dir = $appdata_dir + "\Local\Programs"  # Directorio donde se instalarán los programas portables.
[string] $start_menu_dir = $appdata_dir + "\Roaming\Microsoft\Windows\Start Menu\Programs\"  # Directorio donde se ubican los accesos directos de los programas.


# Variables relacionadas al registro de Windows
[string] $registry_uninstall_key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\"
[string] $registry_program_info = "HKCU:\Software\RepoInstaller\"


# Función que verifica que la opción ingresada es un número entero, y además verifica que sea un número válido
function Get-IntegerOption {
    param (
        [int] $min,
        [int] $max
    )

    do {
        $number = 0
        $input = Read-Host " "

        # Intenta convertir el input a un entero
        $isValid = [int]::TryParse($input, [ref]$number)
        
        # Verifica que sea un entero y que esté dentro del rango
        if ($isValid -and $number -ge $min -and $number -le $max) {
            return $number
        } else {
            Out-Null
        }
    } while ($true)
}


# Función que se encarga de realizar la compresión del programa.
function Compress-Program {
    Write-Host "Comprimiendo Programa..."

    $compress_folder = ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::MyDocuments))
    $root_name = (Get-Item -Path $PSScriptRoot).name.Replace(" ", "")
    $root_name_with_space = (Get-Item -Path $PSScriptRoot).name

    Compress-Archive -Path ($PSScriptRoot+"\*") -DestinationPath ($compress_folder+"\"+$root_name+".zip") -Update

    Write-Host "Compresion Completada!"

    if (Test-Path -Path ($registry_uninstall_key+($root_name.Replace(" ", "")))) {
        Remove-Item -Path ($registry_uninstall_key+($root_name.Replace(" ", ""))) -Force -Recurse
    }

    if (Test-Path -Path ($registry_program_info+($root_name.Replace(" ", "")))) {
        Remove-Item -Path ($registry_program_info+($root_name.Replace(" ", ""))) -Force -Recurse
    }

    # Verifica si el archivo existe en "Menú Inicio". Solo borra el archivo, si se creó una subcarpeta,
    # esta no se borra
    $link_file_exist = Get-ChildItem -Path $start_menu_dir -Filter ($root_name_with_space+".lnk") -Recurse

    if ($link_file_exist) {
        Remove-Item -Path ($link_file_exist.FullName) -Force
    }

    # Crea un archivo temporal el cual se encarga de borrar el directorio del programa. Esto
    # con el proposito de borrar este script del directorio sin generar problemas
    $temp_file = $temp_dir+"\temp.ps1"
    
    New-Item -Path $temp_file -Force

    $temp_content = "Remove-Item -Force -Recurse -Path '$PSScriptRoot'"
    Set-Content -Path $temp_file -Force -Value $temp_content

    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File $temp_file" -WindowStyle Hidden
}

# Función que se encarga de reinstalar el programa. Tambien sirve para actualizar dicho programa
function Update-Program {
    Write-Host "Iniciando Proceso de Reinstalacion..."

    Write-Host "Borrando Programa..."
    Remove-Item "$PSScriptRoot\*" -Exclude "$PSScriptRoot\modificar.ps1" -Force



    $program_name = (Get-ItemProperty -Path "HKCU:\Software\RepoInstaller\WindowsTerminal").Name,  # Nombre del programa
    $program_author = (Get-ItemProperty -Path "HKCU:\Software\RepoInstaller\WindowsTerminal").Author_Repo,  # Nombre del autor del repositorio del programa. No necesariamente el creador original
    $program_repo = (Get-ItemProperty -Path "HKCU:\Software\RepoInstaller\WindowsTerminal").Repo,  # Nombre del repositorio del programa
    $publisher = (Get-ItemProperty -Path "HKCU:\Software\RepoInstaller\WindowsTerminal").Publisher,  # Nombre del autor, organización, etc, del programa 
    $treatment = (Get-ItemProperty -Path "HKCU:\Software\RepoInstaller\WindowsTerminal").Treatment,  # Determina como se debe tratar el archivo. El valor de esta variable determina el comportamiento de la función
    $file_pattern = (Get-ItemProperty -Path "HKCU:\Software\RepoInstaller\WindowsTerminal").file_pattern,  # Patrón que se debe buscar para encontrar el URL del programa
    $addShortcut = (Get-ItemProperty -Path "HKCU:\Software\RepoInstaller\WindowsTerminal").AddShortcut,  # Identifica si se debe crear un Acceso Directo
    $arg_list = (Get-ItemProperty -Path "HKCU:\Software\RepoInstaller\WindowsTerminal").Arg_List  # Opciones para usar en el instalador (En caso de que "treatment sea EXE").
    $executable = (Get-ItemProperty -Path "HKCU:\Software\RepoInstaller\WindowsTerminal").Executable  # Nombre del ejecutable principal del programa



    $program_json_url = ("https://api.github.com/repos/" + $program_author + "/" + $program_repo + "/releases/latest")



    if ($treatment -eq "EXE") {
        $program_file = $temp_dir + "\program.exe"
    } else {
        $program_file = $temp_dir + "\program.zip"
    }

    Write-Host "Reinstalando $program_name"
    Write-Host "Obteniendo informacion del Programa..."

    # Descarga el Archivo con información
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -URI $program_json_url -OutFile $program_json 

    $jsonContent = Get-Content -Raw -Path $program_json | ConvertFrom-Json

    $product = $jsonContent.assets | Where-Object { $_.name -like $file_pattern }
    $program_url = $product.browser_download_url  # Asigna el URL encontrado a una variable 

    Write-Host "Descargando Archivo del Programa..."
    Invoke-WebRequest -URI $program_url -OutFile $program_file

    
    # Instala el programa
    if ($treatment -eq "EXE") {
        Write-Host "Ejecutando Instalador..."
        Start-Process ($program_file) -ArgumentList ($arg_list)
    } else {
        Write-Host "Descomprimiendo Archivo..."
        Expand-Archive -Force -Path ($program_file) -DestinationPath ($PSScriptRoot)

        # Primero se encuentra el directorio donde se ubica el ejecutable
        $exe_dir = (Get-ChildItem -Path ($PSScriptRoot) -Recurse $executable).Directory.FullName
       
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
        Set-ItemProperty -Path $registry_program_path -Name "DisplayIcon" -Value ($exe_dir+"\"+$executable) -Type "String"
        Set-ItemProperty -Path $registry_program_path -Name "DisplayVersion" -Value (Get-Version -executable ($exe_dir+"\"+$executable)) -Type "String"
        Set-ItemProperty -Path $registry_program_path -Name "InstallDate" -Value (Get-Date -Format "yyyy-MM-dd") -Type "String"
        Set-ItemProperty -Path $registry_program_path -Name "InstallLocation" -Value ($PSScriptRoot) -Type "String"
        Set-ItemProperty -Path $registry_program_path -Name "EstimatedSize" -Value (Get-Size -program_install_dir ($PSScriptRoot)) -Type "DWORD"


        # Actualiza los registros que son volatiles a cambiar en un futuro
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "Arg_List" -Value $arg_list -Type "String"
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "AddShortcut" -Value $addShortcutValue -Type "DWORD"
        Set-ItemProperty -Path ($registry_program_info+$name_without_space) -Name "Executable" -Value $executable -Type "String"
    }
}

# Función que pregunta al usuario qué desea hacer
function Get-Option {
    Write-Host "Elige una Opcion."
    Write-Host "1. Comprimir Programa"
    Write-Host "2. Reinstalar/Actualizar Programa"

    $op = Get-IntegerOption -min 1 -max 2

    switch ($op) {
        1 { Compress-Program }
        2 { Update-Program }
    }
}

Get-Option

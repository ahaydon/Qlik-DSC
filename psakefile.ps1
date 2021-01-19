Properties {
    $project_name = "QlikResources"
    $output = "modules/$project_name"
    $pkg_path = ".package"
}

Task Clean {
    if (Test-Path $output) {
        Remove-Item $output -Force -Recurse
    }
}

Task Build -Depends Clean {
    $mod = Test-ModuleManifest -Path ./$project_name.psd1
    if ($null -eq $version) {
        $version = $mod.Version
    }
    Assert ($null -ne $version) 'version must not be null'

    $destinationRoot = New-Item -Path $output -ItemType Directory -Force
    $moduleVersion, $prerelease = $version -split '-'

    $functions = $mod.ExportedFunctions.Keys
    $dsc = (Import-LocalizedData -FileName "$project_name.psd1").DscResourcesToExport
    $nested = $mod.NestedModules | Where-Object { $_ }
    $scripts = $mod.Scripts | Where-Object { $_ }
    $files = @($mod.Path, $mod.RootModule) + @($nested) + @($scripts) + (Get-ChildItem ./DSCResources/*) | Resolve-Path -Relative
    $files | ForEach-Object {
        Write-Information "Copying $_" -InformationAction Continue
        $dest = Join-Path $destinationRoot $_
        New-Item -Path ($dest | Split-Path -Parent) -ItemType Directory -Force | Out-Null
        Copy-Item $_ $dest -Recurse
    }
    $manifest = Join-Path $destinationRoot "$project_name.psd1"
    $module_params = @{
        Path = $manifest
        ModuleVersion = $moduleVersion
        FunctionsToExport = $functions
        DscResourcesToExport = $dsc
        Prerelease = $prerelease
    }
    if ($nested) {
        $module_params.NestedModules = ($nested | Resolve-Path -Relative)
    }
    Update-ModuleManifest @module_params
}


Task Package -Depends Build {
    if (!(Test-Path $pkg_path)) {
        New-Item -Path $pkg_path -ItemType Directory | Out-Null
    }

    $package = Join-Path $pkg_path "$project_name.zip"
    if (Test-Path $package) {
        Remove-Item $package
    }

    Compress-Archive -Path $output/* -DestinationPath $package
}


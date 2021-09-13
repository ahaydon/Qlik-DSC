Properties {
    $project_name = "QlikResources"
    $output = "modules/$project_name"
    $pkg_path = ".package"
    $qrs_port = 4242
}

Task PSRemote {
    $script:instances = @()
    $instance_port = @{}
    $instance_files = Get-ChildItem -Path ./.kitchen/ -Filter *.yml
    foreach ($file in $instance_files) {
        if ($Matches = Select-String -Path $file -Pattern "^port: '(\d+)'") {
            [int]$port = $Matches.Matches[0].Groups[1].Value
            $instance_port.Add($file.BaseName, $port + 1)
        }
    }

    foreach ($instance in $instance_port.Keys) {
        if (Get-Command -Name Disable-WSManCertVerification -ErrorAction Ignore) {
            Disable-WSManCertVerification -All
        }

        $session_name = "kitchen_$instance"
        if ($session = Get-PSSession -Name $session_name -ErrorAction SilentlyContinue) {
            if ($session.State -ne 'Opened') {
                Remove-PSSession -Session $session
            }
            else {
                $script:instances += $session
                Continue
            }
        }

        $password = ConvertTo-SecureString -String 'vagrant' -AsPlainText -Force
        $vagrant_cred = New-Object System.Management.Automation.PSCredential('vagrant', $password)
        $so = New-PSSessionOption -SkipCACheck -SkipCNCheck
        Write-Information "$instance`: $($instance_port[$instance])" -InformationAction Continue
        $session = New-PSSession `
            -Name $session_name `
            -ComputerName localhost `
            -Credential $vagrant_cred `
            -EnableNetworkAccess `
            -Port $instance_port[$instance] `
            -UseSSL `
            -SessionOption $so `
            -Authentication Basic
        $script:instances += $session
        Remove-Variable -Name $session_name -Scope Global -ErrorAction SilentlyContinue
        Set-Variable -Name $session_name -Value $session -Scope Global
    }
}

Task ExportCert -Depends PSRemote {
    $kitchen_session = $script:instances[0]
    $result = Invoke-Command -Session $kitchen_session {
        $password = ConvertTo-SecureString -String 'vagrant' -AsPlainText -Force
        $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object Subject -eq 'CN=QlikClient'
        Export-PfxCertificate -cert $cert -FilePath "$env:TEMP\$($cert.Thumbprint).pfx" -password $password
    }
    Copy-Item $result.FullName client.pfx -FromSession $kitchen_session
}

Task ConnectQlik -Depends ExportCert {
    Get-Module Qlik-Cli | Remove-Module -Force
    Import-Module -Name Qlik-Cli -Scope Global

    $password = ConvertTo-SecureString -String 'vagrant' -AsPlainText -Force
    $cert = Get-PfxCertificate -FilePath client.pfx -Password $password
    $cert | Connect-Qlik -Computername https://localhost:$qrs_port -TrustAllCerts -Username INTERNAL\sa_api
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
    $files = @($mod.Path, $mod.RootModule) + @($nested) + @($scripts) + (Get-ChildItem ./DSCResources/*) + (Get-ChildItem ./DSCClassResources/*.ps1) | Resolve-Path -Relative
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


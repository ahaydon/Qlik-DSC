## About

Qlik-DSC is a PowerShell DSC (Desired State Configuration) module that provides resources for managing a Qlik Sense environment. The module uses [Qlik-Cli](https://github.com/ahaydon/Qlik-CLI-Windows) to communicate with the Qlik Sense APIs and manage settings in the Repository.

[![Build](https://img.shields.io/circleci/project/github/ahaydon/Qlik-DSC/master.svg)](https://circleci.com/gh/ahaydon/Qlik-DSC)
[![Release](https://img.shields.io/powershellgallery/v/QlikResources.svg?label=release)](https://www.powershellgallery.com/packages/QlikResources)
[![Downloads](https://img.shields.io/powershellgallery/dt/QlikResources.svg?color=blue)](https://www.powershellgallery.com/packages/QlikResources)
[![Platform](https://img.shields.io/powershellgallery/p/qlikresources)](https://www.powershellgallery.com/packages/QlikResources)
[![License](https://img.shields.io/github/license/ahaydon/Qlik-DSC.svg)](https://github.com/ahaydon/Qlik-DSC/blob/master/LICENSE)
[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)

## Installation

PowerShell 5.x is required to run Qlik-DSC. You can use the following command to check the version installed on your system.

```powershell
$PSVersionTable.PSVersion
```

Ensure you can run script by changing the execution policy, you can change this for the machine by running PowerShell as Administrator and executing the command

```powershell
Set-ExecutionPolicy RemoteSigned
```

The module can be installed from the PowerShell Gallery using NuGet, run the following commands to install the module.

```powershell
Get-PackageProvider -Name NuGet -ForceBootstrap
Install-Module Qlik-Cli
```

If you do not have internet access from the machine on which the module will be installed, it can be installed by downloading and extracting the files to C:\Program Files\WindowsPowerShell\Modules\QlikResources\, the module will then be loaded the next time you open a PowerShell console.

Once the module is installed you can view a list of available resources by using the Get-DscResource PowerShell command.

```powershell
Get-DscResource -Module QlikResources
```

## License

This software is made available "AS IS" without warranty of any kind. Qlik support agreement does not cover support for this software.

$ProjectRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$modulePath = Join-Path $ProjectRoot -ChildPath 'Private' | Join-Path -ChildPath 'Bootstrap.psm1'
Import-Module $modulePath -Force

class DummyProcess {
    [System.Diagnostics.ProcessStartInfo]
    $StartInfo

    [void]
    Start() {}

    [void]
    WaitForExit() {}
}

Describe "Start-SenseBootstrap" {
    BeforeAll {
        InModuleScope Bootstrap {
            Mock Get-ServicePath {
                $Service = $Name[0].SubString(9, $Name[0].Length - 16)
                return "C:\Program Files\Qlik\Sense\${Service}\${Service}.exe"
            }
            if (!(Get-Command -Name Get-Service -ErrorAction Ignore)) {
                # Workaround for testing on non-Windows platforms
                function Get-Service {
                }
                function Start-Service($Name) {
                }
                function Stop-Service {
                }
            }
            Mock Get-Service {
                return [PSCustomObject]@{
                    Status = 'Stopped'
                }
            }
            Mock Start-Service
            Mock Stop-Service
            Mock Start-Process
        }

        $proc = [DummyProcess]::new()
        $proc | Add-Member -MemberType NoteProperty -Name StandardOutput -Value (New-Object PSCustomObject)
        $proc.StandardOutput | Add-Member -MemberType ScriptMethod -Name ReadLine -Value { 'Waiting for certificates to be installed..' }
        $proc | Add-Member -MemberType NoteProperty -Name ExitCode -Value 1
        Mock New-Object -ModuleName Bootstrap -ParameterFilter { $TypeName -eq 'System.Diagnostics.Process' } { return $proc }.GetNewClosure()
    }

    Context 'Rim node' {
        Describe 'When running bootstrap for certificate distribution' {
            It 'Should wait for node registration to complete' {
                Start-SenseBootstrap -Service Repository

                Assert-MockCalled -CommandName Start-Service -ModuleName Bootstrap -ParameterFilter { $Name -eq 'QlikSenseServiceDispatcher' }
            }
        }
    }
}

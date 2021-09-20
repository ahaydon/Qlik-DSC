$ProjectRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$modulePath = Join-Path $ProjectRoot -ChildPath 'Private' | Join-Path -ChildPath 'Common.psm1'
Import-Module $modulePath -Force

class DummyResource {
    [string]
    $Name

    [nullable[bool]]
    $Enabled

    [DummyResource]
    Get() {
        return $this
    }

    [void]
    Set() {}

    [bool]
    Test() {
        return $true
    }
}

Describe "CompareProperties" {
    Context 'String' {
        Describe 'When property is not specified' {
            It 'should skip and return true' {
                $resource = [DummyResource]::new()
                $actual = @{ Name = 'Test' }
                $result = CompareProperties $resource $actual 'Name'

                $result | Should -BeTrue
            }
        }
    }
}

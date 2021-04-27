$ProjectRoot = Split-Path $PSScriptRoot -Parent | Split-Path -Parent
$modulePath = Join-Path $ProjectRoot -ChildPath 'DSCClassResources' | Join-Path -ChildPath 'QlikPackage.psm1'
Import-Module $modulePath -Force

Describe "New-QlikSharedPersistenceConfiguration" {
    BeforeAll {
        $password = ConvertTo-SecureString -String 'dbpassword' -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential('qliksenserepository', $password)
    }

    Context 'Credentials' {
        BeforeAll {
            $spcfile = New-QlikSharedPersistenceConfiguration `
                -Path (Join-Path (Get-PSDrive TestDrive).Root 'spc.cfg') `
                -DbCredential $credential `
                -QLogsWriterPassword $credential `
                -QLogsReaderPassword $credential
        }

        Describe 'When providing a DbCredential parameter' {
            It 'Should include DbUserName and DbUserPassword in the SPC file' {
                $spcfile | Should -FileContentMatch '<DbUserName>qliksenserepository</DbUserName>'
                $spcfile | Should -FileContentMatch '<DbUserPassword>dbpassword</DbUserPassword>'
            }
        }

        Describe 'When providing log reader and writer parameters' {
            It 'Should include the passwords in the SPC file' {
                $spcfile | Should -FileContentMatch '<QLogsWriterPassword>dbpassword</QLogsWriterPassword>'
                $spcfile | Should -FileContentMatch '<QLogsReaderPassword>dbpassword</QLogsReaderPassword>'
            }
        }
    }

    Context 'Cluster Paths' {
        Describe 'When only providing a RootDir' {
            BeforeAll {
                $spcfile = New-QlikSharedPersistenceConfiguration `
                    -Path (Join-Path (Get-PSDrive TestDrive).Root 'spc.cfg') `
                    -DbCredential $credential `
                    -RootDir '\\sense-cn\QlikShare'
            }

            It 'Should resolve other paths to default subdirectories' {
                $spcfile | Should -FileContentMatchExactly '<CreateCluster>true</CreateCluster>'
                $spcfile | Should -FileContentMatch '<RootDir>\\\\sense-cn\\QlikShare</RootDir>'
                $spcfile | Should -FileContentMatch '<AppsDir>\\\\sense-cn\\QlikShare\\Apps</AppsDir>'
                $spcfile | Should -FileContentMatch '<StaticContentRootDir>\\\\sense-cn\\QlikShare\\StaticContent</StaticContentRootDir>'
                $spcfile | Should -FileContentMatch '<ArchivedLogsDir>\\\\sense-cn\\QlikShare\\Archived Logs</ArchivedLogsDir>'

                $spcfile | Should -Not -FileContentMatch '<JoinCluster>true</JoinCluster>'
            }
        }

        Describe 'When providing relative paths' {
            BeforeAll {
                $spcfile = New-QlikSharedPersistenceConfiguration `
                    -Path (Join-Path (Get-PSDrive TestDrive).Root 'spc.cfg') `
                    -DbCredential $credential `
                    -RootDir '\\sense-cn\QlikShare' `
                    -AppsDir 'Dashboards' `
                    -StaticContentRootDir 'Common Files' `
                    -ArchivedLogsDir 'Logs\Archive'
            }

            It 'Should resolve the paths relative to RootDir' {
                $spcfile | Should -FileContentMatchExactly '<CreateCluster>true</CreateCluster>'
                $spcfile | Should -FileContentMatch '<RootDir>\\\\sense-cn\\QlikShare</RootDir>'
                $spcfile | Should -FileContentMatch '<AppsDir>\\\\sense-cn\\QlikShare\\Dashboards</AppsDir>'
                $spcfile | Should -FileContentMatch '<StaticContentRootDir>\\\\sense-cn\\QlikShare\\Common Files</StaticContentRootDir>'
                $spcfile | Should -FileContentMatch '<ArchivedLogsDir>\\\\sense-cn\\QlikShare\\Logs\\Archive</ArchivedLogsDir>'

                $spcfile | Should -Not -FileContentMatch '<JoinCluster>true</JoinCluster>'
            }
        }

        Describe 'When joining a cluster' {
            BeforeAll {
                $spcfile = New-QlikSharedPersistenceConfiguration `
                    -Path (Join-Path (Get-PSDrive TestDrive).Root 'spc.cfg') `
                    -DbCredential $credential
            }

            It 'Should not include paths in the SPC file' {
                $spcfile | Should -FileContentMatchExactly '<JoinCluster>true</JoinCluster>'
                $spcfile | Should -Not -FileContentMatch '<RootDir>.*</RootDir>'
                $spcfile | Should -Not -FileContentMatch '<AppsDir>.*</AppsDir>'
                $spcfile | Should -Not -FileContentMatch '<StaticContentRootDir>.*</StaticContentRootDir>'
                $spcfile | Should -Not -FileContentMatch '<ArchivedLogsDir>.*</ArchivedLogsDir>'

                $spcfile | Should -Not -FileContentMatch '<CreateCluster>true</CreateCluster>'
            }
        }
    }
}

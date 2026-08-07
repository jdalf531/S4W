Describe 'Get-DriveDatedFolders' {
    BeforeAll {
        function Import-ScriptFunctions {
            param(
                [Parameter(Mandatory)] [string] $Path,
                [Parameter(Mandatory)] [string[]] $Name
            )

            $content = Get-Content -LiteralPath $Path -Raw
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

            foreach ($functionName in $Name) {
                $functionAst = $ast.FindAll(
                    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName },
                    $true
                ) | Select-Object -First 1

                if (-not $functionAst) {
                    throw "Function '$functionName' not found in '$Path'."
                }

                . ([scriptblock]::Create($functionAst.Extent.Text))
            }
        }

        $script:ScriptPath = Join-Path $PSScriptRoot 'TransferDriveTool-V3.ps1'
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-DriveDatedFolders')
    }

    It 'returns dated subfolders sorted chronologically' {
        $root = Join-Path $TestDrive 'Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260805') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260806') -Force | Out-Null

        $result = Get-DriveDatedFolders -DriveUserRoot $root

        $result.Name | Should -Be @('20260805', '20260806', '20260807')
    }

    It 'excludes non-dated folders like Archive' {
        $root = Join-Path $TestDrive 'Ben'
        New-Item -ItemType Directory -Path (Join-Path $root '20260805') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'Archive') -Force | Out-Null

        $result = Get-DriveDatedFolders -DriveUserRoot $root

        $result.Name | Should -Be @('20260805')
    }

    It 'returns an empty array when the root does not exist' {
        $result = @(Get-DriveDatedFolders -DriveUserRoot (Join-Path $TestDrive 'DoesNotExist'))

        $result.Count | Should -Be 0
    }
}

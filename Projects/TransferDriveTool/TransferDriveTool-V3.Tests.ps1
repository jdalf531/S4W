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

    It 'returns an empty array when the root exists but has no dated subfolders' {
        $root = Join-Path $TestDrive 'Corey'
        New-Item -ItemType Directory -Path (Join-Path $root 'Archive') -Force | Out-Null

        $result = @(Get-DriveDatedFolders -DriveUserRoot $root)

        $result.Count | Should -Be 0
    }

    It 'returns an empty array when the root does not exist' {
        $result = @(Get-DriveDatedFolders -DriveUserRoot (Join-Path $TestDrive 'DoesNotExist'))

        $result.Count | Should -Be 0
    }
}

Describe 'Get-CompletedFileHashes' {
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
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-CompletedFileHashes')
    }

    It 'returns a hash per relative path for completed files' {
        $folder = Join-Path $TestDrive 'completed'
        New-Item -ItemType Directory -Path (Join-Path $folder 'sub') -Force | Out-Null
        Set-Content -Path (Join-Path $folder 'a.txt') -Value 'alpha' -NoNewline
        Set-Content -Path (Join-Path $folder 'sub\b.txt') -Value 'beta' -NoNewline

        $result = Get-CompletedFileHashes -FolderPath $folder

        $result.Keys | Sort-Object | Should -Be @('a.txt', 'sub\b.txt')
        $result['a.txt'] | Should -Be (Get-FileHash -LiteralPath (Join-Path $folder 'a.txt') -Algorithm SHA256).Hash
    }

    It 'excludes .partial and .partial.meta files' {
        $folder = Join-Path $TestDrive 'withpartial'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Set-Content -Path (Join-Path $folder 'done.txt') -Value 'finished' -NoNewline
        Set-Content -Path (Join-Path $folder 'inflight.txt.partial') -Value 'half' -NoNewline
        Set-Content -Path (Join-Path $folder 'inflight.txt.partial.meta') -Value "4`n0" -NoNewline

        $result = Get-CompletedFileHashes -FolderPath $folder

        $result.Keys | Should -Be @('done.txt')
    }

    It 'returns an empty hashtable when the folder does not exist' {
        $result = Get-CompletedFileHashes -FolderPath (Join-Path $TestDrive 'missing')

        $result.Count | Should -Be 0
    }
}

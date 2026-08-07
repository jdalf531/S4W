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

Describe 'Get-DateFolderCandidates' {
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
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-DateFolderCandidates')
    }

    It 'finds the unsuffixed and numbered folders for a date, sorted by suffix' {
        $root = Join-Path $TestDrive 'mpn\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-2') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-1') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260808') -Force | Out-Null

        $result = Get-DateFolderCandidates -DestUserRoot $root -Date '20260807'

        $result.Name | Should -Be @('20260807', '20260807-1', '20260807-2')
    }

    It 'returns an empty array when the destination root does not exist' {
        $result = @(Get-DateFolderCandidates -DestUserRoot (Join-Path $TestDrive 'nope') -Date '20260807')

        $result.Count | Should -Be 0
    }

    It 'returns an empty array when the root exists but has no matching date folder' {
        $root = Join-Path $TestDrive 'Ben2'
        New-Item -ItemType Directory -Path (Join-Path $root '20260808') -Force | Out-Null

        $result = Get-DateFolderCandidates -DestUserRoot $root -Date '20260807'

        $result.Count | Should -Be 0
    }
}

Describe 'Get-NextAvailableDateSuffix' {
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
        . Import-ScriptFunctions -Path $script:ScriptPath -Name @('Get-DateFolderCandidates', 'Get-NextAvailableDateSuffix')
    }

    It 'returns the plain date when no folder exists yet' {
        $root = Join-Path $TestDrive 'mpn2\Kevin'
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        Get-NextAvailableDateSuffix -DestUserRoot $root -Date '20260807' | Should -Be '20260807'
    }

    It 'increments to the next unused suffix' {
        $root = Join-Path $TestDrive 'mpn3\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-1') -Force | Out-Null

        Get-NextAvailableDateSuffix -DestUserRoot $root -Date '20260807' | Should -Be '20260807-2'
    }

    It 'throws once MaxSuffix is exhausted' {
        $root = Join-Path $TestDrive 'mpn4\Kevin'
        New-Item -ItemType Directory -Path (Join-Path $root '20260807') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root '20260807-1') -Force | Out-Null

        { Get-NextAvailableDateSuffix -DestUserRoot $root -Date '20260807' -MaxSuffix 1 } | Should -Throw
    }
}

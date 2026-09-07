param(
    [string]$Output = "web_export_context.md",
    [int]$MaxEmbeddedFileKB = 1536
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Godot Web export context exporter
#
# Put this script in the ROOT of the exported web folder, beside index.html:
#   .\web_mint_context.ps1
#
# Output:
#   web_export_context.md
#
# Purpose:
# - Capture the browser-facing side of a Godot Web export for AI/code review.
# - Inline HTML/JS/CSS/config/text files that are useful for integration work.
# - Keep large binaries such as .wasm/.pck and images tree-only.
# - Never inline obvious secret files or private-key containers.
#
# This is intentionally separate from godot_mint_context.ps1:
# - godot_mint_context.ps1 describes the SOURCE Godot project.
# - web_mint_context.ps1 describes the EXPORTED browser build.
#
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.
# ASCII-only script source; Markdown uses ~~~ fences.
# ---------------------------------------------------------------------------

$ScriptFileName = Split-Path -Leaf $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

$IndexHtml = Join-Path $ProjectRoot "index.html"
if (-not (Test-Path -LiteralPath $IndexHtml)) {
    throw "index.html was not found beside this script. Put web_mint_context.ps1 in the exported web root."
}

$OutputPath = Join-Path $ProjectRoot $Output
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$MaxEmbeddedFileBytes = $MaxEmbeddedFileKB * 1024

# ---------------------------------------------------------------------------
# Exclusions and safety
# ---------------------------------------------------------------------------

$ExcludedDirectoryNames = @(
    ".git",
    ".hg",
    ".svn",
    ".vscode",
    ".idea",
    ".cache",
    "node_modules",
    "__pycache__",
    "tmp",
    "temp",
    "logs",
    "log",
    "backups",
    "backup"
)

$SensitiveExactFileNames = @(
    ".env",
    ".env.local",
    ".env.development",
    ".env.production",
    ".env.test",
    ".env.staging",
    "id_rsa",
    "id_ed25519"
)

$SensitiveExtensions = @(
    ".pem",
    ".key",
    ".p12",
    ".pfx",
    ".jks",
    ".keystore"
)

# Browser-build binaries/media that are useful to know about, but usually not
# useful to inline into AI context.
$TreeOnlyExtensions = @(
    ".wasm",
    ".pck",
    ".zip",
    ".gz",
    ".br",
    ".7z",
    ".tar",
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".gif",
    ".ico",
    ".svgz",
    ".mp3",
    ".ogg",
    ".wav",
    ".m4a",
    ".mp4",
    ".webm",
    ".woff",
    ".woff2",
    ".ttf",
    ".otf",
    ".map"
)

$EmbeddedExtensions = @(
    ".html",
    ".htm",
    ".js",
    ".mjs",
    ".cjs",
    ".css",
    ".scss",
    ".json",
    ".jsonc",
    ".webmanifest",
    ".xml",
    ".txt",
    ".md",
    ".yaml",
    ".yml",
    ".toml",
    ".ini",
    ".cfg",
    ".conf",
    ".csv",
    ".ts",
    ".tsx",
    ".jsx",
    ".sh",
    ".ps1"
)

$EmbeddedFileNames = @(
    "CNAME",
    "README",
    "README.md",
    "LICENSE",
    "LICENSE.md",
    ".nojekyll",
    ".gitignore",
    ".gitattributes",
    ".editorconfig",
    "_headers",
    "_redirects"
)

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------

function Get-RelativePath {
    param([string]$FullName)

    $root = [System.IO.Path]::GetFullPath($ProjectRoot)

    if (-not $root.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
        $root += [System.IO.Path]::DirectorySeparatorChar
    }

    $full = [System.IO.Path]::GetFullPath($FullName)

    $rootUri = New-Object System.Uri($root)
    $fullUri = New-Object System.Uri($full)
    $relativeUri = $rootUri.MakeRelativeUri($fullUri)

    return [System.Uri]::UnescapeDataString(
        $relativeUri.ToString()
    ).Replace("\", "/")
}

function Test-IsExcludedPath {
    param([string]$FullName)

    $relative = Get-RelativePath $FullName

    if ($relative -eq $Output) {
        return $true
    }

    if ($relative -eq $ScriptFileName) {
        return $true
    }

    $parts = $relative -split "/"

    foreach ($part in $parts) {
        if ($ExcludedDirectoryNames -contains $part) {
            return $true
        }
    }

    return $false
}

function Test-IsSensitiveFile {
    param([System.IO.FileInfo]$File)

    if ($SensitiveExactFileNames -contains $File.Name) {
        return $true
    }

    if ($File.Name.StartsWith(".env.", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    if ($SensitiveExtensions -contains $File.Extension.ToLowerInvariant()) {
        return $true
    }

    return $false
}

function Test-IsEmbeddedFile {
    param([System.IO.FileInfo]$File)

    if (Test-IsExcludedPath $File.FullName) {
        return $false
    }

    if (Test-IsSensitiveFile $File) {
        return $false
    }

    if ($File.Length -gt $MaxEmbeddedFileBytes) {
        return $false
    }

    if ($TreeOnlyExtensions -contains $File.Extension.ToLowerInvariant()) {
        return $false
    }

    if ($EmbeddedFileNames -contains $File.Name) {
        return $true
    }

    return $EmbeddedExtensions -contains $File.Extension.ToLowerInvariant()
}

function Get-LanguageTag {
    param([System.IO.FileInfo]$File)

    switch ($File.Extension.ToLowerInvariant()) {
        ".html"        { return "html" }
        ".htm"         { return "html" }
        ".js"          { return "javascript" }
        ".mjs"         { return "javascript" }
        ".cjs"         { return "javascript" }
        ".ts"          { return "typescript" }
        ".tsx"         { return "tsx" }
        ".jsx"         { return "jsx" }
        ".css"         { return "css" }
        ".scss"        { return "scss" }
        ".json"        { return "json" }
        ".jsonc"       { return "jsonc" }
        ".webmanifest" { return "json" }
        ".xml"         { return "xml" }
        ".yaml"        { return "yaml" }
        ".yml"         { return "yaml" }
        ".toml"        { return "toml" }
        ".ini"         { return "ini" }
        ".cfg"         { return "ini" }
        ".conf"        { return "text" }
        ".csv"         { return "csv" }
        ".md"          { return "markdown" }
        ".sh"          { return "bash" }
        ".ps1"         { return "powershell" }
        default        { return "text" }
    }
}

function Get-AllProjectFiles {
    return @(
        Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force |
            Where-Object { -not (Test-IsExcludedPath $_.FullName) } |
            Sort-Object { Get-RelativePath $_.FullName }
    )
}

# ---------------------------------------------------------------------------
# Tree
# ---------------------------------------------------------------------------

function Get-TreeLines {
    param([System.IO.FileInfo[]]$Files)

    $rootName = Split-Path $ProjectRoot -Leaf
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($rootName + "/")

    $tree = @{}

    foreach ($file in $Files) {
        $relative = Get-RelativePath $file.FullName
        $parts = $relative -split "/"
        $node = $tree

        foreach ($part in $parts) {
            if (-not $node.ContainsKey($part)) {
                $node[$part] = @{}
            }

            $node = $node[$part]
        }
    }

    function Add-TreeNodeLines {
        param(
            [hashtable]$Node,
            [string]$Prefix
        )

        $names = @($Node.Keys | Sort-Object)

        for ($i = 0; $i -lt $names.Count; $i++) {
            $name = $names[$i]
            $isLast = ($i -eq ($names.Count - 1))
            $child = $Node[$name]
            $isDirectory = ($child.Count -gt 0)

            if ($isLast) {
                $branch = "\-- "
            }
            else {
                $branch = "|-- "
            }

            if ($isDirectory) {
                $suffix = "/"
            }
            else {
                $suffix = ""
            }

            $lines.Add($Prefix + $branch + $name + $suffix)

            if ($isDirectory) {
                if ($isLast) {
                    $nextPrefix = $Prefix + "    "
                }
                else {
                    $nextPrefix = $Prefix + "|   "
                }

                Add-TreeNodeLines -Node $child -Prefix $nextPrefix
            }
        }
    }

    Add-TreeNodeLines -Node $tree -Prefix ""
    return $lines
}

# ---------------------------------------------------------------------------
# High-signal summaries
# ---------------------------------------------------------------------------

function Get-GitSummary {
    $lines = New-Object System.Collections.Generic.List[string]

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue

    if ($null -eq $gitCommand) {
        $lines.Add("git executable not found.")
        return $lines
    }

    try {
        $inside = (& git -C $ProjectRoot rev-parse --is-inside-work-tree 2>$null)

        if ($LASTEXITCODE -ne 0 -or $inside -ne "true") {
            $lines.Add("Not detected as a Git worktree.")
            return $lines
        }

        $branch = (& git -C $ProjectRoot branch --show-current 2>$null)
        $head = (& git -C $ProjectRoot rev-parse --short HEAD 2>$null)
        $remote = (& git -C $ProjectRoot remote get-url origin 2>$null)

        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = "<detached>"
        }

        if ([string]::IsNullOrWhiteSpace($head)) {
            $head = "<unknown>"
        }

        $lines.Add("Branch: " + $branch)
        $lines.Add("HEAD: " + $head)

        if (-not [string]::IsNullOrWhiteSpace($remote)) {
            $lines.Add("Origin: " + $remote)
        }

        $lines.Add("")
        $lines.Add("Status:")

        $status = @(& git -C $ProjectRoot status --short 2>$null)

        if ($status.Count -eq 0) {
            $lines.Add("<clean>")
        }
        else {
            foreach ($line in $status) {
                $lines.Add($line)
            }
        }
    }
    catch {
        $lines.Add("Unable to read Git metadata: " + $_.Exception.Message)
    }

    return $lines
}

function Get-IndexHtmlSummary {
    $results = New-Object System.Collections.Generic.List[string]

    try {
        $content = [System.IO.File]::ReadAllText($IndexHtml)
    }
    catch {
        $results.Add("<unable to read index.html>")
        return $results
    }

    $patterns = @(
        '<script\b[^>]*\bsrc\s*=\s*["''][^"'']+["''][^>]*>',
        '<link\b[^>]*\bhref\s*=\s*["''][^"'']+["''][^>]*>',
        '<meta\b[^>]*>',
        '<canvas\b[^>]*>',
        'navigator\.serviceWorker[^;]*;?',
        'new\s+Engine\s*\([^;]*;?',
        'Engine\([^;]*;?'
    )

    $seen = @{}

    foreach ($pattern in $patterns) {
        $matches = [regex]::Matches(
            $content,
            $pattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        foreach ($match in $matches) {
            $value = ($match.Value -replace '\s+', ' ').Trim()

            if ($value.Length -gt 300) {
                $value = $value.Substring(0, 300) + "..."
            }

            if (-not $seen.ContainsKey($value)) {
                $seen[$value] = $true
                $results.Add("- " + $value)
            }
        }
    }

    if ($results.Count -eq 0) {
        $results.Add("<no script/link/meta/canvas/engine markers detected>")
    }

    return $results
}

function Get-BrowserIntegrationSurface {
    param([System.IO.FileInfo[]]$TextFiles)

    $results = New-Object System.Collections.Generic.List[string]
    $maxEntries = 300

    # These are the browser APIs/integration hooks most relevant to ads,
    # analytics, custom JS bridges, service workers, storage, and networking.
    $pattern = '(?i)(magicads|rewarded|advert|fetch\s*\(|XMLHttpRequest|WebSocket|postMessage|addEventListener\s*\(|serviceWorker|localStorage|sessionStorage|indexedDB|window\.|document\.|navigator\.|JavaScriptBridge|Engine\b|Godot\b)'

    foreach ($file in $TextFiles) {
        if ($results.Count -ge $maxEntries) {
            break
        }

        try {
            $lines = [System.IO.File]::ReadAllLines($file.FullName)
        }
        catch {
            continue
        }

        for ($i = 0; $i -lt $lines.Length; $i++) {
            if ($lines[$i] -notmatch $pattern) {
                continue
            }

            $line = $lines[$i].Trim()

            if ($line.Length -gt 400) {
                $line = $line.Substring(0, 400) + "..."
            }

            $relative = Get-RelativePath $file.FullName
            $results.Add("- " + $relative + ":" + ($i + 1) + ": " + $line)

            if ($results.Count -ge $maxEntries) {
                break
            }
        }
    }

    if ($results.Count -eq 0) {
        $results.Add("<no browser integration markers detected>")
    }

    return $results
}

function Get-FileInventory {
    param([System.IO.FileInfo[]]$Files)

    $results = New-Object System.Collections.Generic.List[string]

    foreach ($file in $Files) {
        $relative = Get-RelativePath $file.FullName
        $size = $file.Length
        $kind = "tree-only"

        if (Test-IsSensitiveFile $file) {
            $kind = "sensitive"
        }
        elseif (Test-IsEmbeddedFile $file) {
            $kind = "embedded"
        }
        elseif ($file.Length -gt $MaxEmbeddedFileBytes) {
            $kind = "too-large"
        }
        elseif ($TreeOnlyExtensions -contains $file.Extension.ToLowerInvariant()) {
            $kind = "binary/media"
        }

        $results.Add("- " + $relative + " | " + $size + " bytes | " + $kind)
    }

    return $results
}

# ---------------------------------------------------------------------------
# Collect
# ---------------------------------------------------------------------------

$AllFiles = @(Get-AllProjectFiles)

$EmbeddedFiles = @(
    $AllFiles | Where-Object { Test-IsEmbeddedFile $_ }
)

$TreeOnlyFiles = @(
    $AllFiles | Where-Object { -not (Test-IsEmbeddedFile $_) }
)

$TextFilesForSurface = @(
    $EmbeddedFiles | Where-Object {
        $ext = $_.Extension.ToLowerInvariant()
        $ext -eq ".html" -or
        $ext -eq ".htm" -or
        $ext -eq ".js" -or
        $ext -eq ".mjs" -or
        $ext -eq ".cjs" -or
        $ext -eq ".ts" -or
        $ext -eq ".tsx" -or
        $ext -eq ".jsx"
    }
)

# Put browser entrypoints and integration files first.
$OrderedEmbeddedFiles = @(
    $EmbeddedFiles |
        Sort-Object `
            @{ Expression = {
                $relative = Get-RelativePath $_.FullName

                if ($relative -eq "index.html") { return 0 }
                if ($relative -eq "CNAME") { return 1 }
                if ($relative -eq "_headers") { return 2 }
                if ($relative -eq "_redirects") { return 2 }
                if ($relative -like "*.webmanifest") { return 3 }
                if ($relative -eq "index.js") { return 4 }
                if ($relative -like "*.js") { return 5 }
                if ($relative -like "*.css") { return 6 }

                return 10
            } }, `
            @{ Expression = { Get-RelativePath $_.FullName } }
)

$GitSummary = @(Get-GitSummary)
$IndexHtmlSummary = @(Get-IndexHtmlSummary)
$BrowserIntegrationSurface = @(Get-BrowserIntegrationSurface -TextFiles $TextFilesForSurface)
$FileInventory = @(Get-FileInventory -Files $AllFiles)

# ---------------------------------------------------------------------------
# Write Markdown
# ---------------------------------------------------------------------------

$builder = New-Object System.Text.StringBuilder

[void]$builder.AppendLine("# Godot Web Export Context")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("> Generated by web_mint_context.ps1.")
[void]$builder.AppendLine("> Browser-facing snapshot of an exported Godot Web build.")
[void]$builder.AppendLine("> Large binaries/media are listed but not embedded; obvious secret files are never embedded.")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("- Export root: **$(Split-Path $ProjectRoot -Leaf)**")
[void]$builder.AppendLine("- Exported: **$(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")**")
[void]$builder.AppendLine("- Total included paths: **$($AllFiles.Count)**")
[void]$builder.AppendLine("- Embedded text/source files: **$($EmbeddedFiles.Count)**")
[void]$builder.AppendLine("- Tree-only/skipped-content files: **$($TreeOnlyFiles.Count)**")
[void]$builder.AppendLine("- Max embedded file size: **$MaxEmbeddedFileKB KB**")
[void]$builder.AppendLine("")

[void]$builder.AppendLine("## Safety Note")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("Obvious .env/private-key files are not embedded.")
[void]$builder.AppendLine("Hard-coded secrets inside ordinary HTML/JS/config files cannot be guaranteed to be detected.")
[void]$builder.AppendLine("Review the generated Markdown before sharing it outside your own workflow.")
[void]$builder.AppendLine("")

[void]$builder.AppendLine("## Git Snapshot")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("~~~text")
foreach ($line in $GitSummary) {
    [void]$builder.AppendLine($line)
}
[void]$builder.AppendLine("~~~")
[void]$builder.AppendLine("")

[void]$builder.AppendLine("## index.html Surface")
[void]$builder.AppendLine("")
foreach ($line in $IndexHtmlSummary) {
    [void]$builder.AppendLine($line)
}
[void]$builder.AppendLine("")

[void]$builder.AppendLine("## Browser / Ad Integration Surface")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("Matches browser APIs and integration markers that may matter for rewarded ads, custom JS bridges, networking, storage, analytics, or service workers.")
[void]$builder.AppendLine("")
foreach ($line in $BrowserIntegrationSurface) {
    [void]$builder.AppendLine($line)
}
[void]$builder.AppendLine("")

[void]$builder.AppendLine("## Project Tree")
[void]$builder.AppendLine("")
[void]$builder.AppendLine("~~~text")
foreach ($line in (Get-TreeLines -Files $AllFiles)) {
    [void]$builder.AppendLine($line)
}
[void]$builder.AppendLine("~~~")
[void]$builder.AppendLine("")

[void]$builder.AppendLine("## File Inventory")
[void]$builder.AppendLine("")
foreach ($line in $FileInventory) {
    [void]$builder.AppendLine($line)
}
[void]$builder.AppendLine("")

if ($TreeOnlyFiles.Count -gt 0) {
    [void]$builder.AppendLine("## Tree-only / Non-embedded Files")
    [void]$builder.AppendLine("")
    [void]$builder.AppendLine("These paths exist but their contents were not inlined because they are sensitive, binary/media, too large, or not selected as browser-facing text.")
    [void]$builder.AppendLine("")

    foreach ($file in $TreeOnlyFiles) {
        $relative = Get-RelativePath $file.FullName
        $reason = "not selected"

        if (Test-IsSensitiveFile $file) {
            $reason = "sensitive"
        }
        elseif ($file.Length -gt $MaxEmbeddedFileBytes) {
            $reason = "too large"
        }
        elseif ($TreeOnlyExtensions -contains $file.Extension.ToLowerInvariant()) {
            $reason = "binary/media"
        }

        [void]$builder.AppendLine("- " + $relative + " (" + $reason + ")")
    }

    [void]$builder.AppendLine("")
}

[void]$builder.AppendLine("## Embedded Web Files")
[void]$builder.AppendLine("")

foreach ($file in $OrderedEmbeddedFiles) {
    $relative = Get-RelativePath $file.FullName
    $language = Get-LanguageTag $file

    try {
        $content = [System.IO.File]::ReadAllText($file.FullName)
    }
    catch {
        $content = "<Unable to read file as text: $($_.Exception.Message)>"
    }

    [void]$builder.AppendLine("### " + $relative)
    [void]$builder.AppendLine("")
    [void]$builder.AppendLine("~~~" + $language)
    [void]$builder.Append($content)

    if (-not $content.EndsWith([Environment]::NewLine) -and -not $content.EndsWith("`n")) {
        [void]$builder.AppendLine("")
    }

    [void]$builder.AppendLine("~~~")
    [void]$builder.AppendLine("")
}

[System.IO.File]::WriteAllText(
    $OutputPath,
    $builder.ToString(),
    $Utf8NoBom
)

Write-Host ""
Write-Host "Godot Web export context exported." -ForegroundColor Green
Write-Host "Output   : $OutputPath"
Write-Host "Total    : $($AllFiles.Count)"
Write-Host "Embedded : $($EmbeddedFiles.Count)"
Write-Host "Tree-only: $($TreeOnlyFiles.Count)"
Write-Host ""
Write-Host "Next: review the Markdown, then share web_export_context.md for integration analysis."

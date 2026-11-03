# Execute the actual placement resolver without downloading/installing anything.
$ErrorActionPreference = "Stop"
$tokens = $null
$errors = $null
$installer = Join-Path $PSScriptRoot "../install.ps1"
$ast = [Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) { throw "Installer parse errors: $errors" }
$resolver = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Resolve-SetupScope"
}, $true)
if (-not $resolver) { throw "Missing Resolve-SetupScope" }
Invoke-Expression $resolver.Extent.Text

$script:Answers = [Collections.Generic.Queue[string]]::new()
$script:PromptCount = 0
function Read-Host([string]$Prompt) {
    $script:PromptCount++
    if ($script:Answers.Count -eq 0) { throw "Unexpected prompt: $Prompt" }
    return $script:Answers.Dequeue()
}
function Assert-Equal($Actual, $Expected) {
    if ($Actual -ne $Expected) { throw "Expected '$Expected', got '$Actual'" }
}
function Assert-Rejected([scriptblock]$Call, [string]$Message) {
    $failure = $null
    try { & $Call | Out-Null } catch { $failure = "$_" }
    if (-not $failure -or $failure -notlike "*$Message*") { throw "Expected rejection containing '$Message', got '$failure'" }
}

# Interactive choice is independent of whether project-local is available.
$script:Answers.Enqueue("1")
Assert-Equal (Resolve-SetupScope "" $true "" $false) "user"
$script:Answers.Enqueue("2")
Assert-Rejected { Resolve-SetupScope "" $true "" $true } "needs a Git repository"
$script:Answers.Enqueue("2")
Assert-Rejected { Resolve-SetupScope "" $true "C:\repo" $false } "need Node.js"
$script:Answers.Enqueue("2")
Assert-Equal (Resolve-SetupScope "" $true "C:\repo" $true) "repository"
# Invalid input must not silently approve global placement.
$script:Answers.Enqueue("invalid")
$script:Answers.Enqueue("2")
Assert-Equal (Resolve-SetupScope "" $true "C:\repo" $true) "repository"
Assert-Equal $script:PromptCount 6

# No terminal/--yes is not consent, while explicit scopes remain usable.
$before = $script:PromptCount
Assert-Rejected { Resolve-SetupScope "" $false "C:\repo" $true } "-Scope user or -Scope repository"
Assert-Equal (Resolve-SetupScope "user" $false "" $false) "user"
Assert-Equal (Resolve-SetupScope "repository" $false "C:\repo" $true) "repository"
Assert-Rejected { Resolve-SetupScope "repository" $false "" $true } "needs a Git repository"
Assert-Rejected { Resolve-SetupScope "repository" $false "C:\repo" $false } "need Node.js"
Assert-Equal $script:PromptCount $before
Write-Host "Installer scope contracts passed"

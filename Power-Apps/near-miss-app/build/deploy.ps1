<#
  deploy.ps1 — export / pack / import helper for the Near-Miss Safety solution (Windows PowerShell).
  Requires the Power Platform CLI:  dotnet tool install --global Microsoft.PowerApps.CLI.Tool
  Usage examples:
    ./deploy.ps1 -Action pack-import -Env "https://<dev>.crm.dynamics.com"
    ./deploy.ps1 -Action export      -Env "https://<dev>.crm.dynamics.com"
#>
param(
  [ValidateSet("auth","export","pack-import","promote")] [string]$Action = "pack-import",
  [string]$Env = "https://your-dev.crm.dynamics.com",
  [string]$SolutionName = "NearMissSafety",
  [string]$SrcFolder = "src/solution/src",
  [string]$OutFolder = "out"
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutFolder | Out-Null

switch ($Action) {
  "auth"        { pac auth create --environment $Env }

  # Capture changes made in Studio back into source control (run this after editing tables/app in Dev).
  "export"      {
    pac solution export --name $SolutionName --path "$OutFolder/$SolutionName.zip" --managed false --overwrite
    pac solution unpack --zipfile "$OutFolder/$SolutionName.zip" --folder $SrcFolder --packagetype Unmanaged --allowDelete
  }

  # Build the solution from source and import into the target Dev/Test env.
  "pack-import" {
    pac solution pack --zipfile "$OutFolder/$SolutionName.zip" --folder $SrcFolder --packagetype Unmanaged
    pac solution import --path "$OutFolder/$SolutionName.zip" --activate-plugins --force-overwrite
    pac solution publish
  }

  # Produce a MANAGED build for promotion to Test/Prod (or use Power Platform Pipelines instead).
  "promote"     {
    pac solution pack --zipfile "$OutFolder/${SolutionName}_managed.zip" --folder $SrcFolder --packagetype Managed
    Write-Host "Managed solution written to $OutFolder/${SolutionName}_managed.zip — import via Pipelines or the target env."
  }
}

#Requires -Version 7
# Single entry point for the test suite.
#
# Imports an explicit minimum version: Windows ships Pester 3.4.0 in System32,
# which cannot be uninstalled and whose syntax is incompatible with Pester 5+.
# Relying on default resolution would load the wrong one.
Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

$config = New-PesterConfiguration
$config.Run.Path         = $PSScriptRoot
$config.Output.Verbosity = 'Detailed'
$config.Run.Exit         = $true

Invoke-Pester -Configuration $config

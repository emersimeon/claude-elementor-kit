@echo off
REM Wrapper so Windows users can double-click to install.
REM Runs INSTALL.ps1 with the right execution policy.
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL.ps1"

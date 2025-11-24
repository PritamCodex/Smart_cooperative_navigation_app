flutter build apk --release --verbose *>&1 | Tee-Object -FilePath full_build.log
Write-Host "Build log saved to full_build.log"
Get-Content full_build.log | Select-String -Pattern "error|fail|exception" -Context 2 | Out-File -FilePath build_errors_filtered.log
Write-Host "Filtered errors saved to build_errors_filtered.log"

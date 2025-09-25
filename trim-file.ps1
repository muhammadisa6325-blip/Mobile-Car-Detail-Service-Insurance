$content = Get-Content 'contracts\vehicle-condition-tracker.clar' -Raw
$content = $content.TrimEnd()
[System.IO.File]::WriteAllText('contracts\vehicle-condition-tracker.clar', $content)
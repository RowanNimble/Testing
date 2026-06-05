git fetch --prune
git checkout main
git pull
git branch --merged main | ForEach-Object {
    $branch = $_.Trim()
    if ($branch -and $branch -ne "main" -and -not $branch.StartsWith("*")) {
        git branch -d $branch
    }
}

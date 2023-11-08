param (
    [string]$bucket = ''
)

if ([string]::IsNullOrWhiteSpace($bucket)) {
    $bucket = "$PSScriptRoot/../bucket"
    Write-Verbose -Verbose "Using default bucket path '$bucket'."
}

function Get-JsonPaths {
    param (
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "The provided path is not a directory."
        return @()
    }

    return Get-ChildItem -Path $Path -Filter *.json | Select-Object -ExpandProperty FullName
}

function Get-JsonContentAsDictionary {
    param (
        [string[]]$Paths
    )

    $dict = @{}
    foreach ($path in $Paths) {
        try {
            $content = Get-Content -Path $path -Raw | ConvertFrom-Json -ErrorAction Stop
            $dict[$path] = $content
        }
        catch {
            Write-Error "Failed to parse JSON content from ${path}: $_"
        }
    }

    return $dict
}

function Convert-GitHubUrlToRepoId {
    param (
        [string]$GithubUrl
    )

    $ownerRepoRegex = 'github\.com[/:](?<owner>[^/]+)/(?<repo>[^/.]+)'
    if ($GithubUrl -match $ownerRepoRegex) {
        $owner = $Matches['owner']
        $repo = $Matches['repo']
        return "$owner/$repo"
    }
    else {
        Write-Error "Invalid GitHub URL format."
        return $null
    }
}
function Get-GitHubUrlFromData {
    param (
        [PSCustomObject]$Data
    )

    if ($Data.psobject.properties.name -contains 'checkver') {
        if ($Data.checkver.psobject.properties.name -contains 'github') {
            return $Data.checkver.github
        }
    }

    return $null
}

function Convert-GitHubUrlToRepoId {
    param (
        [string]$GithubUrl
    )

    $ownerRepoRegex = 'github\.com[/:](?<owner>[^/]+)/(?<repo>[^/.]+)'
    if ($GithubUrl -match $ownerRepoRegex) {
        $owner = $Matches['owner']
        $repo = $Matches['repo']
        return "$owner/$repo"
    }
    else {
        Write-Error "Invalid GitHub URL format."
        return $null
    }
}
function Get-RepoIdForEachPath {
    param (
        [hashtable]$Hashtable
    )

    $RepoIds = @{}
    foreach ($path in $Hashtable.Keys) {
        $Data = $Hashtable[$path]
        $repoUrl = Get-GitHubUrlFromData -Data $Data
        if ($repoUrl) {
            $RepoId = Convert-GitHubUrlToRepoId -githubUrl $repoUrl
            $RepoIds.Add($path, $RepoId)
        }
    }
    return $RepoIds
}

function Update-Bucket {
    param (
        [string]$Bucket
    )
    $bucketPaths = Get-JsonPaths $Bucket
    Write-Verbose -Verbose "Bucket paths: $($bucketPaths | ConvertTo-Json -Depth 100)"
    Write-Verbose -Verbose "Parsing JSON content from $($bucketPaths.Count) files."
    $bucketContent = Get-JsonContentAsDictionary $bucketPaths
    Write-Verbose -Verbose "Bucket content: $($bucketContent | ConvertTo-Json -Depth 100)"

    $repoIds = Get-RepoIdForEachPath $bucketContent
    Write-Verbose -Verbose "Repo IDs: $($repoIds | ConvertTo-Json -Depth 100)"

    $uniqueRepoIds = Get-UniqueRepoIds $repoIds
    Write-Verbose -Verbose "Unique repo IDs: $($uniqueRepoIds | ConvertTo-Json -Depth 100)"
    Write-Verbose -Verbose "Getting latest tags for $($RepoIds.Count) repos."

    $latestTags = Get-LatestTagsForRepoList $uniqueRepoIds
    Write-Verbose -Verbose "Latest tags: $($latestTags | ConvertTo-Json -Depth 100)"
}

function Get-UniqueRepoIds {
    param (
        [hashtable]$RepoIds
    )
    $uniqueRepoIds = $RepoIds.Values | Sort-Object -Unique
    return $uniqueRepoIds
}

function Get-LatestTagForRepo {
    param (
        [string]$RepoId
    )

    try {
        $latestTag = gh api -X GET "repos/$RepoId/releases/latest" --jq '.tag_name'
        if ($latestTag) {
            return $latestTag
        } else {
            Write-Error "No releases found for $RepoId."
            return $null
        }
    } catch {
        Write-Error "Failed to get latest release for ${repoId}: $_"
        return $null
    }
}

function Get-LatestTagsForRepoList {
    param (
        [string[]]$RepoIds
    )

    $latestTags = @{}
    foreach ($repoId in $RepoIds) {
        $latestTag = Get-LatestTagForRepo -repoId $repoId
        if ($latestTag) {
            $latestTags[$repoId] = $latestTag
        } else {
            Write-Error "Failed to get latest tag for ${repoId}."
        }
    }

    return $latestTags
}

Update-Bucket $bucket

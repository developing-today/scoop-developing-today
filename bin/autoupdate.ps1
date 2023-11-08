#!/usr/bin/env pwsh

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

function Get-AutoUpdateUrl {
    param (
        [PSCustomObject]$Content,
        [string]$Architecture
    )
    if ($Content.autoupdate.PSObject.Properties[$Architecture]) {
        return $Content.autoupdate.PSObject.Properties[$Architecture].Value.url
    } else {
        Write-Verbose -Verbose "Architecture '$Architecture' does not exist in the autoupdate section."
        return $null
    }
}


function Convert-AutoUpdateUrlToVersion {
    param (
        [string]$AutoUpdateUrl,
        [string]$Version
    )
    return $AutoUpdateUrl -replace '\$version', $Version
}

function Join-PathWithLatestVersion {
    param (
        [hashtable]$PathToRepoIdMap,
        [hashtable]$LatestTags
    )

    $newPathToVersionMap = @{}

    foreach ($path in $PathToRepoIdMap.Keys) {
        $repoId = $PathToRepoIdMap[$path]
        if ($LatestTags.ContainsKey($repoId)) {
            $newPathToVersionMap[$path] = $LatestTags[$repoId]
        }
    }

    return $newPathToVersionMap
}

function Update-Version {
    param (
        [string]$Path,
        [string]$Version,
        [PSCustomObject]$Content
    )
    $Content.version = $Version

    foreach ($Architecture in $Content.architecture.PSObject.Properties.Name) {
        $urlTemplate = Get-AutoUpdateUrl $Content $Architecture
        if ($urlTemplate -eq $null) {
            Write-Warning "Failed to get URL for architecture '$Architecture'."
            continue
        }
        $updatedUrl = Convert-AutoUpdateUrlToVersion $urlTemplate $Version
        if ($updatedUrl -eq $null) {
            Write-Warning "Failed to update URL for architecture '$Architecture'."
            continue
        }
        Write-Verbose -Verbose "Updating URL for architecture '$Architecture' to '$updatedUrl'."
        $Content.architecture.$Architecture.url = $updatedUrl
    }

    $Content | ConvertTo-Json -Depth 100 | Set-Content -Path $Path
}

function Update-PathVersions {
    param (
        [hashtable]$NewPathVersions,
        [hashtable]$Contents
    )

    foreach ($path in $NewPathVersions.Keys) {
        $version = $NewPathVersions[$path]
        $content = $Contents[$path]

        if ($null -eq $version) {
            Write-Warning "No version found for path $path"
            continue
        }
        if ($null -eq $content) {
            Write-Warning "No content found for path $path"
            continue
        }
        Update-Version $path $version $content
    }
}

function Update-Bucket {
    param (
        [string]$Bucket
    )
    $bucketPaths = Get-JsonPaths $Bucket
    Write-Verbose -Verbose "Bucket paths: $($bucketPaths | ConvertTo-Json -Depth 100)"
    Write-Verbose -Verbose "Parsing JSON content from $($bucketPaths.Count) files."
    $Content = Get-JsonContentAsDictionary $bucketPaths
    Write-Verbose -Verbose "Bucket content: $($Content | ConvertTo-Json -Depth 100)"

    $repoIds = Get-RepoIdForEachPath $Content
    Write-Verbose -Verbose "Repo IDs: $($repoIds | ConvertTo-Json -Depth 100)"

    $uniqueRepoIds = Get-UniqueRepoIds $repoIds
    Write-Verbose -Verbose "Unique repo IDs: $($uniqueRepoIds | ConvertTo-Json -Depth 100)"
    Write-Verbose -Verbose "Getting latest tags for $($RepoIds.Count) repos."

    $latestTags = Get-LatestTagsForRepoList $uniqueRepoIds
    Write-Verbose -Verbose "Latest tags: $($latestTags | ConvertTo-Json -Depth 100)"

    $NewPathVersions = Join-PathWithLatestVersion $repoIds $latestTags
    Write-Verbose -Verbose "New Path versions: $($NewPathVersions | ConvertTo-Json -Depth 100)"

    Write-Verbose -Verbose "Updating path versions."
    Update-PathVersions $NewPathVersions $Content
}

Update-Bucket $bucket

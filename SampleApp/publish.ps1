param(
    [string]$Tag = "latest"
)

# Check if Docker Hub credentials are set
if (-not $env:DOCKERHUB_USERNAME -or -not $env:DOCKERHUB_PASSWORD) {
    Write-Error "Error: Docker Hub credentials are not set. Please set DOCKERHUB_USERNAME and DOCKERHUB_PASSWORD environment variables."
    exit 1
}

# Log into Docker Hub
Write-Host "Logging into Docker Hub..."
$env:DOCKERHUB_PASSWORD | docker login --username $env:DOCKERHUB_USERNAME --password-stdin
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker login failed. Check your credentials."
    exit $LASTEXITCODE
}

# Define local image name and target repository tag using the provided parameter
$localImage = "sampleapp"
$repository = "$env:DOCKERHUB_USERNAME/sampleapp:$Tag"

# Tag the local image for Docker Hub
Write-Host "Tagging image '$localImage' as '$repository'..."
docker tag $localImage $repository
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to tag the image."
    exit $LASTEXITCODE
}

# Push the image to Docker Hub
Write-Host "Pushing image '$repository' to Docker Hub..."
docker push $repository
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to push the image."
    exit $LASTEXITCODE
}

Write-Host "Image pushed successfully to Docker Hub."
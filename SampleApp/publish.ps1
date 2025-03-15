param(
    [string]$Tag = "latest"
)

# Define Docker image name
$imageName = "sampleapp"

# Check if Docker Hub credentials are set
if (-not $env:TF_VAR_dockerhub_username -or -not $env:TF_VAR_dockerhub_password) {
    Write-Error "Error: Docker Hub credentials are not set. Please set TF_VAR_dockerhub_username and TF_VAR_dockerhub_password environment variables."
    exit 1
}

# Log into Docker Hub
Write-Host "Logging into Docker Hub..."
$env:TF_VAR_dockerhub_password | docker login --username $env:TF_VAR_dockerhub_username --password-stdin
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker login failed. Check your credentials."
    exit $LASTEXITCODE
}

# Build the Docker image for the current folder
Write-Host "Building Docker image '${imageName}:${Tag}' from the current directory..."
docker build -t "${imageName}:${Tag}" .
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker build failed."
    exit $LASTEXITCODE
}

# Define target repository tag using the provided parameter
$repository = "$env:TF_VAR_dockerhub_username/${imageName}:${Tag}"

# Tag the local image for Docker Hub
Write-Host "Tagging image '${imageName}:${Tag}' as '$repository'..."
docker tag "${imageName}:${Tag}" $repository
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

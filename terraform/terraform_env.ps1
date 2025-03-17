# Read arguments

if (-not ($args -contains "--destroy")) {
    $build_tag1 = $args[0]
    echo "Server image tag for slot 1: $build_tag1"
    
    $build_tag2 = $args[1]
    echo "Server image tag for slot 2: $build_tag2"
    
    if (-not $build_tag1) {
        Write-Error "<environment name> <server image tag> are expected as an argument."
        exit 1
    }

    if (-not $build_tag2) {
        Write-Error "<environment name> <server image tag> are expected as an argument."
        exit 1
    }
}


# Validate required environment variables.
if (-not $env:TF_VAR_dockerhub_username) {
    Write-Error "Environment variable TF_VAR_dockerhub_username is not set."
    exit 1
}
if (-not $env:TF_VAR_dockerhub_password) {
    Write-Error "Environment variable TF_VAR_dockerhub_password is not set."
    exit 1
}
if (-not $env:AWS_ACCESS_KEY_ID) {
    Write-Error "Environment variable AWS_ACCESS_KEY_ID is not set."
    exit 1
}
if (-not $env:AWS_SECRET_ACCESS_KEY) {
    Write-Error "Environment variable AWS_SECRET_ACCESS_KEY is not set."
    exit 1
}

# Determine mode from arguments
$dryRun = $false
$destroy = $false

if ($args -contains "--dry") {
    $dryRun = $true
}
if ($args -contains "--destroy") {
    $destroy = $true
}
if ($dryRun -and $destroy) {
    Write-Error "Cannot specify both --dry and --destroy options simultaneously."
    exit 1
}

# Call terraform based on args

./terraform.exe init

if ($dryRun) {
    echo "Executing Terraform plan (--dry)"
    ./terraform.exe plan -var="build_tag1=${build_tag1}" -var="build_tag2=${build_tag2}"
}
elseif ($destroy) {
    echo "Executing Terraform destroy (--destroy)"
    ./terraform.exe destroy -auto-approve var="build_tag1=a" -var="build_tag2=b"
}
else {
    echo "Executing Terraform apply"
    ./terraform.exe apply -auto-approve -var="build_tag1=${build_tag1}" -var="build_tag2=${build_tag2}"
}

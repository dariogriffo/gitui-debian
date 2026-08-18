gitui_VERSION=$1
BUILD_VERSION=$2
ARCH=${3:-amd64}  # Default to amd64 if no architecture specified

if [ -z "$gitui_VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <gitui_version> <build_version> [architecture]"
    echo "Example: $0 0.28.1 1 arm64"
    echo "Example: $0 0.28.1 1 all    # Build for all architectures"
    echo "Supported architectures: amd64, arm64, armhf, all"
    exit 1
fi

# Function to map Ubuntu architecture to the gitui release asset name.
# Upstream does NOT put the version in the asset filename, only in the URL.
get_gitui_release() {
    local arch=$1
    case "$arch" in
        "amd64")
            echo "gitui-linux-x86_64"
            ;;
        "arm64")
            echo "gitui-linux-aarch64"
            ;;
        "armhf")
            echo "gitui-linux-armv7"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Shared-library dependencies of the released binary for this architecture.
# amd64 is a static-pie musl build (no NEEDED entries at all); the aarch64 and
# armv7 builds are dynamically linked against glibc >= 2.28 and libgcc_s.
get_gitui_depends() {
    local arch=$1
    case "$arch" in
        "amd64")
            echo ""
            ;;
        "arm64"|"armhf")
            echo "libc6 (>= 2.28), libgcc-s1"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to build for a specific architecture
build_architecture() {
    local build_arch=$1
    local gitui_release
    local gitui_depends

    gitui_release=$(get_gitui_release "$build_arch")
    if [ -z "$gitui_release" ]; then
        echo "❌ Unsupported architecture: $build_arch"
        echo "Supported architectures: amd64, arm64, armhf"
        return 1
    fi
    gitui_depends=$(get_gitui_depends "$build_arch")

    echo "Building for architecture: $build_arch using $gitui_release"

    # Clean up any previous builds for this architecture
    rm -rf "$gitui_release" || true
    rm -f "${gitui_release}.tar.gz" || true

    # Download and extract the gitui binary for this architecture
    if ! wget "https://github.com/gitui-org/gitui/releases/download/v${gitui_VERSION}/${gitui_release}.tar.gz"; then
        echo "❌ Failed to download gitui binary for $build_arch"
        return 1
    fi

    # gitui tarballs are flat (./gitui only), extract into a per-release directory
    mkdir -p "$gitui_release"
    if ! tar -xf "${gitui_release}.tar.gz" -C "$gitui_release"; then
        echo "❌ Failed to extract gitui binary for $build_arch"
        return 1
    fi

    rm -f "${gitui_release}.tar.gz"

    # Build packages for all supported Ubuntu distributions. Upstream ships no
    # riscv64 binary, so there is no noble-and-later-only architecture here.
    declare -a arr=("jammy" "noble" "questing" "resolute")

    for dist in "${arr[@]}"; do
        FULL_VERSION="$gitui_VERSION-${BUILD_VERSION}~${dist}_${build_arch}_ubu"
        echo "  Building $FULL_VERSION"

        if ! docker build . -f Dockerfile.ubu -t "gitui-ubuntu-$dist-$build_arch" \
            --build-arg UBUNTU_DIST="$dist" \
            --build-arg gitui_VERSION="$gitui_VERSION" \
            --build-arg BUILD_VERSION="$BUILD_VERSION" \
            --build-arg FULL_VERSION="$FULL_VERSION" \
            --build-arg ARCH="$build_arch" \
            --build-arg DEPENDS="$gitui_depends" \
            --build-arg GITUI_RELEASE="$gitui_release"; then
            echo "❌ Failed to build Docker image for $dist on $build_arch"
            return 1
        fi

        id="$(docker create "gitui-ubuntu-$dist-$build_arch")"
        if ! docker cp "$id:/gitui_$FULL_VERSION.deb" - > "./gitui_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb package for $dist on $build_arch"
            return 1
        fi

        if ! tar -xf "./gitui_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb contents for $dist on $build_arch"
            return 1
        fi
    done

    # Clean up extracted directory
    rm -rf "$gitui_release" || true

    echo "✅ Successfully built for $build_arch"
    return 0
}

# Main build logic
if [ "$ARCH" = "all" ]; then
    echo "🚀 Building gitui $gitui_VERSION-$BUILD_VERSION for all supported architectures..."
    echo ""

    # All supported architectures
    ARCHITECTURES=("amd64" "arm64" "armhf")

    for build_arch in "${ARCHITECTURES[@]}"; do
        echo "==========================================="
        echo "Building for architecture: $build_arch"
        echo "==========================================="

        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi

        echo ""
    done

    echo "🎉 All architectures built successfully!"
    echo "Generated packages:"
    ls -la gitui_*.deb
else
    # Build for single architecture
    if ! build_architecture "$ARCH"; then
        exit 1
    fi
fi

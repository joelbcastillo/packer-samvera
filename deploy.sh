#! /bin/bash

#
# A little wrapper Bash script to make building easier.
#

# Fail on first error
set -e

# Type artifacts we're versioning ("releases" or "tags")
VERSION_TYPE="releases"

# Override the default action (Cf. `packer -h` for options)
PACKER_ACTION="${PACKER_ACTION:-build}"

if [ "$PACKER_ACTION" == "validate" ]; then
  ON_ERROR=""
else
  ON_ERROR="-on-error=ask"
fi

# Turn on verbose Packer logging by setting: PACKER_LOG=true
PACKER_LOG="${PACKER_LOG:-0}"

# Some conservative/safe build values
DEFAULT_CORE_COUNT=2
DEFAULT_MEMORY=2048

# Optionally, make our builds speedier by giving them full access to the host's resources
if [ "$3" == "fast" ]; then
  if hash getconf 2>/dev/null; then
    if hash free 2>/dev/null; then
      VB_MEMORY=$(free -m | awk '/^Mem:/{print $7}')
      VB_CPU_CORES=$(getconf _NPROCESSORS_ONLN)

      if [ $? -ne 0 ]; then
        VB_CPU_CORES=${DEFAULT_CORE_COUNT}
        VB_MEMORY=${DEFAULT_MEMORY}
      fi
    else
      VB_CPU_CORES=${DEFAULT_CORE_COUNT}
      VB_MEMORY=${DEFAULT_MEMORY}
    fi
  else
    VB_CPU_CORES=${DEFAULT_CORE_COUNT}
    VB_MEMORY=${DEFAULT_MEMORY}
  fi
else
  VB_CPU_CORES=${DEFAULT_CORE_COUNT}
  VB_MEMORY=${DEFAULT_MEMORY}
fi

# Give option to override these in command line (in addition to the config file)
VB_CPU_CORES="${CORES:-$VB_CPU_CORES}"
VB_MEMORY="${MEMORY:-$VB_MEMORY}"

# Provide a usage statement
function printUsage() {
  echo 'Usage: ./build.sh [artifact] [output]'
  echo 'Examples:'
  echo '  ./build.sh base ami'
  echo '  ./build.sh hyrax ami'
  echo '  ./build.sh base box'
  echo '  ./build.sh hyrax box'
#  echo '  ./build.sh base image'
#  echo '  ./build.sh hyrax image'

  exit 1
}

# Confirm that jq is installed on the system
hash jq 2>/dev/null || {
  echo >&2 "jq must be installed to run this script: https://stedolan.github.io/jq/download/"
  exit 1
}

# Check that our build configuration exists
if [ ! -f config.json ]; then
  echo "The config.json file must exist before running the build. See the project README.md"
  exit 1
fi

# Get variables we need to check the latest version
PROJECT_NAME=$(cat config.json | jq -r '.project_name')
PROJECT_OWNER=$(cat config.json | jq -r '.project_owner')
PROJECT_VERSION=$(cat config.json | jq -r '.project_version')

# Label a build artifact pushed to Vagrant Cloud with either SNAPSHOT or a tag/branch name
if [ -z "$PROJECT_NAME" ] || [ -z "$PROJECT_OWNER" ]; then
  echo "The config.json file is missing the project_owner and project_name variables"
  exit 1
else
  BUILD_VERSION=$(curl --silent "https://api.github.com/repos/${PROJECT_OWNER}/${PROJECT_NAME}/${VERSION_TYPE}" | jq -r '.[0].name')

  if [ "$PROJECT_VERSION" != 'HEAD' ] && [ "$PROJECT_VERSION" != 'master' ]; then
    BUILD_VERSION="${BUILD_VERSION:1}-${PROJECT_VERSION}"
  else
    BUILD_VERSION="${BUILD_VERSION:1}-SNAPSHOT"
  fi

  PURPLE='\033[0;35m'
  NC='\033[0m'
  printf "${PURPLE}Building ${PROJECT_OWNER}/${PROJECT_NAME} ${BUILD_VERSION}${NC}\n\n"
fi

if [ -z "$1" ] && [ -z "$2" ]; then
  printUsage
elif [ "$2" == "ami" ] || [ "$2" == "box" ]; then
  if [ "$1" == "base" ] || [ "$1" == "hyrax" ]; then
    PACKER_LOG="$PACKER_LOG" packer "$PACKER_ACTION" -only="$2" -var-file=config.json $ON_ERROR \
      -var="vb_memory=$VB_MEMORY" -var="vb_cpu_cores=$VB_CPU_CORES" -var="build_version=$BUILD_VERSION" samvera-${1}.json
  else
    printUsage
  fi
else
  printUsage
fi

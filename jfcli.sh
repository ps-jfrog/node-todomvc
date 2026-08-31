#!/bin/bash
buildApp=${1:-"JFCLI"}
clear
export JF_NAME="psazuse" JFROG_CLI_LOG_LEVEL="ERROR" TIMESTAMP="$(date '+%Y.%m.%d+%H%M')"
export BUILD_NAME="todomvc-npm" BUILD_ID=""
export RT_REPO_NPM_VIRTUAL="todomvc-npm-virtual"  # "todomvc-npm-sandbox-local"  # npmjs-remote
export NPM_CONFIG_REGISTRY="https://${JF_NAME}.jfrog.io/artifactory/api/npm/${RT_REPO_NPM_VIRTUAL}/"

jf config use ${JF_NAME}

usingJFrogCLI() {
    export BUILD_ID="cli-${TIMESTAMP}"
    printf "\n*** Using JFrog CLI commands \n"
    jf npmc --repo-resolve ${RT_REPO_NPM_VIRTUAL} --repo-deploy ${RT_REPO_NPM_VIRTUAL} 
    jf npm cache clean --force
#    jf ca --format=table --threads=100
#    jf audit --npm --sast=true --sca=true --secrets=true --licenses=true --validate-secrets=true --vuln=true --format=table --extended-table=true --threads=100 --fail=false

    jf npm install --build-name=${BUILD_NAME} --build-number=${BUILD_ID}
    jf npm publish --build-name=${BUILD_NAME} --build-number=${BUILD_ID}

    jf rt bp ${BUILD_NAME} ${BUILD_ID} --collect-git-info=true --collect-env=true --detailed-summary=true
}
usingTraditionalCmd() {
    export BUILD_ID="npm-${TIMESTAMP}"
    export JFROG_RUN_NATIVE=true
    export JFROG_CLI_GHOST_FROG=true
    export JFROG_CLI_BUILD_NAME="${BUILD_NAME}"
    export JFROG_CLI_BUILD_NUMBER="${BUILD_ID}"

    printf "\n*** Using traditional commands \n"
    if [ -z "${PSAZUSE_JF_ACCESS_TOKEN:-}" ]; then
        printf "PSAZUSE_JF_ACCESS_TOKEN is not set; native npm cannot authenticate to Artifactory.\n"
        exit 1
    fi

    # No jf npmc — not needed with JFROG_RUN_NATIVE=true (native mode uses .npmrc, not npm.yaml)
    jf package-alias install --packages=npm

    NPM_REG_HOST="//${JF_NAME}.jfrog.io/artifactory/api/npm/${RT_REPO_NPM_VIRTUAL}/"
    NPM_REGISTRY="https://${JF_NAME}.jfrog.io/artifactory/api/npm/${RT_REPO_NPM_VIRTUAL}/"
    npm config set registry "${NPM_REGISTRY}"
    npm config set "${NPM_REG_HOST}:_authToken" "${PSAZUSE_JF_ACCESS_TOKEN}"

    # Must prepend alias bin to PATH after install so 'npm' resolves to the shim
    export PATH="$HOME/.jfrog/package-alias/bin:$PATH"
    hash -r 2>/dev/null || true

    jf package-alias status

    ORIG_PKG_VER="$(node -p "require('./package.json').version")"
    EPOCH="$(date -u '+%s')"
    STAMPED_PKG_VER="1.0.${EPOCH}"
    printf "\n*** Publishing %s (not %s)\n" "${STAMPED_PKG_VER}" "${ORIG_PKG_VER}"
    npm version "${STAMPED_PKG_VER}" --no-git-tag-version --allow-same-version
    restorePkgVer() { npm version "${ORIG_PKG_VER}" --no-git-tag-version --allow-same-version >/dev/null; }
    trap restorePkgVer EXIT

    # Build info captured via env vars — NO --build-name/--build-number on native npm
    npm install
    npm publish

    jf rt bp "${BUILD_NAME}" "${BUILD_ID}" --collect-env=true --detailed-summary=true
}

arg_len=${#buildApp}
buildApp=$(printf '%s' "${buildApp}" | tr '[:lower:]' '[:upper:]' | xargs)
printf "User Action: ${buildApp}, and arg length: ${arg_len}\n"
case "${buildApp}" in
    JFCLI | jf | CLI)
        usingJFrogCLI
        ;;
    TRADITIONAL | NPM | NODE | NATIVE)
        usingTraditionalCmd
        ;;
    *)
        printf "\n*** Invalid argument: ${buildApp} \n"
        exit 1
        ;;
esac

printf "\n*** Build name: ${BUILD_NAME}  build number: ${BUILD_ID} \n"
jf -v
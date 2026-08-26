#!/bin/bash
buildApp=${1:-"JFCLI"}

export JF_NAME="psazuse" JFROG_CLI_LOG_LEVEL="ERROR" TIMESTAMP="$(date '+%Y.%m.%d+%H%M')"
export BUILD_NAME="todomvc-npm" BUILD_ID=""
export RT_REPO_NPM_VIRTUAL="todomvc-npm-virtual"  # "todomvc-npm-sandbox-local"
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
    export BUILD_ID="npm-${TIMESTAMP}" JFROG_RUN_NATIVE=true
    export JFROG_CLI_BUILD_NAME="${BUILD_NAME}" JFROG_CLI_BUILD_NUMBER="${BUILD_ID}"
    printf "\n*** Using traditional commands \n"
    if [ -z "${PSAZUSE_JF_ACCESS_TOKEN:-}" ]; then
        printf "PSAZUSE_JF_ACCESS_TOKEN is not set; native npm cannot authenticate to Artifactory.\n"
        exit 1
    fi

    # jf npmc is required for 'jf npm publish' to record build-info; native npmrc is for JFROG_RUN_NATIVE.
    jf npmc --repo-resolve ${RT_REPO_NPM_VIRTUAL} --repo-deploy ${RT_REPO_NPM_VIRTUAL}
    NPM_REG_HOST="//${JF_NAME}.jfrog.io/artifactory/api/npm/${RT_REPO_NPM_VIRTUAL}/"
    npm config set registry "${NPM_CONFIG_REGISTRY}"
    npm config set "${NPM_REG_HOST}:_authToken" "${PSAZUSE_JF_ACCESS_TOKEN}"
    npm config set "${NPM_REG_HOST}:always-auth" true

    ORIG_PKG_VER="$(node -p "require('./package.json').version")"
    STAMPED_PKG_VER="${ORIG_PKG_VER}-npm.$(date -u '+%Y%m%d%H%M%S')"
    printf "\n*** Publishing ${STAMPED_PKG_VER} (not ${ORIG_PKG_VER})\n"
    npm version "${STAMPED_PKG_VER}" --no-git-tag-version --allow-same-version
    restorePkgVer() { npm version "${ORIG_PKG_VER}" --no-git-tag-version --allow-same-version >/dev/null; }
    trap restorePkgVer EXIT

    npm install
    # Plain 'npm publish' does not write local build-info. Native npm + --build-name/--build-number does.
    jf npm publish --tag snapshot --build-name="${BUILD_NAME}" --build-number="${BUILD_ID}" --module=todomvc

    printf "\n*** jf rt bp ${BUILD_NAME} ${BUILD_ID} --collect-git-info=true --collect-env=true --detailed-summary=true \n"
    jf rt bp ${BUILD_NAME} ${BUILD_ID} --collect-git-info=true --collect-env=true --detailed-summary=true
}


arg_len=${#buildApp}
buildApp=$(printf "${buildApp}" | tr '[:lower:]' '[:upper:]' | xargs)
printf "User Action: ${buildApp}, and arg length: ${arg_len}\n"
case ${buildApp} in
    JFCLI)
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
pipeline {

    /**************************************************************************
     * Build Agent
     *
     * CD pipeline runs on a dedicated Jenkins Agent labeled 'builder-01'
     * utilizing a rootless Podman socket (DooD pattern).
     **************************************************************************/

    agent {
        label 'builder-01'
    }

    /**************************************************************************
     * Parameterized Pipeline
     *
     * Enables multi-environment deployment portability, enterprise container
     * registry integration, and live verification controls.
     **************************************************************************/

    parameters {
        choice(
            name: 'DEPLOY_ENV',
            choices: ['corporate-matrix', 'aws-staging', 'aws-production', 'production', 'staging', 'lab'],
            description: 'Target Deployment Environment'
        )
        string(
            name: 'INVENTORY_PATH',
            defaultValue: '',
            description: 'Custom inventory path (e.g. /etc/ansible/hosts, ~/.ansible/production.ini, or inventories/corporate-matrix.ini). If empty, defaults to auto-detection in inventories/'
        )
        string(
            name: 'TARGET_HOST',
            defaultValue: 'all',
            description: 'Target Host / Group pattern (e.g. all, aws-ec2-win-01, windows_nodes, app_payment:&env_uat, tomcat_fleet)'
        )
        booleanParam(
            name: 'ENABLE_DEPLOYMENT',
            defaultValue: false,
            description: 'Safety Switch: Check this box to execute real deployment to target servers. If unchecked, pipeline runs in Dry-Run validation mode.'
        )
        string(
            name: 'REGISTRY_HOST',
            defaultValue: 'localhost',
            description: 'Enterprise Container Registry host (e.g. localhost, harbor.corp.internal, nexus.corp.internal:8443)'
        )
        booleanParam(
            name: 'EXECUTE_LIVE_TESTS',
            defaultValue: true,
            description: 'Execute post-deployment live verification suite (verify-postfix-relay & test-tomcatdown-live)'
        )
    }

    /**************************************************************************
     * Environment Variables
     **************************************************************************/

    environment {
        PROJECT_NAME = 'tomcat-monitoring'
        NETWORK_NAME = "${env.CONTAINER_NETWORK ?: 'tm-net'}"
    }

    stages {

        /**********************************************************************
         * Stage 1: Checkout & Platform Validation
         **********************************************************************/

        stage('Checkout & Platform Validation') {
            steps {
                checkout scm

                sh '''#!/usr/bin/env bash
                    set -euo pipefail
                    echo "========================================"
                    echo "STAGE 1: CHECKOUT & PLATFORM VALIDATION"
                    echo "========================================"
                    echo "Branch   : ${GIT_BRANCH:-HEAD}"
                    echo "Commit   : ${GIT_COMMIT:-unknown}"
                    echo "Workspace: ${WORKSPACE}"
                    test -f CONFIG
                    test -f README.md
                    test -f AGENTS.md
                    test -f Jenkinsfile
                    test -f scripts/validate.sh

                    echo "Executing static layout & configuration validation..."
                    bash scripts/validate.sh
                '''
            }
        }

        /**********************************************************************
         * Stage 2: Verify Agent & Runtime Isolation
         **********************************************************************/

        stage('Verify Agent & Runtime Isolation') {
            steps {
                sh '''#!/usr/bin/env bash
                    set -euo pipefail
                    echo "========================================"
                    echo "STAGE 2: VERIFY AGENT & RUNTIME ISOLATION"
                    echo "========================================"
                    echo "Hostname : $(hostname)"
                    echo "User     : $(whoami)"
                    echo "Podman   : $(podman --version)"

                    # Verify rootless mode on build agent
                    is_rootless="$(podman info --format '{{.Host.Security.Rootless}}')"
                    echo "Rootless : ${is_rootless}"
                    test "${is_rootless}" = 'true'

                    # Ensure container network bridge exists
                    if ! podman network exists "${NETWORK_NAME}"; then
                        echo "Creating container network bridge: ${NETWORK_NAME}..."
                        podman network create "${NETWORK_NAME}"
                    fi
                    echo "Network bridge ${NETWORK_NAME} active and isolated."
                '''
            }
        }

        /**********************************************************************
         * Stage 2.5: Materialize Multi-OS Tooling Artifacts
         **********************************************************************/

        stage('Materialize Multi-OS Tooling Artifacts') {
            when {
                expression { return params.ENABLE_DEPLOYMENT == true }
            }
            steps {
                sh '''#!/usr/bin/env bash
                    set -euo pipefail
                    echo "=================================================="
                    echo "STAGE: MATERIALIZE MULTI-OS TOOLING ARTIFACTS"
                    echo "=================================================="
                    export PATH="${HOME}/.local/bin:${HOME}/.local/go/bin:${PATH}"

                    if command -v go >/dev/null 2>&1; then
                        echo "Go compiler available: $(go version)"
                    else
                        echo "Warning: go compiler not found in PATH (${PATH})"
                    fi

                    # 1. Materialize tmctl operator CLI
                    if [[ ! -f "../tmctl/bin/linux_amd64/tmctl" || ! -f "../tmctl/bin/windows_amd64/tmctl.exe" ]]; then
                        echo "Materializing tmctl operator CLI..."
                        if [[ ! -d "../tmctl" ]]; then
                            git clone http://edkas-pc1:3000/gitadm/tmctl.git ../tmctl || git clone /home/eddywiyatno/git/tmctl ../tmctl
                        fi
                        if [[ -f "../tmctl/scripts/build.sh" ]]; then
                            (cd ../tmctl && bash scripts/build.sh)
                        fi
                    fi
                    echo "tmctl status: $(test -f ../tmctl/bin/linux_amd64/tmctl && echo 'Linux OK' || echo 'Missing') | $(test -f ../tmctl/bin/windows_amd64/tmctl.exe && echo 'Windows OK' || echo 'Missing')"

                    # 2. Materialize tm-agent diagnostic event collector
                    if [[ ! -f "../tm-agent/bin/linux_amd64/tm-agent" || ! -f "../tm-agent/bin/windows_amd64/tm-agent.exe" ]]; then
                        echo "Materializing tm-agent diagnostic event collector..."
                        if [[ ! -d "../tm-agent" ]]; then
                            git clone http://edkas-pc1:3000/gitadm/tm-agent.git ../tm-agent || git clone /home/eddywiyatno/git/tm-agent ../tm-agent
                        fi
                        if [[ -f "../tm-agent/scripts/build.sh" ]]; then
                            (cd ../tm-agent && bash scripts/build.sh)
                        fi
                    fi
                    echo "tm-agent status: $(test -f ../tm-agent/bin/linux_amd64/tm-agent && echo 'Linux OK' || echo 'Missing') | $(test -f ../tm-agent/bin/windows_amd64/tm-agent.exe && echo 'Windows OK' || echo 'Missing')"

                    # 3. Materialize Windows container-equivalent binaries if cached on host
                    mkdir -p roles/role_container_stack/files/windows_amd64
                    if [[ -d "/home/eddywiyatno/git/tomcat-monitoring/roles/role_container_stack/files/windows_amd64" ]]; then
                        cp -u /home/eddywiyatno/git/tomcat-monitoring/roles/role_container_stack/files/windows_amd64/*.exe roles/role_container_stack/files/windows_amd64/ 2>/dev/null || true
                    fi
                    echo "Multi-OS tooling artifacts successfully materialized."
                '''
            }
        }

        /**********************************************************************
         * Stage 3: Zero-Touch Platform Deployment
         **********************************************************************/

        stage('Zero-Touch Platform Deployment') {
            when {
                expression { return params.ENABLE_DEPLOYMENT == true }
            }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'aws-ec2-ssh-key', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
                    sh '''#!/usr/bin/env bash
                        set -euo pipefail
                        echo "========================================"
                        echo "STAGE 3: ZERO-TOUCH PLATFORM DEPLOYMENT"
                        echo "========================================"
                        echo "Target Environment: ${DEPLOY_ENV:-corporate-matrix}"
                        echo "Target Host Filter: ${TARGET_HOST:-all}"
                        echo "Custom Inv Path   : ${INVENTORY_PATH:-auto-detect}"
                        echo "Registry Host     : ${REGISTRY_HOST:-localhost}"

                        export ANSIBLE_SSH_KEY_FILE="${SSH_KEY_FILE}"

                        # Adaptive inventory resolution (Custom path -> .ini -> .ini.example)
                        INVENTORY_FILE=""
                        if [[ -n "${INVENTORY_PATH:-}" && -f "${INVENTORY_PATH}" ]]; then
                            INVENTORY_FILE="${INVENTORY_PATH}"
                        elif [[ -f "inventories/${DEPLOY_ENV}.ini" ]]; then
                            INVENTORY_FILE="inventories/${DEPLOY_ENV}.ini"
                        elif [[ -f "inventories/${DEPLOY_ENV}.ini.example" ]]; then
                            INVENTORY_FILE="inventories/${DEPLOY_ENV}.ini.example"
                        elif [[ -f "inventories/${DEPLOY_ENV}" ]]; then
                            INVENTORY_FILE="inventories/${DEPLOY_ENV}"
                        fi

                        LIMIT_ARG=""
                        if [[ -n "${TARGET_HOST:-}" && "${TARGET_HOST}" != "all" ]]; then
                            LIMIT_ARG="--limit ${TARGET_HOST}"
                            echo "Applying target host filter: ${TARGET_HOST}"
                        fi

                        echo "Executing declarative deployment via Ansible Thin Orchestrator & tmctl..."
                        if [[ -n "${INVENTORY_FILE}" && -f "${INVENTORY_FILE}" ]]; then
                            echo "Running Ansible deployment with inventory: ${INVENTORY_FILE} ${LIMIT_ARG}..."
                            bash scripts/run-ansible-playbook.sh deploy-stack.yml -i "${INVENTORY_FILE}" ${LIMIT_ARG}
                        else
                            echo "Running Ansible deployment with default target ${LIMIT_ARG}..."
                            bash scripts/run-ansible-playbook.sh deploy-stack.yml ${LIMIT_ARG}
                        fi

                        echo "All monitoring stack components successfully deployed zero-touch."
                    '''
                }
            }
        }

        /**********************************************************************
         * Stage 4: Live Verification Suite & Incident Simulation
         **********************************************************************/

        stage('Live Verification Suite') {
            when {
                expression { return params.ENABLE_DEPLOYMENT == true && params.EXECUTE_LIVE_TESTS == true }
            }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'aws-ec2-ssh-key', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
                    sh '''#!/usr/bin/env bash
                        set -euo pipefail
                        echo "========================================"
                        echo "STAGE 4: LIVE VERIFICATION SUITE"
                        echo "========================================"

                        if [[ "${DEPLOY_ENV}" =~ ^aws- ]]; then
                            echo "Target Cloud Deployment (${DEPLOY_ENV}): Executing live multi-node / multi-OS verification..."
                            INVENTORY_FILE=""
                            if [[ -n "${INVENTORY_PATH:-}" && -f "${INVENTORY_PATH}" ]]; then
                                INVENTORY_FILE="${INVENTORY_PATH}"
                            elif [[ -f "inventories/${DEPLOY_ENV}.ini" ]]; then
                                INVENTORY_FILE="inventories/${DEPLOY_ENV}.ini"
                            elif [[ -f "inventories/${DEPLOY_ENV}.ini.example" ]]; then
                                INVENTORY_FILE="inventories/${DEPLOY_ENV}.ini.example"
                            elif [[ -f "inventories/${DEPLOY_ENV}" ]]; then
                                INVENTORY_FILE="inventories/${DEPLOY_ENV}"
                            fi

                            export SSH_KEY_FILE="${SSH_KEY_FILE}"
                            bash scripts/verify-cloud-deployment.sh "${INVENTORY_FILE}" "${TARGET_HOST:-all}"
                        else
                            echo "1. Verifying Postfix Enterprise SMTP Relay Bridge (Pattern A)..."
                            bash scripts/verify-postfix-relay.sh

                            echo "2. Executing live TomcatDown incident simulation & 7-section diagnosis..."
                            bash scripts/test-tomcatdown-live.sh
                        fi

                        echo "Live verification suite completed 100% successfully."
                    '''
                }
            }
        }
    }

    /**************************************************************************
     * Post Actions
     **************************************************************************/

    post {
        always {
            cleanWs deleteDirs: true, notFailBuild: true
        }
        success {
            echo "✔ TOMCAT MONITORING STACK CD PIPELINE COMPLETED SUCCESSFULLY!"
        }
        failure {
            echo "✘ TOMCAT MONITORING STACK CD PIPELINE FAILED ON ONE OR MORE STAGES!"
        }
    }
}

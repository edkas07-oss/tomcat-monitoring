pipeline {

    /**************************************************************************
     * Build Agent
     *
     * Seluruh proses CD dijalankan pada Jenkins Dedicated Agent dengan label
     * "builder" menggunakan Rootless Podman socket (DooD pattern).
     **************************************************************************/

    agent {
        label 'builder-01'
    }

    /**************************************************************************
     * Parameterized Pipeline
     *
     * Mendukung portabilitas deployment ke berbagai target environment,
     * konfigurasi Enterprise Container Registry, dan kontrol eksekusi live test.
     **************************************************************************/

    parameters {
        choice(
            name: 'DEPLOY_ENV',
            choices: ['aws-staging', 'aws-production', 'production', 'staging', 'lab'],
            description: 'Target Deployment Environment'
        )
        string(
            name: 'TARGET_HOST',
            defaultValue: 'all',
            description: 'Target Host / Group pattern (e.g. all, aws-ec2-win-01, windows_nodes, linux_nodes, tomcat_fleet)'
        )
        string(
            name: 'REGISTRY_HOST',
            defaultValue: 'localhost',
            description: 'Enterprise Container Registry host (e.g. localhost, harbor.internal, nexus.internal:8443)'
        )
        booleanParam(
            name: 'EXECUTE_LIVE_TESTS',
            defaultValue: true,
            description: 'Mengeksekusi rangkaian live verification suite pasca-deploy (verify-postfix-relay & test-tomcatdown-live)'
        )
    }

    /**************************************************************************
     * Environment Variables
     **************************************************************************/

    environment {
        PROJECT_NAME = 'tomcat-monitoring'
        NETWORK_NAME = 'devops-lab'
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

                    echo "Menjalankan validasi statis seluruh konfigurasi stack..."
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

                    # Verifikasi mode rootless Podman pada build agent
                    is_rootless="$(podman info --format '{{.Host.Security.Rootless}}')"
                    echo "Rootless : ${is_rootless}"
                    test "${is_rootless}" = 'true'

                    # Memastikan isolasi network bridge devops-lab tersedia
                    if ! podman network exists "${NETWORK_NAME}"; then
                        echo "Membuat network bridge Podman: ${NETWORK_NAME}..."
                        podman network create "${NETWORK_NAME}"
                    fi
                    echo "Network bridge ${NETWORK_NAME} aktif dan terisolasi."
                '''
            }
        }

        /**********************************************************************
         * Stage 3: Zero-Touch Platform Deployment
         **********************************************************************/

        stage('Zero-Touch Platform Deployment') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'aws-ec2-ssh-key', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
                    sh '''#!/usr/bin/env bash
                        set -euo pipefail
                        echo "========================================"
                        echo "STAGE 3: ZERO-TOUCH PLATFORM DEPLOYMENT"
                        echo "========================================"
                        echo "Target Environment: ${DEPLOY_ENV:-aws-staging}"
                        echo "Target Host Filter: ${TARGET_HOST:-all}"
                        echo "Registry Host     : ${REGISTRY_HOST:-localhost}"

                        export ANSIBLE_SSH_KEY_FILE="${SSH_KEY_FILE}"
                        INVENTORY_FILE="inventories/${DEPLOY_ENV}.ini"

                        LIMIT_ARG=""
                        if [[ -n "${TARGET_HOST:-}" && "${TARGET_HOST}" != "all" ]]; then
                            LIMIT_ARG="--limit ${TARGET_HOST}"
                            echo "Menerapkan pembatasan host target (limit): ${TARGET_HOST}"
                        fi

                        echo "Mengeksekusi deklaratif deployment via Ansible Thin Orchestrator & tmctl..."
                        if [[ -f "${INVENTORY_FILE}" ]]; then
                            echo "Menjalankan deployment Ansible ke target inventori: ${INVENTORY_FILE} ${LIMIT_ARG}..."
                            bash scripts/run-ansible-playbook.sh deploy-stack.yml -i "${INVENTORY_FILE}" ${LIMIT_ARG}
                        else
                            echo "Menjalankan deployment Ansible ke target default ${LIMIT_ARG}..."
                            bash scripts/run-ansible-playbook.sh deploy-stack.yml ${LIMIT_ARG}
                        fi

                        echo "Seluruh komponen stack monitoring berhasil dideploy secara zero-touch."
                    '''
                }
            }
        }


        /**********************************************************************
         * Stage 4: Live Verification Suite & Incident Simulation
         **********************************************************************/

        stage('Live Verification Suite') {
            when {
                expression { return params.EXECUTE_LIVE_TESTS == true }
            }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'aws-ec2-ssh-key', keyFileVariable: 'SSH_KEY_FILE', usernameVariable: 'SSH_USER')]) {
                    sh '''#!/usr/bin/env bash
                        set -euo pipefail
                        echo "========================================"
                        echo "STAGE 4: LIVE VERIFICATION SUITE"
                        echo "========================================"

                        if [[ "${DEPLOY_ENV}" =~ ^aws- ]]; then
                            echo "Target Cloud Deployment (${DEPLOY_ENV}): Menjalankan verifikasi live via SSH ke EC2..."
                            INVENTORY_FILE="inventories/${DEPLOY_ENV}.ini"
                            TARGET_HOST="$(grep -E 'ansible_host=' "${INVENTORY_FILE}" | head -n 1 | sed -E 's/.*ansible_host=([^ ]+).*/\\1/')"
                            TARGET_USER="${SSH_USER:-ec2-user}"
                            
                            echo "Target Host: ${TARGET_USER}@${TARGET_HOST}"
                            ssh -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${TARGET_USER}@${TARGET_HOST}" "
                                set -euo pipefail
                                echo '1. Memeriksa status kesehatan Diagnostic Service...'
                                curl -sk https://127.0.0.1:8443/health >/dev/null && echo 'Diagnostic Service: OK'
                                echo '2. Memeriksa kesiapan Prometheus TSDB...'
                                curl -s http://127.0.0.1:9090/-/ready >/dev/null && echo 'Prometheus: READY'
                                echo '3. Memeriksa kesiapan Alertmanager...'
                                curl -s http://127.0.0.1:9093/-/ready >/dev/null && echo 'Alertmanager: OK'
                                echo '4. Memeriksa ketersediaan metrik Tomcat JMX Exporter...'
                                curl -sk https://127.0.0.1:9404/metrics >/dev/null && echo 'Tomcat JMX Exporter: OK'
                                echo '5. Memeriksa Mailpit inbox...'
                                curl -s http://127.0.0.1:8025/api/v1/messages >/dev/null && echo 'Mailpit API: OK'
                                echo '6. Memeriksa status service tm-agent daemon...'
                                systemctl --user is-active tm-agent >/dev/null && echo 'tm-agent daemon: ACTIVE'
                            "
                        else
                            echo "1. Memverifikasi jembatan Postfix Enterprise SMTP Relay (Pola A)..."
                            bash scripts/verify-postfix-relay.sh

                            echo "2. Mengeksekusi simulasi insiden live TomcatDown dan pelaporan 7-seksi..."
                            bash scripts/test-tomcatdown-live.sh
                        fi

                        echo "Rangkaian pengujian live verification suite berhasil 100%."
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
            echo "✔ TOMCAT MONITORING STACK CD PIPELINE BERHASIL DISELESAIKAN DENGAN SUKSES!"
        }
        failure {
            echo "✘ TOMCAT MONITORING STACK CD PIPELINE GAGAL PADA SALAH SATU TAHAPAN!"
        }
    }
}

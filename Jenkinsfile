pipeline {

    /**************************************************************************
     * Build Agent
     *
     * Seluruh proses CD dijalankan pada Jenkins Dedicated Agent dengan label
     * "builder" menggunakan Rootless Podman socket (DooD pattern).
     **************************************************************************/

    agent {
        label 'builder'
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
            choices: ['production', 'staging', 'lab'],
            description: 'Target Deployment Environment'
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

                sh '''
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
                sh '''
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
                sh '''
                    set -euo pipefail
                    echo "========================================"
                    echo "STAGE 3: ZERO-TOUCH PLATFORM DEPLOYMENT"
                    echo "========================================"
                    echo "Target Environment: ${params.DEPLOY_ENV}"
                    echo "Registry Host     : ${params.REGISTRY_HOST}"

                    echo "1. Menginisialisasi volume konfigurasi Prometheus & Alertmanager..."
                    bash scripts/initialize-prometheus-volumes.sh
                    bash scripts/initialize-alertmanager-volumes.sh

                    echo "2. Meluncurkan layanan workload Tomcat JMX Exporter..."
                    bash scripts/deploy-tomcat.sh

                    echo "3. Meluncurkan layanan inti monitoring (Prometheus)..."
                    bash scripts/deploy-prometheus.sh

                    echo "4. Meluncurkan layanan routing alert (Alertmanager)..."
                    bash scripts/deploy-alertmanager.sh

                    echo "5. Meluncurkan backend analitik (Diagnostic Service)..."
                    bash scripts/deploy-diagnostic-service.sh

                    echo "6. Meluncurkan daemon pemantau event host (Event Collector)..."
                    bash scripts/deploy-event-collector.sh

                    echo "Seluruh komponen stack monitoring berhasil dideploy secara zero-touch."
                '''
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
                sh '''
                    set -euo pipefail
                    echo "========================================"
                    echo "STAGE 4: LIVE VERIFICATION SUITE"
                    echo "========================================"

                    echo "1. Memverifikasi jembatan Postfix Enterprise SMTP Relay (Pola A)..."
                    bash scripts/verify-postfix-relay.sh

                    echo "2. Mengeksekusi simulasi insiden live TomcatDown dan pelaporan 7-seksi..."
                    bash scripts/test-tomcatdown-live.sh

                    echo "Rangkaian pengujian live verification suite berhasil 100%."
                '''
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

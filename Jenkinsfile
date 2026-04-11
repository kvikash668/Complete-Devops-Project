pipeline {
    agent any

    environment {
        // SonarQube
        SONAR_HOME = tool('Sonar')

        // GitHub
        GITHUB_REPO_URL = 'https://github.com/kvikash668/Complete-Devops-Project.git'
        GITHUB_BRANCH = 'main'
        GITHUB_CREDENTIALS_ID = 'github-pat'
        GITHUB_USER_EMAIL = 'kvikash668@gmail.com'
        GITHUB_USER_NAME = 'Kvikash668'

        // Kubernetes Repo
        K8S_REPO_URL = 'https://github.com/kvikash668/Complete-Devops-Project.git'
        K8S_REPO_BRANCH = 'main'
        K8S_REPO_DIR = 'Kubernetes'
        K8S_MANIFESTS_PATH = 'k8s-manifests'

        FRONTEND_CANARY_FILE = 'frontend-canary.yaml'
        BACKEND_CANARY_FILE = 'node-canary.yaml'

        // Docker
        DOCKER_REGISTRY_USER = 'kvikash668'
        DOCKER_CREDENTIALS_ID = 'jenkins-token'
        FRONTEND_IMAGE_NAME = 'frontend'
        BACKEND_IMAGE_NAME = 'backend'

        // Security
        OWASP_INSTALL_NAME = 'dependency-check'
        OWASP_REPORT_FILE = 'dependency-check-report.xml'
        TRIVY_REPORT_FILE = 'trivy-report.html'

        // Email
        NOTIFICATION_EMAIL = 'workingvikash@gmail.com'
        EMAIL_FROM = 'jenkins@ci.com'

        // Build
        FRONTEND_BUILD_DIR = 'client'
        BACKEND_BUILD_DIR = 'server'

        QUALITY_GATE_TIMEOUT = '5'
    }

    stages {

        stage('Clone Code') {
            steps {
                git url: "${GITHUB_REPO_URL}", branch: "${GITHUB_BRANCH}"
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    set -e
                    cd client && npm install
                    cd ../server && npm install
                '''
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv("Sonar") {
                    sh '''
                        ${SONAR_HOME}/bin/sonar-scanner \
                        -Dsonar.projectName=socialEcho-1 \
                        -Dsonar.projectKey=socialEcho-1 \
                        -Dsonar.sources=.
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: QUALITY_GATE_TIMEOUT.toInteger(), unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('OWASP Scan') {
            steps {
                dependencyCheck additionalArguments: "--scan ./", odcInstallation: "${OWASP_INSTALL_NAME}"
                dependencyCheckPublisher pattern: "${OWASP_REPORT_FILE}"
            }
        }

        stage('Trivy Scan') {
            steps {
                sh '''
                    if ! command -v trivy &> /dev/null
                    then
                        echo "❌ Trivy not installed"
                        exit 1
                    fi
                    trivy fs -o ${TRIVY_REPORT_FILE} .
                '''
            }
        }

        stage('Build & Push Docker Images') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKER_CREDENTIALS_ID}",
                    usernameVariable: 'USER',
                    passwordVariable: 'PASS'
                )]) {
                    sh '''
                        set -e

                        echo "$PASS" | docker login -u "$USER" --password-stdin

                        # Frontend
                        cd ${FRONTEND_BUILD_DIR}
                        docker build -t ${DOCKER_REGISTRY_USER}/${FRONTEND_IMAGE_NAME}:${BUILD_NUMBER} .
                        docker tag ${DOCKER_REGISTRY_USER}/${FRONTEND_IMAGE_NAME}:${BUILD_NUMBER} ${DOCKER_REGISTRY_USER}/${FRONTEND_IMAGE_NAME}:latest
                        docker push ${DOCKER_REGISTRY_USER}/${FRONTEND_IMAGE_NAME}:${BUILD_NUMBER}
                        docker push ${DOCKER_REGISTRY_USER}/${FRONTEND_IMAGE_NAME}:latest
                        cd ..

                        # Backend
                        cd ${BACKEND_BUILD_DIR}
                        docker build -t ${DOCKER_REGISTRY_USER}/${BACKEND_IMAGE_NAME}:${BUILD_NUMBER} .
                        docker tag ${DOCKER_REGISTRY_USER}/${BACKEND_IMAGE_NAME}:${BUILD_NUMBER} ${DOCKER_REGISTRY_USER}/${BACKEND_IMAGE_NAME}:latest
                        docker push ${DOCKER_REGISTRY_USER}/${BACKEND_IMAGE_NAME}:${BUILD_NUMBER}
                        docker push ${DOCKER_REGISTRY_USER}/${BACKEND_IMAGE_NAME}:latest
                        cd ..

                        docker logout
                    '''
                }
            }
        }

        stage('Update Kubernetes Manifests') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${GITHUB_CREDENTIALS_ID}",
                    usernameVariable: 'GIT_USER',
                    passwordVariable: 'GIT_PASS'
                )]) {
                    sh '''
                        set -e

                        rm -rf ${K8S_REPO_DIR}

                        git clone ${K8S_REPO_URL} ${K8S_REPO_DIR}
                        cd ${K8S_REPO_DIR}

                        git config user.email "${GITHUB_USER_EMAIL}"
                        git config user.name "${GITHUB_USER_NAME}"

                        git remote set-url origin https://$GIT_USER:$GIT_PASS@github.com/kvikash668/Complete-Devops-Project.git

                        cd ${K8S_MANIFESTS_PATH}

                        sed -i "s|image: .*frontend.*|image: ${DOCKER_REGISTRY_USER}/${FRONTEND_IMAGE_NAME}:${BUILD_NUMBER}|" ${FRONTEND_CANARY_FILE}
                        sed -i "s|image: .*backend.*|image: ${DOCKER_REGISTRY_USER}/${BACKEND_IMAGE_NAME}:${BUILD_NUMBER}|" ${BACKEND_CANARY_FILE}

                        git add .
                        git commit -m "Update images - Build ${BUILD_NUMBER}" || echo "No changes"
                        git push origin ${K8S_REPO_BRANCH}
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "✅ SUCCESS"
            mail to: "${NOTIFICATION_EMAIL}",
                 subject: "✅ SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                 body: "Build completed successfully."
        }
        failure {
            echo "❌ FAILED"
            mail to: "${NOTIFICATION_EMAIL}",
                 subject: "❌ FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                 body: "Build failed. Check Jenkins logs."
        }
        always {
            cleanWs()
        }
    }
}
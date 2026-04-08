pipeline {
    agent any

    // tools {
    //     sonar 'Sonar'  // Correct tool type
    // }

    environment {
        // GitHub
        SONAR_HOME = tool name: 'Sonar', type: 'hudson.plugins.sonar.SonarRunnerInstallation'

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

        // Files
        FRONTEND_CANARY_FILE = 'frontend-canary.yaml'
        BACKEND_CANARY_FILE = 'node-canary.yaml'
        FRONTEND_STABLE_FILE = 'frontend-server.yaml'
        BACKEND_STABLE_FILE = 'node-server.yaml'

        // Docker
        DOCKER_REGISTRY_USER = 'kvikash668'
        DOCKER_CREDENTIALS_ID = 'jenkins-token'
        FRONTEND_IMAGE_NAME = 'frontend'
        BACKEND_IMAGE_NAME = 'backend'

        // Sonar
        // SONAR_PROJECT_NAME = 'socialEcho-1'
        // SONAR_PROJECT_KEY = 'socialEcho-1'
        // SONAR_ENV = 'Sonar'

        // Security
        OWASP_INSTALL_NAME = 'dependency-check'
        OWASP_REPORT_FILE = 'dependency-check-report.xml'
        TRIVY_REPORT_FILE = 'trivy-report.html'

        // Email
        NOTIFICATION_EMAIL = 'workingvikash@gmail.com'
        EMAIL_FROM = 'jenkins@ci.com'

        // Build dirs
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
               cd client && npm install
               cd ../server && npm install
            '''
    }
}
        stage('SonarQube Quality Analysis') {
            steps {
                withSonarQubeEnv("Sonar") {
                    sh '''
                        ${SONAR_HOME}/bin/sonar-scanner \
                        -Dsonar.projectName=socialEcho-1 \
                        -Dsonar.projectKey=socialEcho-1
                    '''
                }
            }
        }

        // stage('Quality Gate') {
        //     steps {
        //         timeout(time: QUALITY_GATE_TIMEOUT.toInteger(), unit: 'MINUTES') {
        //             waitForQualityGate abortPipeline: true
        //         }
        //     }
        // }
        
        stage('OWASP Scan') {
            steps {
                dependencyCheck additionalArguments: "--scan ./", odcInstallation: "${OWASP_INSTALL_NAME}"
                dependencyCheckPublisher pattern: "${OWASP_REPORT_FILE}"
            }
        }

        stage('Trivy Scan') {
            steps {
                sh "trivy fs -o ${TRIVY_REPORT_FILE} ."
            }
        }

        stage('Build & Push Docker') {
            steps {
                withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS_ID}", usernameVariable: 'USER', passwordVariable: 'PASS')]) {
                    sh """
                        echo "$PASS" | docker login -u "$USER" --password-stdin

                        cd ${FRONTEND_BUILD_DIR}
                        docker build -t ${DOCKER_REGISTRY_USER}/${FRONTEND_IMAGE_NAME}:${BUILD_NUMBER} .
                        docker push ${DOCKER_REGISTRY_USER}/${FRONTEND_IMAGE_NAME}:${BUILD_NUMBER}
                        cd ..

                        cd ${BACKEND_BUILD_DIR}
                        docker build -t ${DOCKER_REGISTRY_USER}/${BACKEND_IMAGE_NAME}:${BUILD_NUMBER} .
                        docker push ${DOCKER_REGISTRY_USER}/${BACKEND_IMAGE_NAME}:${BUILD_NUMBER}
                        cd ..

                        docker logout
                    """
                }
            }
        }

        stage('Update Kubernetes Manifests') {
            steps {
                withCredentials([usernamePassword(credentialsId: "${GITHUB_CREDENTIALS_ID}", usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                    sh """
                        rm -rf ${K8S_REPO_DIR}
                        git clone https://$GIT_USER:$GIT_PASS@github.com/kvikash668/Complete-Devops-Project.git ${K8S_REPO_DIR}

                        cd ${K8S_REPO_DIR}/${K8S_MANIFESTS_PATH}

                        sed -i "s|image: .*|image: ${DOCKER_REGISTRY_USER}/${FRONTEND_IMAGE_NAME}:${BUILD_NUMBER}|" ${FRONTEND_CANARY_FILE}
                        sed -i "s|image: .*|image: ${DOCKER_REGISTRY_USER}/${BACKEND_IMAGE_NAME}:${BUILD_NUMBER}|" ${BACKEND_CANARY_FILE}

                        git config user.email "${GITHUB_USER_EMAIL}"
                        git config user.name "${GITHUB_USER_NAME}"

                        git add .
                        git commit -m "Update images - Build ${BUILD_NUMBER}" || echo "No changes"

                        git push https://$GIT_USER:$GIT_PASS@github.com/kvikash668/Complete-Devops-Project.git ${K8S_REPO_BRANCH}
                    """
                }
            }
        }
    }

    post {
        success {
            echo "✅ SUCCESS"
        }
        failure {
            echo "❌ FAILED"
        }
        always {
            cleanWs()
        }
    }
}
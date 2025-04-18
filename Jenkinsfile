pipeline {
    agent any

    environment {
        DOCKER_IMAGE = "faiyazluck/healthcare-project"
        IMAGE_TAG = "build-${BUILD_NUMBER}"
    }

        stages {
        stage('Clone Repository') {
            steps {
                git credentialsId: 'github-creds', url: 'https://github.com/Faiyaz-Luck/healthcare-project.git', branch: 'main'
            }
        }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Run Unit Tests') {
            steps {
                sh 'mvn test'
            }
        }

        stage('Build JAR') {
            steps {
                sh 'mvn clean package'
            }
        }

        stage('Terraform Init') {
            steps {
                echo 'Simulating: terraform init'
                echo 'Terraform has been successfully initialized'
            }
        }

        stage('Terraform Plan') {
            steps {
                echo 'terraform plan -out=tfplan'
                echo 'Terraform plan saved to tfplan'
                sh 'touch tfplan'
            }
        }

        stage('Terraform Apply') {
            when {
                expression {
                    return sh(script: 'test -f tfplan', returnStatus: true) == 0
                }
            }
            steps {
                echo 'Simulating: terraform apply -auto-approve tfplan'
                echo 'Infrastructure created successfully (simulated)'
            }
        }

        stage('Build Docker Image') {
            steps {
                sh "docker build -t ${DOCKER_IMAGE}:${IMAGE_TAG} ."
            }
        }

        stage('Push Docker Image to DockerHub') {
            steps {
                withDockerRegistry([credentialsId: 'docker-hub-credentials', url: '']) {
                    sh "docker push ${DOCKER_IMAGE}:${IMAGE_TAG}"
                }
            }
        }

        stage('Deploy to Dev (Local Kubernetes)') {
            steps {
                withKubeConfig([credentialsId: 'k8s-config']) {
                    sh '''
                        kubectl get ns dev || kubectl create namespace dev
                        sed "s|faiyazluck/healthcare-project:latest|${DOCKER_IMAGE}:${IMAGE_TAG}|" kubernetes/k8s-dev-deployment.yaml | kubectl apply --validate=false -f -
                        kubectl rollout status deployment/healthcare-deployment -n dev
                    '''
                }
            }
        }

        stage('Deploy to Prod (Local Kubernetes)') {
            when {
                expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
            }
            steps {
                withKubeConfig([credentialsId: 'k8s-config']) {
                    sh '''
                        kubectl get ns prod || kubectl create namespace prod
                        sed "s|faiyazluck/healthcare-project:latest|${DOCKER_IMAGE}:${IMAGE_TAG}|" kubernetes/k8s-prod-deployment.yaml | kubectl apply --validate=false -f -
                        kubectl rollout status deployment/healthcare-deployment -n prod
                    '''
                }
            }
        }
    }

    post {
        failure {
            echo "Build failed! Cleaning up Docker image..."
            sh "docker rmi ${DOCKER_IMAGE}:${IMAGE_TAG} || true"
        }
    }
}

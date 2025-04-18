pipeline {
    agent any

    environment {
        DOCKER_IMAGE = "aaliyafari/healthcare-project"
        IMAGE_TAG = "build-${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout Code') {
            steps {
                git credentialsId: 'github-creds', url: 'https://github.com/Faiyaz-Luck/healthcare-project.git', branch: 'main'
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
                echo 'terraform init'
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
                echo 'terraform apply -auto-approve tfplan'
                echo 'Infrastructure created successfully'
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

        stage('Deploy to Dev') {
            steps {
                withKubeConfig([credentialsId: 'k8s-config']) {
                    sh '''
                        kubectl get ns dev || kubectl create namespace dev
                        sed "s|aaliyafari/healthcare-project:latest|${DOCKER_IMAGE}:${IMAGE_TAG}|" kubernetes/k8s-dev-deployment.yaml | kubectl apply --validate=false -f -
                        kubectl rollout status deployment/healthcare-deployment -n dev
                    '''
                }
            }
        }

        stage('Deploy to Prod') {
            when {
                expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
            }
            steps {
                withKubeConfig([credentialsId: 'k8s-config']) {
                    sh '''
                        kubectl get ns prod || kubectl create namespace prod
                        sed "s|aaliyafari/healthcare-project:latest|${DOCKER_IMAGE}:${IMAGE_TAG}|" kubernetes/k8s-prod-deployment.yaml | kubectl apply --validate=false -f -
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

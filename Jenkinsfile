pipeline {
    agent any

    environment {
        DOCKER_IMAGE = "faiyazluck/healthcare-project"
        IMAGE_TAG = "build-${BUILD_NUMBER}"
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

stage('Terraform Plan') {
    steps {
        withCredentials([[
            $class: 'AmazonWebServicesCredentialsBinding',
            credentialsId: 'AWS_CREDENTIALS'
        ]]) {
            sh '''
                terraform init
                terraform plan -out=tfplan || exit 1
            '''
        }
    }
}

stage('Terraform Apply') {
    when {
        expression {
            return sh(script: 'test -f tfplan', returnStatus: true) == 0
        }
    }
    steps {
        sh 'terraform apply -auto-approve tfplan'
    }
}



        stage('Build Docker Image') {
            steps {
                sh "docker build -t ${DOCKER_IMAGE}:${IMAGE_TAG} ."
            }
        }

        stage('Push Docker Image') {
            steps {
                withDockerRegistry([credentialsId: 'docker-hub-credentials', url: '']) {
                    sh "docker push ${DOCKER_IMAGE}:${IMAGE_TAG}"
                }
            }
        }

        stage('Deploy to Dev') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'AWS_CREDENTIALS'
                ]]) {
                    withEnv([
                        "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID",
                        "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
                    ]) {
                        withKubeConfig([credentialsId: 'k8s-config']) {
                            sh '''
                                kubectl get ns dev || kubectl create namespace dev
                                sed "s|faiyazluck/healthcare-project:latest|${DOCKER_IMAGE}:${IMAGE_TAG}|" kubernetes/k8s-dev-deployment.yaml | kubectl apply --validate=false -f -
                                kubectl rollout status deployment/healthcare-deployment -n dev
                            '''
                        }
                    }
                }
            }
        }

        stage('Deploy to Prod') {
            when {
                expression { currentBuild.result == null || currentBuild.result == 'SUCCESS' }
            }
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'AWS_CREDENTIALS'
                ]]) {
                    withEnv([
                        "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID",
                        "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
                    ]) {
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
        }
    }

    post {
        failure {
            echo "Build failed! Cleaning up Docker image..."
            sh "docker rmi ${DOCKER_IMAGE}:${IMAGE_TAG} || true"
        }
    }
}

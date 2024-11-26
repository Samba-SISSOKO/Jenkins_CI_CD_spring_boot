pipeline {
    agent any

    environment {
        DOCKERHUB_AUTH = credentials('DockerHubCredentials')
        MYSQL_AUTH = credentials('MYSQL_AUTH')
        HOSTNAME_DEPLOY_PROD = "20.115.44.142"
        HOSTNAME_DEPLOY_STAGING = "20.115.42.32"
        IMAGE_NAME = 'paymybuddy'
        IMAGE_TAG = 'latest'
    }

    stages {
        stage('Build and Test') {
            steps {
                sh 'mvn clean test'
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('SonarCloud Analysis') {
            steps {
                withSonarQubeEnv('SonarCloudServer') {
                    sh 'mvn sonar:sonar -s .m2/settings.xml'
                }
            }
        }

        stage('Package') {
            steps {
                sh 'mvn clean package -DskipTests'
            }
        }

        stage('Build and Push Docker Image') {
            steps {
                sh """
                    docker build -t ${DOCKERHUB_AUTH_USR}/${IMAGE_NAME}:${IMAGE_TAG} .
                    echo ${DOCKERHUB_AUTH_PSW} | docker login -u ${DOCKERHUB_AUTH_USR} --password-stdin
                    docker push ${DOCKERHUB_AUTH_USR}/${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
        }

        stage('Deploy Staging') {
            when {
                expression { env.GIT_BRANCH == 'origin/main' }
            }
            steps {
                sshagent(credentials: ['SSH_AUTH_SERVER']) {
                    sh '''
                        ssh-keyscan -t rsa,dsa ${HOSTNAME_DEPLOY_STAGING} >> ~/.ssh/known_hosts
                        scp -r deploy centos@${HOSTNAME_DEPLOY_STAGING}:/home/centos/
                        ssh centos@${HOSTNAME_DEPLOY_STAGING} "
                            cd deploy &&
                            echo ${DOCKERHUB_AUTH_PSW} | docker login -u ${DOCKERHUB_AUTH_USR} --password-stdin &&
                            docker compose down &&
                            docker pull ${DOCKERHUB_AUTH_USR}/${IMAGE_NAME}:${IMAGE_TAG} &&
                            docker compose up -d
                        "
                    '''
                }
            }
        }

        stage('Test Staging') {
            steps {
                sh 'curl ${HOSTNAME_DEPLOY_STAGING}:8080'
            }
        }

        stage('Deploy Production') {
            when {
                expression { env.GIT_BRANCH == 'origin/main' }
            }
            steps {
                sshagent(credentials: ['SSH_AUTH_SERVER']) {
                    sh '''
                        ssh-keyscan -t rsa,dsa ${HOSTNAME_DEPLOY_PROD} >> ~/.ssh/known_hosts
                        scp -r deploy centos@${HOSTNAME_DEPLOY_PROD}:/home/centos/
                        ssh centos@${HOSTNAME_DEPLOY_PROD} "
                            cd deploy &&
                            echo ${DOCKERHUB_AUTH_PSW} | docker login -u ${DOCKERHUB_AUTH_USR} --password-stdin &&
                            docker compose down &&
                            docker pull ${DOCKERHUB_AUTH_USR}/${IMAGE_NAME}:${IMAGE_TAG} &&
                            docker compose up -d
                        "
                    '''
                }
            }
        }

        stage('Test Production') {
            steps {
                sh 'curl ${HOSTNAME_DEPLOY_PROD}:8080'
            }
        }
    }
}


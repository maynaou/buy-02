def BACKEND_SERVICES = [
    'api-gateway',
    'discovery-service',
    'media-service',
    'product-service',
    'security-service',
    'user-service',
    'order-service'
]


pipeline {

    agent any

    environment {
        IMAGE_TAG = "build-${BUILD_NUMBER}"
        NEXUS_DOCKER_PROXY = "nexus:8084"
    }

    options {

        buildDiscarder(
            logRotator(
                numToKeepStr: '20'
            )
        )

        disableConcurrentBuilds()

        timestamps()

        timeout(
            time: 30,
            unit: 'MINUTES'
        )

        preserveStashes(buildCount: 10)

    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Prepare Nexus Maven Settings') {
            steps {
                sh 'chmod 600 "$WORKSPACE/settings.xml"'
            }
        }

        stage('Prepare Secrets') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'cloudinary-url',
                        variable: 'CLOUDINARY_URL'
                    ),
                    file(
                        credentialsId: 'jwt-private-key',
                        variable: 'JWT_PRIVATE_KEY'
                    ),
                    file(
                        credentialsId: 'jwt-public-key',
                        variable: 'JWT_PUBLIC_KEY'
                    ),
                    file(
                        credentialsId: 'frontend-ssl-cert',
                        variable: 'FRONTEND_SSL_CERT'
                    ),
                    file(
                        credentialsId: 'frontend-ssl-key',
                        variable: 'FRONTEND_SSL_KEY'
                    )
                ]) {
                    sh './scripts/prepare-secrets.sh'
                }
            }
        }

        stage('Backend Unit & Integration Tests') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'nexus-credentials',
                        usernameVariable: 'NEXUS_CI_USER',
                        passwordVariable: 'NEXUS_CI_PASSWORD'
                    )
                ]) {
                    withEnv(['NEXUS_URL=http://nexus:8081']) {
                        script {
                            BACKEND_SERVICES.each { service ->
                                dir("backend/${service}") {
                                    sh './mvnw -s "$WORKSPACE/settings.xml" clean package'
                                }
                            }
                        }
                    }
                }
            }
        }

stage('Backend SonarQube Analysis') {
    steps {
        withCredentials([
            usernamePassword(
                credentialsId: 'nexus-credentials',
                usernameVariable: 'NEXUS_CI_USER',
                passwordVariable: 'NEXUS_CI_PASSWORD'
            )
        ]) {
            withEnv(['NEXUS_URL=http://nexus:8081']) {
                script {
                    BACKEND_SERVICES.each { service ->
                        dir("backend/${service}") {
                            echo "🔎 SonarQube: ${service}"

                            withSonarQubeEnv('SonarQube') {
                                sh """
                                    ./mvnw -s "$WORKSPACE/settings.xml" \
                                    org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
                                    -Dsonar.projectKey=buy-02-${service} \
                                    -Dsonar.projectName=buy-02-${service} \
                                    -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
                                """
                            }

                            timeout(time: 5, unit: 'MINUTES') {
                                waitForQualityGate abortPipeline: true
                            }
                        }
                    }
                }
            }
        }
    }
}

        stage('Frontend Unit & Integration Tests') {
            steps {
                dir('frontend') {
                    sh 'npm ci'
                    sh "npm test -- --watch=false --include='src/**/*.spec.ts'"
                }
            }
        }


        stage('Frontend SonarQube Analysis') {
            steps {
                dir('frontend') {
                    withSonarQubeEnv('SonarQube') {
                        sh '''
                            npx sonar-scanner \
                            -Dsonar.projectKey=buy-02-frontend \
                            -Dsonar.projectName=buy-02-frontend \
                            -Dsonar.sources=src \
                            -Dsonar.tests=src \
                            -Dsonar.test.inclusions=**/*.spec.ts \
                            -Dsonar.exclusions=**/*.spec.ts,**/node_modules/**,**/dist/** \
                            -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info
                        '''
                    }
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                    }
                }
            }
        }

        stage('Publish Backend Artifacts to Nexus') {
            when {
                anyOf {
                    branch 'main'
                    buildingTag()
                }
            }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'nexus-credentials',
                        usernameVariable: 'NEXUS_CI_USER',
                        passwordVariable: 'NEXUS_CI_PASSWORD'
                    )
                ]) {
                    withEnv(['NEXUS_URL=http://nexus:8081']) {
                        script {
                            def releaseTag = env.TAG_NAME
                            def isRelease = releaseTag != null && !releaseTag.isEmpty()
                            def releaseVersion
                            if (isRelease) {
                                if (!(releaseTag ==~ /^v\d+\.\d+\.\d+$/)) {
                                    error("Tag de release invalide : ${releaseTag}. Format attendu : vMAJOR.MINOR.PATCH (ex. v1.0.0).")
                                }
                                releaseVersion = releaseTag.substring(1)
                            }
                            BACKEND_SERVICES.each { service ->
                                dir("backend/${service}") {
                                    if (isRelease) {
                                        withEnv(["RELEASE_VERSION=${releaseVersion}"]) {
                                            sh '''
                                                ./mvnw -B -s "$WORKSPACE/settings.xml" \
                                                  org.codehaus.mojo:versions-maven-plugin:2.19.1:set \
                                                  -DnewVersion="$RELEASE_VERSION" \
                                                  -DgenerateBackupPoms=false
                                                ./mvnw -B -s "$WORKSPACE/settings.xml" clean deploy \
                                                  -DskipTests
                                            '''
                                        }
                                    } else {
                                        sh '''
                                            ./mvnw -B -s "$WORKSPACE/settings.xml" deploy \
                                              -DskipTests
                                        '''
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        stage('Docker Build') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'nexus-credentials',
                        usernameVariable: 'NEXUS_USERNAME',
                        passwordVariable: 'NEXUS_PASSWORD'
                    )
                ]) {
                    sh '''
                        set +x
                        registry=nexus:8084
                        printf '%s' "$NEXUS_PASSWORD" | docker login "$registry" \
                          --username "$NEXUS_USERNAME" --password-stdin
                        trap 'docker logout "$registry" >/dev/null 2>&1 || true' EXIT
                        (cd backend && IMAGE_TAG="$IMAGE_TAG" docker compose build)
                        (cd frontend && docker build \
                          --build-arg "DOCKERHUB_PROXY=$NEXUS_DOCKER_PROXY" \
                          -t "frontend-app:$IMAGE_TAG" .)
                    '''
                }

                script {
                    def dockerTag = env.TAG_NAME
                        ? env.TAG_NAME.substring(1)
                        : "main-${env.GIT_COMMIT.take(12)}-${env.BUILD_NUMBER}"
                    writeFile file: 'image-tag.txt', text: "${env.IMAGE_TAG}\n"
                    writeFile file: 'nexus-docker-tag.txt', text: "${dockerTag}\n"
                }

                stash(
                    name: 'docker-image-tag',
                    includes: 'image-tag.txt,nexus-docker-tag.txt'
                )
            }
        }

        stage('End-to-End Tests') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'nexus-credentials',
                        usernameVariable: 'NEXUS_USERNAME',
                        passwordVariable: 'NEXUS_PASSWORD'
                    )
                ]) {
                    sh '''
                        set +x
                        registry=nexus:8084
                        printf '%s' "$NEXUS_PASSWORD" | docker login "$registry" \
                          --username "$NEXUS_USERNAME" --password-stdin
                        trap 'docker logout "$registry" >/dev/null 2>&1 || true' EXIT
                        bash ./scripts/e2e-tests.sh
                    '''
                }
            }
        }

        stage('Publish Docker Images to Nexus') {
            when {
                anyOf {
                    branch 'main'
                    buildingTag()
                }
            }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'nexus-credentials',
                        usernameVariable: 'NEXUS_USERNAME',
                        passwordVariable: 'NEXUS_PASSWORD'
                    )
                ]) {
                    script {
                        unstash 'docker-image-tag'
                        def nexusDockerTag = readFile('nexus-docker-tag.txt').trim()
                        withEnv(["NEXUS_DOCKER_TAG=${nexusDockerTag}"]) {
                            def pushStatus = sh(
                                returnStatus: true,
                                script: '''
                                    set +x
                                    registry=nexus:8082
                                    printf '%s' "$NEXUS_PASSWORD" | docker login "$registry" \
                                      --username "$NEXUS_USERNAME" --password-stdin
                                    trap 'docker logout "$registry" >/dev/null 2>&1 || true' EXIT

                                    push_status=0
                                    for image in \
                                      backend-api-gateway \
                                      backend-discovery-service \
                                      backend-media-service \
                                      backend-product-service \
                                      backend-security-service \
                                      backend-user-service \
                                      backend-order-service \
                                      frontend-app
                                    do
                                      docker tag "$image:$IMAGE_TAG" \
                                        "$registry/buy-02/$image:$NEXUS_DOCKER_TAG" || {
                                          push_status=$?
                                          break
                                        }
                                      docker push "$registry/buy-02/$image:$NEXUS_DOCKER_TAG" || {
                                          push_status=$?
                                          break
                                        }
                                    done

                                    exit "$push_status"
                                '''
                            )
                            if (pushStatus != 0) {
                                error("La publication des images Docker dans Nexus a échoué (code ${pushStatus}).")
                            }
                        }
                    }
                }
            }
        }

        stage('Deploy Backend') {
            when {
                branch 'main'
            }
            steps {
                script {
                    unstash 'docker-image-tag'
                    def deployTag = readFile('image-tag.txt').trim()
                    def nexusDockerTag = readFile('nexus-docker-tag.txt').trim()
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'nexus-credentials',
                            usernameVariable: 'NEXUS_USERNAME',
                            passwordVariable: 'NEXUS_PASSWORD'
                        )
                    ]) {
                        withEnv([
                            "IMAGE_TAG=${deployTag}",
                            "NEXUS_DOCKER_TAG=${nexusDockerTag}"
                        ]) {
                            echo "📦 Version à déployer : ${nexusDockerTag} depuis Nexus"
                            try {
                                sh 'bash ./scripts/deploy-backend.sh'
                            } catch (err) {
                                sh 'bash ./scripts/rollback-backend.sh'
                                error("❌ Déploiement Backend échoué — rollback exécuté")
                            }
                        }
                    }
                }
            }
        }

        stage('Deploy Frontend') {
            when {
                branch 'main'
            }
            steps {
                script {
                    unstash 'docker-image-tag'
                    def deployTag = readFile('image-tag.txt').trim()
                    def nexusDockerTag = readFile('nexus-docker-tag.txt').trim()
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'nexus-credentials',
                            usernameVariable: 'NEXUS_USERNAME',
                            passwordVariable: 'NEXUS_PASSWORD'
                        )
                    ]) {
                        withEnv([
                            "IMAGE_TAG=${deployTag}",
                            "NEXUS_DOCKER_TAG=${nexusDockerTag}"
                        ]) {
                            echo "📦 Version Frontend à déployer : ${nexusDockerTag} depuis Nexus"
                            try {
                                sh 'bash ./scripts/deploy-frontend.sh'
                            } catch (err) {
                                sh 'bash ./scripts/rollback-frontend.sh'
                                error("❌ Déploiement Frontend échoué — rollback exécuté")
                            }
                        }
                    }
                }
            }
        }

        stage('cleanUp') {
            when {
                branch 'main'
            }
            steps {
                script {
                    sh './scripts/cleanup-images.sh'
                }
            }
        }
    }

    post {
        always {
            junit(
                allowEmptyResults: true,
                testResults:
                    'backend/*/target/surefire-reports/*.xml, frontend/test-results/*.xml'
            )
        }
        success {
            echo "✅ Build réussi"
            emailext(
                subject: "✅ Jenkins SUCCESS - ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body:"""Build réussi.
                        Job: ${env.JOB_NAME}
                        Build: #${env.BUILD_NUMBER}
                        Branch: ${env.BRANCH_NAME}
                        Commit: ${env.GIT_COMMIT}
                        URL Jenkins:${env.BUILD_URL}""",

                to: "mohssinaynaou874@gmail.com"
            )
        }

        failure {
            echo "❌ Build échoué"
            emailext(
                subject: "❌ Jenkins FAILURE - ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                body:"""Build échoué.
                        Job: ${env.JOB_NAME}
                        Build: #${env.BUILD_NUMBER}
                        Branch: ${env.BRANCH_NAME}
                        Commit: ${env.GIT_COMMIT}
                        URL Jenkins:${env.BUILD_URL}""",

                to: "mohssinaynaou874@gmail.com"
            )
        }
    }
}
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    environment {
        // Jenkins credentials
        UIPATH_ORCH_URL = credentials('uipath-url')
        UIPATH_ORCH_LOGICAL_NAME = credentials('uipath-account')
        UIPATH_ORCH_TENANT_NAME = credentials('uipath-tenant')

        // UiPath project settings
        PACKAGE_ID = "Hello_World"
        PROJECT_JSON_PATH = "project.json"
        ENTRY_POINT = "Main.xaml"
        PROCESS_NAME = "Hello_World_Main.xaml"

        // Orchestrator folders
        DEV_FOLDER = "CICD Branch DEV"
        TEST_FOLDER = "CICD Pipeline TEST"
    }

    stages {

        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Determine Branch and Target Environment') {
            steps {
                script {
                    /*
                     * In a Multibranch Pipeline:
                     *
                     * BRANCH_NAME   = branch being built, e.g. main, feature/x, PR-12
                     * CHANGE_BRANCH = source branch of a PR, e.g. feature/x
                     * CHANGE_ID     = PR number, only present for PR builds
                     */

                    env.SOURCE_BRANCH = env.CHANGE_BRANCH ?: env.BRANCH_NAME
                    env.IS_PR_BUILD = env.CHANGE_ID ? "true" : "false"

                    echo "BRANCH_NAME   = ${env.BRANCH_NAME}"
                    echo "CHANGE_BRANCH = ${env.CHANGE_BRANCH ?: ''}"
                    echo "CHANGE_ID     = ${env.CHANGE_ID ?: ''}"
                    echo "SOURCE_BRANCH = ${env.SOURCE_BRANCH}"
                    echo "IS_PR_BUILD   = ${env.IS_PR_BUILD}"

                    if (env.SOURCE_BRANCH == "main") {
                        env.TARGET_ENV = "TEST"
                        env.ORCH_FOLDER = env.TEST_FOLDER
                    }
                    else if (env.SOURCE_BRANCH ==~ /^(feature|bugfix|hotfix)\/.+/) {
                        env.TARGET_ENV = "DEV"
                        env.ORCH_FOLDER = env.DEV_FOLDER
                    }
                    else {
                        error """
                        Branch name '${env.SOURCE_BRANCH}' is not allowed.

                        Use one of:
                        - feature/<description>
                        - bugfix/<description>
                        - hotfix/<description>
                        - main
                        """
                    }

                    /*
                     * Unique package version.
                     * Example: 1.2604.2915.3021
                     *
                     * Format:
                     * 1.<YYMM>.<DDHH>.<mmss>
                     *
                     * This prevents "Package already exists" conflicts in Orchestrator.
                     */
                    def stamp = powershell(
                        returnStdout: true,
                        script: '(Get-Date).ToString("yyMM.ddHH.mmss")'
                    ).trim()

                    env.PACKAGE_VERSION = "1.${stamp}"
                    env.OUTPUT_DIR = "Output\\${env.BUILD_NUMBER}"
                    env.PACKAGE_PATH = "${env.OUTPUT_DIR}\\${env.PACKAGE_ID}.${env.PACKAGE_VERSION}.nupkg"

                    echo "TARGET_ENV      = ${env.TARGET_ENV}"
                    echo "ORCH_FOLDER     = ${env.ORCH_FOLDER}"
                    echo "PACKAGE_VERSION = ${env.PACKAGE_VERSION}"
                    echo "PACKAGE_PATH    = ${env.PACKAGE_PATH}"
                }
            }
        }

        stage('Build Package') {
            steps {
                UiPathPack (
                    outputPath: "${env.OUTPUT_DIR}",
                    projectJsonPath: "${env.PROJECT_JSON_PATH}",
                    version: [$class: 'ManualVersionEntry', version: "${env.PACKAGE_VERSION}"],
                    useOrchestrator: false,
                    traceLevel: 'Verbose'
                )
            }
        }

        stage('Check Package') {
            steps {
                bat "dir \"${env.OUTPUT_DIR}\""
            }
        }

        stage('Deploy to DEV') {
            when {
                expression {
                    return env.TARGET_ENV == "DEV"
                }
            }
            steps {
                echo "Deploying ${env.PACKAGE_ID} ${env.PACKAGE_VERSION} to DEV folder: ${env.DEV_FOLDER}"

                UiPathDeploy (
                    packagePath: "${env.PACKAGE_PATH}",
                    orchestratorAddress: "${env.UIPATH_ORCH_URL}",
                    orchestratorTenant: "${env.UIPATH_ORCH_TENANT_NAME}",
                    folderName: "${env.DEV_FOLDER}",
                    environments: "",
                    entryPointPaths: "${env.ENTRY_POINT}",
                    credentials: Token(
                        accountName: "${env.UIPATH_ORCH_LOGICAL_NAME}",
                        credentialsId: "APIUserKey"
                    ),
                    createProcess: true,
                    traceLevel: 'Verbose'
                )
            }
        }

        stage('Run DEV Job') {
            when {
                expression {
                    return env.TARGET_ENV == "DEV"
                }
            }
            steps {
                echo "Running DEV validation job: ${env.PROCESS_NAME}"

                UiPathRunJob (
                    orchestratorAddress: "${env.UIPATH_ORCH_URL}",
                    orchestratorTenant: "${env.UIPATH_ORCH_TENANT_NAME}",
                    folderName: "${env.DEV_FOLDER}",
                    processName: "${env.PROCESS_NAME}",
                    jobType: Unattended(),
                    credentials: Token(
                        accountName: "${env.UIPATH_ORCH_LOGICAL_NAME}",
                        credentialsId: "APIUserKey"
                    ),
                    failWhenJobFails: true,
                    waitForJobCompletion: true,
                    timeout: 600,
                    priority: 'Normal',
                    resultFilePath: "",
                    parametersFilePath: "",
                    traceLevel: 'Verbose'
                )
            }
        }

        stage('Deploy to TEST') {
            when {
                expression {
                    return env.TARGET_ENV == "TEST"
                }
            }
            steps {
                echo "Deploying ${env.PACKAGE_ID} ${env.PACKAGE_VERSION} to TEST folder: ${env.TEST_FOLDER}"

                UiPathDeploy (
                    packagePath: "${env.PACKAGE_PATH}",
                    orchestratorAddress: "${env.UIPATH_ORCH_URL}",
                    orchestratorTenant: "${env.UIPATH_ORCH_TENANT_NAME}",
                    folderName: "${env.TEST_FOLDER}",
                    environments: "",
                    entryPointPaths: "${env.ENTRY_POINT}",
                    credentials: Token(
                        accountName: "${env.UIPATH_ORCH_LOGICAL_NAME}",
                        credentialsId: "APIUserKey"
                    ),
                    createProcess: true,
                    traceLevel: 'Verbose'
                )
            }
        }

        stage('Run TEST Job') {
            when {
                expression {
                    return env.TARGET_ENV == "TEST"
                }
            }
            steps {
                echo "Running TEST validation job: ${env.PROCESS_NAME}"

                UiPathRunJob (
                    orchestratorAddress: "${env.UIPATH_ORCH_URL}",
                    orchestratorTenant: "${env.UIPATH_ORCH_TENANT_NAME}",
                    folderName: "${env.TEST_FOLDER}",
                    processName: "${env.PROCESS_NAME}",
                    jobType: Unattended(),
                    credentials: Token(
                        accountName: "${env.UIPATH_ORCH_LOGICAL_NAME}",
                        credentialsId: "APIUserKey"
                    ),
                    failWhenJobFails: true,
                    waitForJobCompletion: true,
                    timeout: 600,
                    priority: 'Normal',
                    resultFilePath: "",
                    parametersFilePath: "",
                    traceLevel: 'Verbose'
                )
            }
        }
    }

    post {
        success {
            echo """
            Pipeline successful.

            Branch: ${env.SOURCE_BRANCH}
            Target: ${env.TARGET_ENV}
            Package: ${env.PACKAGE_ID} ${env.PACKAGE_VERSION}
            Folder: ${env.ORCH_FOLDER}
            """
        }

        failure {
            echo """
            Pipeline failed.

            Branch: ${env.SOURCE_BRANCH ?: env.BRANCH_NAME}
            Target: ${env.TARGET_ENV ?: 'unknown'}
            """
        }

        always {
            archiveArtifacts artifacts: "Output/${env.BUILD_NUMBER}/*.nupkg", allowEmptyArchive: true
        }
    }
}
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    environment {
        // Jenkins credentials - moeten Secret Text credentials zijn
        UIPATH_ORCH_URL = credentials('uipath-url')
        UIPATH_ORCH_LOGICAL_NAME = credentials('uipath-account')
        UIPATH_ORCH_TENANT_NAME = credentials('uipath-tenant')

        // UiPath settings
        PROJECT_JSON_PATH = "project.json"
        ENTRY_POINT = "Main.xaml"

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
                    env.SOURCE_BRANCH = env.CHANGE_BRANCH ?: env.BRANCH_NAME
                    env.IS_PR_BUILD = env.CHANGE_ID ? "true" : "false"

                    echo "BRANCH_NAME   = ${env.BRANCH_NAME}"
                    echo "CHANGE_BRANCH = ${env.CHANGE_BRANCH ?: ''}"
                    echo "CHANGE_TARGET = ${env.CHANGE_TARGET ?: ''}"
                    echo "CHANGE_ID     = ${env.CHANGE_ID ?: ''}"
                    echo "SOURCE_BRANCH = ${env.SOURCE_BRANCH}"
                    echo "IS_PR_BUILD   = ${env.IS_PR_BUILD}"

                    if (env.CHANGE_ID && env.CHANGE_TARGET != "main") {
                        error "Pull requests must target main. Current target is '${env.CHANGE_TARGET}'."
                    }

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

                    def stamp = powershell(
                        returnStdout: true,
                        script: '(Get-Date).ToString("yyMM.ddHH.mmss")'
                    ).trim()

                    env.PACKAGE_VERSION = "1.${stamp}"
                    env.OUTPUT_DIR = "Output\\${env.BUILD_NUMBER}"

                    echo "TARGET_ENV      = ${env.TARGET_ENV}"
                    echo "ORCH_FOLDER     = ${env.ORCH_FOLDER}"
                    echo "PACKAGE_VERSION = ${env.PACKAGE_VERSION}"
                    echo "OUTPUT_DIR      = ${env.OUTPUT_DIR}"
                }
            }
        }

        stage('Detect Changed Files') {
            steps {
                powershell '''
                $ErrorActionPreference = "Stop"

                git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main | Out-Null

                $branch = $env:SOURCE_BRANCH
                $isPr = $env:IS_PR_BUILD

                if ($isPr -eq "true") {
                    $target = $env:CHANGE_TARGET

                    if ([string]::IsNullOrWhiteSpace($target)) {
                        $target = "main"
                    }

                    $files = git diff --name-only "origin/$target...HEAD"
                }
                elseif ($branch -eq "main") {
                    git rev-parse --verify HEAD~1 2>$null | Out-Null

                    if ($LASTEXITCODE -eq 0) {
                        $files = git diff --name-only HEAD~1 HEAD
                    }
                    else {
                        $files = git ls-files
                    }
                }
                else {
                    $files = git diff --name-only origin/main...HEAD
                }

                $files | Out-File -FilePath changed-files.txt -Encoding utf8

                Write-Host "Changed files:"
                Get-Content changed-files.txt
                '''

                script {
                    def changedFiles = readFile('changed-files.txt')
                        .split(/\r?\n/)
                        .collect { it.trim().replace('\\', '/') }
                        .findAll { it }

                    echo "Changed files detected:"
                    changedFiles.each { echo " - ${it}" }

                    def uipathChanged = changedFiles.any { file ->
                        file == 'project.json' ||
                        file.endsWith('.xaml') ||
                        (file.endsWith('.json') && !file.startsWith('.github/')) ||
                        file.startsWith('Data/') ||
                        file.startsWith('Framework/') ||
                        file.startsWith('Tests/') ||
                        file.startsWith('Libraries/') ||
                        file.startsWith('Objects/') ||
                        file.startsWith('Screenshots/') ||
                        file.startsWith('Documentation/')
                    }

                    env.UIPATH_CHANGED = uipathChanged.toString()

                    echo "UIPATH_CHANGED = ${env.UIPATH_CHANGED}"

                    if (env.UIPATH_CHANGED != "true") {
                        echo """
                        No UiPath project changes detected.

                        Skipping:
                        - Validate UiPath Configuration
                        - Read UiPath Project Metadata
                        - Build Package
                        - Deploy
                        - Run Job

                        Jenkins will still report SUCCESS to GitHub.
                        """
                    }
                }
            }
        }

        stage('Validate UiPath Configuration') {
            when {
                expression {
                    return env.UIPATH_CHANGED == "true"
                }
            }
            steps {
                powershell '''
                $ErrorActionPreference = "Stop"

                $url = $env:UIPATH_ORCH_URL
                $account = $env:UIPATH_ORCH_LOGICAL_NAME
                $tenant = $env:UIPATH_ORCH_TENANT_NAME

                if ([string]::IsNullOrWhiteSpace($url)) {
                    throw "UIPATH_ORCH_URL is empty. Check Jenkins credential: uipath-url"
                }

                $url = $url.Trim()

                if (-not [Uri]::IsWellFormedUriString($url, [UriKind]::Absolute)) {
                    throw "UIPATH_ORCH_URL is not a valid absolute URL. Check Jenkins credential: uipath-url"
                }

                $uri = [Uri]$url

                if ($uri.Scheme -ne "https") {
                    throw "UIPATH_ORCH_URL must start with https://"
                }

                if ([string]::IsNullOrWhiteSpace($account)) {
                    throw "UIPATH_ORCH_LOGICAL_NAME is empty. Check Jenkins credential: uipath-account"
                }

                if ([string]::IsNullOrWhiteSpace($tenant)) {
                    throw "UIPATH_ORCH_TENANT_NAME is empty. Check Jenkins credential: uipath-tenant"
                }

                Write-Host "UiPath configuration format OK"
                '''
            }
        }

        stage('Read UiPath Project Metadata') {
            when {
                expression {
                    return env.UIPATH_CHANGED == "true"
                }
            }
            steps {
                powershell '''
                $ErrorActionPreference = "Stop"

                if (-not (Test-Path $env:PROJECT_JSON_PATH)) {
                    throw "project.json not found at path: $env:PROJECT_JSON_PATH"
                }

                $project = Get-Content -Raw $env:PROJECT_JSON_PATH | ConvertFrom-Json

                if ([string]::IsNullOrWhiteSpace($project.name)) {
                    throw "Could not read project name from project.json"
                }

                $project.name | Out-File -FilePath project_name.txt -Encoding ascii -NoNewline

                Write-Host "UiPath project metadata OK"
                '''

                script {
                    env.PROJECT_NAME = readFile('project_name.txt').trim()
                    env.PROCESS_NAME = "${env.PROJECT_NAME}_${env.ENTRY_POINT}"

                    echo "PROJECT_NAME = ${env.PROJECT_NAME}"
                    echo "PROCESS_NAME = ${env.PROCESS_NAME}"
                }
            }
        }

        stage('Build Package') {
            when {
                expression {
                    return env.UIPATH_CHANGED == "true"
                }
            }
            steps {
                UiPathPack (
                    outputPath: env.OUTPUT_DIR,
                    projectJsonPath: env.PROJECT_JSON_PATH,
                    version: [$class: 'ManualVersionEntry', version: env.PACKAGE_VERSION],
                    useOrchestrator: false,
                    traceLevel: 'Verbose'
                )
            }
        }

        stage('Check Package') {
            when {
                expression {
                    return env.UIPATH_CHANGED == "true"
                }
            }
            steps {
                bat '''
                @echo off

                echo Checking package output...
                dir "%OUTPUT_DIR%"

                if exist package_path.txt del package_path.txt

                for %%f in (%OUTPUT_DIR%\\*.nupkg) do (
                    echo %%f>package_path.txt
                )

                if not exist package_path.txt (
                    echo No .nupkg package found in %OUTPUT_DIR%
                    exit /b 1
                )
                '''

                script {
                    env.PACKAGE_PATH = readFile('package_path.txt').trim()
                    echo "PACKAGE_PATH = ${env.PACKAGE_PATH}"
                }
            }
        }

        stage('Deploy to DEV') {
            when {
                expression {
                    return env.UIPATH_CHANGED == "true" && env.TARGET_ENV == "DEV"
                }
            }
            steps {
                echo "Deploying ${env.PROJECT_NAME} ${env.PACKAGE_VERSION} to DEV folder: ${env.DEV_FOLDER}"

                UiPathDeploy (
                    packagePath: env.PACKAGE_PATH,
                    orchestratorAddress: env.UIPATH_ORCH_URL,
                    orchestratorTenant: env.UIPATH_ORCH_TENANT_NAME,
                    folderName: env.DEV_FOLDER,
                    environments: "",
                    entryPointPaths: env.ENTRY_POINT,
                    credentials: Token(
                        accountName: env.UIPATH_ORCH_LOGICAL_NAME,
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
                    return env.UIPATH_CHANGED == "true" && env.TARGET_ENV == "DEV"
                }
            }
            steps {
                echo "Running DEV validation job: ${env.PROCESS_NAME}"

                UiPathRunJob (
                    orchestratorAddress: env.UIPATH_ORCH_URL,
                    orchestratorTenant: env.UIPATH_ORCH_TENANT_NAME,
                    folderName: env.DEV_FOLDER,
                    processName: env.PROCESS_NAME,
                    jobType: Unattended(),
                    credentials: Token(
                        accountName: env.UIPATH_ORCH_LOGICAL_NAME,
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
                    return env.UIPATH_CHANGED == "true" && env.TARGET_ENV == "TEST"
                }
            }
            steps {
                echo "Deploying ${env.PROJECT_NAME} ${env.PACKAGE_VERSION} to TEST folder: ${env.TEST_FOLDER}"

                UiPathDeploy (
                    packagePath: env.PACKAGE_PATH,
                    orchestratorAddress: env.UIPATH_ORCH_URL,
                    orchestratorTenant: env.UIPATH_ORCH_TENANT_NAME,
                    folderName: env.TEST_FOLDER,
                    environments: "",
                    entryPointPaths: env.ENTRY_POINT,
                    credentials: Token(
                        accountName: env.UIPATH_ORCH_LOGICAL_NAME,
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
                    return env.UIPATH_CHANGED == "true" && env.TARGET_ENV == "TEST"
                }
            }
            steps {
                echo "Running TEST validation job: ${env.PROCESS_NAME}"

                UiPathRunJob (
                    orchestratorAddress: env.UIPATH_ORCH_URL,
                    orchestratorTenant: env.UIPATH_ORCH_TENANT_NAME,
                    folderName: env.TEST_FOLDER,
                    processName: env.PROCESS_NAME,
                    jobType: Unattended(),
                    credentials: Token(
                        accountName: env.UIPATH_ORCH_LOGICAL_NAME,
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

            Branch:         ${env.SOURCE_BRANCH}
            Target:         ${env.TARGET_ENV}
            UiPath changed: ${env.UIPATH_CHANGED}
            Project:        ${env.PROJECT_NAME ?: 'N/A'}
            Version:        ${env.PACKAGE_VERSION}
            Folder:         ${env.ORCH_FOLDER}
            Package:        ${env.PACKAGE_PATH ?: 'N/A'}
            """
        }

        failure {
            echo """
            Pipeline failed.

            Branch:         ${env.SOURCE_BRANCH ?: env.BRANCH_NAME}
            Target:         ${env.TARGET_ENV ?: 'unknown'}
            UiPath changed: ${env.UIPATH_CHANGED ?: 'unknown'}
            """
        }

        always {
            archiveArtifacts artifacts: "Output/${env.BUILD_NUMBER}/*.nupkg", allowEmptyArchive: true
        }
    }
}
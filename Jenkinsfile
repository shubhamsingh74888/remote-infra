// ============================================================
//  Jenkinsfile  →  place in: remote-infra/Jenkinsfile
//
//  Infrastructure Pipeline — Terraform S3/DynamoDB bootstrap
//  THEN EKS + Jenkins EC2 + ArgoCD via Wanderlust-Mega-Project/terraform
//
//  TRIGGER: Poll SCM or GitHub Webhook on remote-infra repo
//           (H/5 * * * *  OR  GitHub webhook)
//
//  REPOS USED:
//    1. remote-infra          → S3 bucket + DynamoDB (backend bootstrap)
//    2. Wanderlust-Mega-Project/terraform → VPC, EKS, Jenkins EC2, ArgoCD
//
//  CREDENTIAL IDs (must match Jenkins Manage Credentials exactly):
//    aws-creds       → Username/Password  (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
//    github          → Username/Password  (GitHub token)
// ============================================================

pipeline {

  agent any

  tools {
    terraform 'terraform-latest'
  }

  environment {
    AWS_DEFAULT_REGION = 'ap-south-1'
    CLUSTER_NAME       = 'wanderlust-prod-eks'
    TF_VAR_FILE        = 'env/prod.tfvars'
    BACKEND_CONFIG     = 'backend-configs/prod.hcl'
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '5'))
    timestamps()
    timeout(time: 90, unit: 'MINUTES')
    disableConcurrentBuilds()
    ansiColor('xterm')
  }

  parameters {
    choice(
      name: 'ACTION',
      choices: ['apply', 'plan-only', 'destroy'],
      description: '''
        apply      → Plan + Approval Gate + Apply + Bootstrap ArgoCD
        plan-only  → Run terraform plan only (safe, no changes)
        destroy    → Teardown EKS + all resources (requires approval)
      '''
    )
    booleanParam(
      name: 'SKIP_BOOTSTRAP',
      defaultValue: false,
      description: 'Skip ArgoCD bootstrap (use if cluster already bootstrapped)'
    )
    booleanParam(
      name: 'BOOTSTRAP_REMOTE_INFRA',
      defaultValue: false,
      description: 'Run Step 00 — create S3 bucket + DynamoDB via remote-infra repo (first-time only)'
    )
  }

  stages {

    // ── Stage 00 · Remote Backend Bootstrap (first-time only) ──
    // Creates the S3 bucket + DynamoDB table that all other
    // terraform workspaces use as remote backend.
    // Only runs if BOOTSTRAP_REMOTE_INFRA = true.
    stage('00 · Remote Backend · Bootstrap') {
      when {
        expression { params.BOOTSTRAP_REMOTE_INFRA == true }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          git branch: 'main',
              credentialsId: 'github',
              url: 'https://github.com/shubhamsingh74888/remote-infra.git'

          sh '''
            echo "[REMOTE-INFRA] Initialising remote backend infrastructure..."
            terraform init
            terraform workspace select prod || terraform workspace new prod
            terraform plan  -out=remote-infra.tfplan
            terraform apply -auto-approve remote-infra.tfplan
            echo "[REMOTE-INFRA] ✔ S3 bucket + DynamoDB ready."
          '''
        }
      }
    }

    // ── Stage 01 · Checkout Main Repo ──────────────────────
    stage('01 · Checkout · Wanderlust-Mega-Project') {
      steps {
        git branch: 'main',
            credentialsId: 'github',
            url: 'https://github.com/shubhamsingh74888/Wanderlust-Mega-Project.git'

        echo "[CHECKOUT] ✔ Checked out Wanderlust-Mega-Project"
      }
    }

    // ── Stage 02 · Terraform Init ───────────────────────────
    stage('02 · Terraform · Init') {
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          dir('terraform') {
            sh '''
              echo "[INIT] Initialising Terraform with prod backend..."
              terraform init \
                -backend-config=${BACKEND_CONFIG} \
                -reconfigure
              terraform workspace select prod || terraform workspace new prod
              echo "[INIT] ✔ Workspace: prod"
            '''
          }
        }
      }
    }

    // ── Stage 03 · Terraform Plan ───────────────────────────
    // KEY: state rm runs BEFORE plan — prevents "Saved plan is stale"
    stage('03 · Terraform · Plan') {
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          dir('terraform') {
            sh '''
              rm -f tfplan

              echo "[PLAN] Cleaning stale state entries (Prometheus → ArgoCD)..."
              terraform state rm 'module.eks[0].helm_release.prometheus[0]' || true
              terraform state rm 'module.eks[0].helm_release.argocd[0]'     || true

              echo "[PLAN] Running terraform plan..."
              terraform plan \
                -var-file="${TF_VAR_FILE}" \
                -out=tfplan \
                -detailed-exitcode || true

              echo "[PLAN] ✔ Plan complete — review above before approving."
            '''
          }
        }
      }
    }

    // ── Stage 04 · Approval Gate ────────────────────────────
    stage('04 · Approval Gate') {
      when {
        expression { params.ACTION == 'apply' || params.ACTION == 'destroy' }
      }
      steps {
        timeout(time: 15, unit: 'MINUTES') {
          input(
            message: "⚠️  Approve Terraform ${params.ACTION.toUpperCase()} on PRODUCTION EKS?",
            ok: "Yes, ${params.ACTION.toUpperCase()} it"
          )
        }
      }
    }

    // ── Stage 05 · Terraform Apply ──────────────────────────
    stage('05 · Terraform · Apply') {
      when {
        expression { params.ACTION == 'apply' }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          dir('terraform') {
            sh '''
              echo "[APPLY] Applying terraform plan..."
              terraform apply -auto-approve tfplan
              echo "[APPLY] ✔ Infrastructure applied."
            '''
          }
        }
      }
    }

    // ── Stage 06 · Terraform Destroy ────────────────────────
    stage('06 · Terraform · Destroy') {
      when {
        expression { params.ACTION == 'destroy' }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          dir('terraform') {
            sh '''
              echo "[DESTROY] ⚠ Destroying all infrastructure..."
              terraform destroy \
                -var-file="${TF_VAR_FILE}" \
                -auto-approve
              echo "[DESTROY] ✔ Infrastructure destroyed."
            '''
          }
        }
      }
    }

    // ── Stage 07 · Bootstrap ArgoCD + GitOps ───────────────
    stage('07 · Bootstrap · ArgoCD + GitOps') {
      when {
        allOf {
          expression { params.ACTION == 'apply' }
          expression { params.SKIP_BOOTSTRAP == false }
        }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          sh '''
            STATUS=$(aws eks describe-cluster \
              --name ${CLUSTER_NAME} \
              --region ${AWS_DEFAULT_REGION} \
              --query 'cluster.status' \
              --output text 2>/dev/null || echo "NOT_FOUND")

            echo "[BOOTSTRAP] Cluster status: $STATUS"

            if [ "$STATUS" = "ACTIVE" ]; then
              aws eks update-kubeconfig \
                --name ${CLUSTER_NAME} \
                --region ${AWS_DEFAULT_REGION}

              chmod +x bootstrap-gitops.sh
              ./bootstrap-gitops.sh
            else
              echo "[BOOTSTRAP] ⚠ Cluster not ACTIVE ($STATUS) — skipping bootstrap."
            fi
          '''
        }
      }
    }

    // ── Stage 08 · Scale · Ensure 2 Nodes ─────────────────
    stage('08 · Scale · Ensure 2 Nodes') {
      when {
        expression { params.ACTION == 'apply' }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          sh '''
            aws eks update-kubeconfig \
              --name ${CLUSTER_NAME} \
              --region ${AWS_DEFAULT_REGION} 2>/dev/null || true

            NODEGROUP=$(aws eks list-nodegroups \
              --cluster-name ${CLUSTER_NAME} \
              --region ${AWS_DEFAULT_REGION} \
              --query 'nodegroups[0]' \
              --output text 2>/dev/null || echo "")

            if [ -n "$NODEGROUP" ] && [ "$NODEGROUP" != "None" ]; then
              aws eks update-nodegroup-config \
                --cluster-name ${CLUSTER_NAME} \
                --nodegroup-name "$NODEGROUP" \
                --scaling-config minSize=1,maxSize=3,desiredSize=2 \
                --region ${AWS_DEFAULT_REGION} 2>/dev/null || true

              echo "[SCALE] Waiting for nodes to be Ready..."
              kubectl wait --for=condition=Ready nodes \
                --all --timeout=300s || true
            fi

            echo "[SCALE] ── Node Status ──"
            kubectl get nodes 2>/dev/null || echo "[SCALE] Cluster not yet accessible."
            echo "[SCALE] ✔ Done."
          '''
        }
      }
    }

  }

  post {
    success {
      echo "✅ Infra pipeline PASSED — Action: ${params.ACTION}"
    }
    failure {
      echo "❌ Infra pipeline FAILED — Action: ${params.ACTION}"
    }
    always {
      cleanWs()
    }
  }
}

// ============================================================
//  Jenkinsfile  →  remote-infra/Jenkinsfile
//
//  Infrastructure Pipeline — Terraform S3/DynamoDB bootstrap
//  THEN EKS + Jenkins EC2 + ArgoCD via Wanderlust-Mega-Project/terraform
//
//  CREDENTIAL IDs:
//    aws-creds  → Username/Password (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
//    github     → Username/Password (GitHub token)
// ============================================================

pipeline {

  agent any

  tools {
    terraform 'terraform-latest'
  }

  // ── Dynamic Variables mapping from parameters ────────────
  environment {
    AWS_DEFAULT_REGION = "${params.AWS_REGION}"
    ENV_NAME           = "${params.ENVIRONMENT}"
    CLUSTER_NAME       = "wanderlust-${params.ENVIRONMENT}-eks"
    TF_VAR_FILE        = "env/${params.ENVIRONMENT}.tfvars"
    BACKEND_CONFIG     = "backend-configs/${params.ENVIRONMENT}.hcl"
    INFRA_REPO         = "${params.INFRA_REPO_URL}"
    PROJECT_REPO       = "${params.PROJECT_REPO_URL}"
    PATH               = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${env.PATH}"
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '10'))
    timestamps()
    timeout(time: 90, unit: 'MINUTES')
    disableConcurrentBuilds()
    ansiColor('xterm')
  }

  parameters {
    choice(
      name: 'ACTION',
      choices: ['apply', 'plan-only', 'destroy'],
      description: 'Pipeline execution action'
    )
    choice(
      name: 'ENVIRONMENT',
      choices: ['prod', 'staging', 'dev'],
      description: 'Target environment (Determines workspace, tfvars, and naming)'
    )
    string(
      name: 'AWS_REGION',
      defaultValue: 'ap-south-1',
      description: 'Target AWS Region'
    )
    string(
      name: 'INFRA_REPO_URL',
      defaultValue: 'https://github.com/shubhamsingh74888/remote-infra.git',
      description: 'Repository for remote backend bootstrap'
    )
    string(
      name: 'PROJECT_REPO_URL',
      defaultValue: 'https://github.com/shubhamsingh74888/Wanderlust-Mega-Project.git',
      description: 'Main project repository'
    )
    booleanParam(
      name: 'SKIP_BOOTSTRAP',
      defaultValue: false,
      description: 'Skip ArgoCD bootstrap'
    )
    booleanParam(
      name: 'BOOTSTRAP_REMOTE_INFRA',
      defaultValue: false,
      description: 'Run Stage 00 — create S3 + DynamoDB (first-time only)'
    )
  }

  stages {

    // ── Stage 00 · Remote Backend Bootstrap ────────────────────
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
          git branch: 'main', credentialsId: 'github', url: "${env.INFRA_REPO}"

          sh '''
            export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            echo "[REMOTE-INFRA] Running in AWS Account: $ACCOUNT_ID | Region: $AWS_DEFAULT_REGION"
            echo "[REMOTE-INFRA] Initialising remote backend infrastructure..."

            terraform init
            terraform workspace select ${ENV_NAME} || terraform workspace new ${ENV_NAME}
            terraform plan  -out=remote-infra.tfplan
            terraform apply -auto-approve remote-infra.tfplan

            echo "[REMOTE-INFRA] ✔ S3 bucket + DynamoDB ready."
          '''
        }
      }
    }

    // ── Stage 01 · Checkout Main Repo ──────────────────────────
    stage('01 · Checkout · Wanderlust-Mega-Project') {
      steps {
        git branch: 'main', credentialsId: 'github', url: "${env.PROJECT_REPO}"
        echo "[CHECKOUT] ✔ Checked out ${env.PROJECT_REPO} for environment: ${env.ENV_NAME}"
      }
    }

    // ── Stage 02 · Terraform Init ──────────────────────────────
    stage('02 · Terraform · Init') {
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          dir('terraform') {
            sh '''
              export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
              echo "[INIT] Initialising Terraform with backend: ${BACKEND_CONFIG}..."
              terraform init \
                -backend-config=${BACKEND_CONFIG} \
                -reconfigure
              terraform workspace select ${ENV_NAME} || terraform workspace new ${ENV_NAME}
              echo "[INIT] ✔ Workspace: ${ENV_NAME}"
            '''
          }
        }
      }
    }

    // ── Stage 03 · State Reconciliation + Plan ─────────────────
    stage('03 · Terraform · Reconcile + Plan') {
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          dir('terraform') {
            sh '''
              export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
              rm -f tfplan

              # Define dynamic resource names based on environment
              ROLE_NAME="wanderlust-${ENV_NAME}-jenkins-role"
              PROFILE_NAME="wanderlust-${ENV_NAME}-jenkins-profile"
              CUSTOM_POLICY="${ROLE_NAME}:wanderlust-${ENV_NAME}-jenkins-custom"
              SERVER_TAG="wanderlust-${ENV_NAME}-cicd-server"
              EIP_TAG="wanderlust-${ENV_NAME}-cicd-eip"

              echo "[RECONCILE] Removing stale helm state entries..."
              terraform state rm 'module.eks[0].helm_release.prometheus[0]' || true
              terraform state rm 'module.eks[0].helm_release.argocd[0]'     || true

              echo "[RECONCILE] Checking IAM role ($ROLE_NAME)..."
              terraform state show 'module.cicd_server.aws_iam_role.jenkins' > /dev/null 2>&1 || \
              terraform import -var-file="${TF_VAR_FILE}" 'module.cicd_server.aws_iam_role.jenkins' "$ROLE_NAME" || true

              echo "[RECONCILE] Checking IAM instance profile ($PROFILE_NAME)..."
              terraform state show 'module.cicd_server.aws_iam_instance_profile.jenkins' > /dev/null 2>&1 || \
              terraform import -var-file="${TF_VAR_FILE}" 'module.cicd_server.aws_iam_instance_profile.jenkins' "$PROFILE_NAME" || true

              echo "[RECONCILE] Checking IAM inline policy..."
              terraform state show 'module.cicd_server.aws_iam_role_policy.jenkins_custom' > /dev/null 2>&1 || \
              terraform import -var-file="${TF_VAR_FILE}" 'module.cicd_server.aws_iam_role_policy.jenkins_custom' "$CUSTOM_POLICY" || true

              echo "[RECONCILE] Checking IAM policy attachments..."
              terraform state show 'module.cicd_server.aws_iam_role_policy_attachment.ssm' > /dev/null 2>&1 || \
              terraform import -var-file="${TF_VAR_FILE}" 'module.cicd_server.aws_iam_role_policy_attachment.ssm' "$ROLE_NAME/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" || true

              terraform state show 'module.cicd_server.aws_iam_role_policy_attachment.ecr' > /dev/null 2>&1 || \
              terraform import -var-file="${TF_VAR_FILE}" 'module.cicd_server.aws_iam_role_policy_attachment.ecr' "$ROLE_NAME/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess" || true

              echo "[RECONCILE] Checking EC2 instance ($SERVER_TAG)..."
              INSTANCE_ID=$(aws ec2 describe-instances \
                --filters "Name=tag:Name,Values=$SERVER_TAG" "Name=instance-state-name,Values=running,stopped" \
                --query 'Reservations[0].Instances[0].InstanceId' --output text --region ${AWS_DEFAULT_REGION} 2>/dev/null || echo "")

              if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
                terraform state show 'module.cicd_server.aws_instance.cicd' > /dev/null 2>&1 || \
                terraform import -var-file="${TF_VAR_FILE}" 'module.cicd_server.aws_instance.cicd' "$INSTANCE_ID" || true
                echo "[RECONCILE] ✔ EC2 instance $INSTANCE_ID reconciled."
              fi

              echo "[RECONCILE] Checking EIP ($EIP_TAG)..."
              EIP_ALLOC=$(aws ec2 describe-addresses \
                --filters "Name=tag:Name,Values=$EIP_TAG" \
                --query 'Addresses[0].AllocationId' --output text --region ${AWS_DEFAULT_REGION} 2>/dev/null || echo "")

              if [ -n "$EIP_ALLOC" ] && [ "$EIP_ALLOC" != "None" ]; then
                terraform state show 'module.cicd_server.aws_eip.cicd' > /dev/null 2>&1 || \
                terraform import -var-file="${TF_VAR_FILE}" 'module.cicd_server.aws_eip.cicd' "$EIP_ALLOC" || true
                echo "[RECONCILE] ✔ EIP $EIP_ALLOC reconciled."
              fi

              echo "[RECONCILE] ✔ State reconciliation complete."

              echo "[PLAN] Running terraform plan for environment: ${ENV_NAME}..."
              set +e
              terraform plan -var-file="${TF_VAR_FILE}" -out=tfplan -detailed-exitcode
              PLAN_EXIT=$?
              set -e

              if [ $PLAN_EXIT -eq 1 ]; then
                echo "[PLAN] ✘ Terraform plan encountered an error."
                exit 1
              elif [ $PLAN_EXIT -eq 0 ]; then
                echo "[PLAN] ✔ No infrastructure changes needed."
              else
                PLAN_SUMMARY=$(terraform show -no-color tfplan | grep -E '^Plan:|^No changes' || echo "Changes pending")
                echo "[PLAN] ✔ Changes detected: $PLAN_SUMMARY"
                echo "$PLAN_SUMMARY" > /tmp/plan-summary.txt
              fi
            '''
          }
        }
      }
    }

    // ── Stage 04 · Approval Gate ────────────────────────────────
    stage('04 · Approval Gate') {
      when {
        expression { params.ACTION == 'apply' || params.ACTION == 'destroy' }
      }
      steps {
        script {
          def planSummary = "No plan summary file found."
          try {
            planSummary = sh(script: "cat /tmp/plan-summary.txt 2>/dev/null || echo 'No changes or plan-only run'", returnStdout: true).trim()
          } catch (ignored) {}

          timeout(time: 15, unit: 'MINUTES') {
            input(
              message: """⚠️  Approve Terraform ${params.ACTION.toUpperCase()} on ${env.ENV_NAME.toUpperCase()} EKS?

Plan summary: ${planSummary}

ACTION: ${params.ACTION.toUpperCase()}
Cluster: ${env.CLUSTER_NAME}
Region:  ${env.AWS_DEFAULT_REGION}""",
              ok: "Yes, ${params.ACTION.toUpperCase()} it"
            )
          }
        }
      }
    }

    // ── Stage 05 · Terraform Apply ──────────────────────────────
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
              export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
              rm -f /tmp/plan-summary.txt
              if [ ! -f tfplan ]; then
                echo "[APPLY] ✘ tfplan not found — re-run from Stage 03."
                exit 1
              fi

              echo "[APPLY] Applying terraform plan to ${ENV_NAME}..."
              terraform apply -auto-approve tfplan
              echo "[APPLY] ✔ Infrastructure applied."
            '''
          }
        }
      }
    }

    // ── Stage 06 · Pre-Destroy Cleanup ──────────────────────────
    stage('06 · Pre-Destroy · Cleanup') {
      when {
        expression { params.ACTION == 'destroy' }
      }
      steps {
        withCredentials([usernamePassword(
          credentialsId   : 'aws-creds',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          sh '''
            export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
            echo "[CLEANUP] Cleaning up before destroy..."
            aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_DEFAULT_REGION} 2>/dev/null || true
            kubectl delete application --all -n argocd --timeout=60s 2>/dev/null || true
            kubectl delete svc -n wanderlust --field-selector spec.type=LoadBalancer --timeout=120s 2>/dev/null || true
            echo "[CLEANUP] ✔ Pre-destroy cleanup complete."
            sleep 30
          '''
        }
      }
    }

    // ── Stage 07 · Terraform Destroy ────────────────────────────
    stage('07 · Terraform · Destroy') {
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
              export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
              echo "[DESTROY] ⚠ Destroying ${ENV_NAME} infrastructure..."
              terraform destroy -var-file="${TF_VAR_FILE}" -auto-approve
              echo "[DESTROY] ✔ Infrastructure destroyed."
            '''
          }
        }
      }
    }

    // ── Stage 08 · Bootstrap ArgoCD + GitOps ────────────────────
    stage('08 · Bootstrap · ArgoCD + GitOps') {
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
            export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
            echo "[BOOTSTRAP] Checking EKS cluster status..."

            STATUS=$(aws eks describe-cluster \
              --name ${CLUSTER_NAME} \
              --region ${AWS_DEFAULT_REGION} \
              --query 'cluster.status' \
              --output text 2>/dev/null || echo "NOT_FOUND")

            echo "[BOOTSTRAP] Cluster status: $STATUS"
            if [ "$STATUS" != "ACTIVE" ]; then
              echo "[BOOTSTRAP] ⚠ Cluster not ACTIVE — skipping bootstrap."
              exit 0
            fi

            echo "[BOOTSTRAP] Updating kubeconfig..."
            aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_DEFAULT_REGION}

            # Self-heal kubectl if missing (fallback for old AMI)
            if ! command -v kubectl &>/dev/null; then
              echo "[BOOTSTRAP] kubectl missing — installing..."
              curl -fsSL "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl" -o /tmp/kubectl
              install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
              ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
              rm -f /tmp/kubectl
              echo "[BOOTSTRAP] ✔ kubectl ready"
            fi

            echo "[BOOTSTRAP] Waiting for nodes to be Ready..."
            kubectl wait --for=condition=Ready nodes --all --timeout=300s || true

            echo "[BOOTSTRAP] Running GitOps bootstrap script..."
            chmod +x bootstrap-gitops.sh
            ./bootstrap-gitops.sh

            echo "[BOOTSTRAP] ✔ ArgoCD + GitOps bootstrap complete."
          '''
        }
      }
    }

    // ── Stage 09 · Scale · Ensure 2 Nodes ───────────────────────
    stage('09 · Scale · Ensure 2 Nodes') {
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
            export PATH=/usr/local/bin:/usr/bin:/bin:$PATH
            echo "[SCALE] Checking node count..."

            aws eks update-kubeconfig \
              --name ${CLUSTER_NAME} \
              --region ${AWS_DEFAULT_REGION} 2>/dev/null || true

            NODEGROUP=$(aws eks list-nodegroups \
              --cluster-name ${CLUSTER_NAME} \
              --region ${AWS_DEFAULT_REGION} \
              --query 'nodegroups[0]' \
              --output text 2>/dev/null || echo "")

            if [ -n "$NODEGROUP" ] && [ "$NODEGROUP" != "None" ]; then
              CURRENT_DESIRED=$(aws eks describe-nodegroup \
                --cluster-name ${CLUSTER_NAME} \
                --nodegroup-name "$NODEGROUP" \
                --region ${AWS_DEFAULT_REGION} \
                --query 'nodegroup.scalingConfig.desiredSize' \
                --output text 2>/dev/null || echo "0")

              echo "[SCALE] Current desired nodes: $CURRENT_DESIRED"

              if [ "$CURRENT_DESIRED" -lt 2 ]; then
                echo "[SCALE] Scaling up to 2 nodes..."
                aws eks update-nodegroup-config \
                  --cluster-name ${CLUSTER_NAME} \
                  --nodegroup-name "$NODEGROUP" \
                  --scaling-config minSize=1,maxSize=3,desiredSize=2 \
                  --region ${AWS_DEFAULT_REGION} 2>/dev/null || true
                kubectl wait --for=condition=Ready nodes --all --timeout=300s || true
              else
                echo "[SCALE] ✔ Already have $CURRENT_DESIRED nodes — no scaling needed."
              fi
            fi
          '''
        }
      }
    }

    // ── Stage 10 · Deployment Summary ───────────────────────────
    stage('10 · Summary · Deployment Report') {
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
            export PATH=/usr/local/bin:/usr/bin:/bin:$PATH

            aws eks update-kubeconfig \
              --name ${CLUSTER_NAME} \
              --region ${AWS_DEFAULT_REGION} 2>/dev/null || true

            ARGOCD_LB=$(kubectl get svc argocd-server -n argocd \
              -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
              2>/dev/null || echo "Pending")

            JENKINS_IP=$(aws ec2 describe-addresses \
              --filters "Name=tag:Name,Values=wanderlust-${ENV_NAME}-cicd-eip" \
              --query 'Addresses[0].PublicIp' \
              --output text \
              --region ${AWS_DEFAULT_REGION} 2>/dev/null || echo "Not found")

            echo ""
            echo "╔══════════════════════════════════════════════════════╗"
            echo "║         WANDERLUST INFRA — DEPLOYMENT SUMMARY        ║"
            echo "╚══════════════════════════════════════════════════════╝"
            echo ""
            echo "  Environment : ${ENV_NAME}"
            echo "  Region      : ${AWS_DEFAULT_REGION}"
            echo "  Cluster     : ${CLUSTER_NAME}"
            echo ""
            echo "  ArgoCD URL  : https://$ARGOCD_LB"
            echo "  Jenkins URL : http://$JENKINS_IP:8080"
            echo ""
            echo "✅ Deployment complete."
          '''
        }
      }
    }

  }

  post {
    success { echo "✅ Infra pipeline PASSED — Env: ${env.ENV_NAME} | Action: ${params.ACTION}" }
    failure { echo "❌ Infra pipeline FAILED — Env: ${env.ENV_NAME} | Action: ${params.ACTION}" }
    always  { cleanWs() }
  }
}

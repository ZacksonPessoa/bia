#!/bin/bash
set -e

ECR_REGISTRY="380093117576.dkr.ecr.us-east-1.amazonaws.com"
ECR_REPO="$ECR_REGISTRY/bia"
CLUSTER="cluster-bia"
SERVICE="service-bia"
FAMILY="task-def-bia"
COMMIT_HASH=$(git rev-parse --short HEAD)

echo ">>> Commit: $COMMIT_HASH"

# Login ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REGISTRY

# Build e push
docker build -t bia .
docker tag bia:latest $ECR_REPO:$COMMIT_HASH
docker tag bia:latest $ECR_REPO:latest
docker push $ECR_REPO:$COMMIT_HASH
docker push $ECR_REPO:latest

echo ">>> Imagem: $ECR_REPO:$COMMIT_HASH"

# Registra nova Task Definition com a imagem versionada
CURRENT_TD=$(aws ecs describe-task-definition --task-definition $FAMILY --query 'taskDefinition' --output json)

NEW_TD=$(echo $CURRENT_TD | python3 -c "
import json, sys
td = json.load(sys.stdin)
td['containerDefinitions'][0]['image'] = '$ECR_REPO:$COMMIT_HASH'
print(json.dumps({k: td[k] for k in ['family','containerDefinitions','networkMode','executionRoleArn','requiresCompatibilities','cpu','memory'] if k in td}))
" 2>/dev/null || echo $CURRENT_TD | python3 -c "
import json, sys
td = json.load(sys.stdin)
td['containerDefinitions'][0]['image'] = '$ECR_REPO:$COMMIT_HASH'
keys = ['family','containerDefinitions','networkMode','executionRoleArn','requiresCompatibilities']
print(json.dumps({k: td[k] for k in keys if k in td}))
")

NEW_REVISION=$(aws ecs register-task-definition --cli-input-json "$NEW_TD" --query 'taskDefinition.taskDefinitionArn' --output text)

echo ">>> Nova Task Definition: $NEW_REVISION"

# Deploy no ECS
aws ecs update-service --cluster $CLUSTER --service $SERVICE --task-definition $NEW_REVISION --force-new-deployment --query 'service.deployments[0].{id:id,status:status,taskDef:taskDefinition}' --output table

echo ">>> Deploy iniciado com commit $COMMIT_HASH"

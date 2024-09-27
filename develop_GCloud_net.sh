#!/bin/bash

# Set the zone and region based on user-defined zone
ZONE="us-west1-c"
REGION="${ZONE%-*}"

# Terminal Colors
COLOR_RESET=$(tput sgr0)
COLOR_RED=$(tput setaf 1)
COLOR_GREEN=$(tput setaf 2)
COLOR_YELLOW=$(tput setaf 3)
COLOR_BOLD=$(tput bold)

# Start script execution
echo "${COLOR_YELLOW}${COLOR_BOLD}Starting the script...${COLOR_RESET}"

# Task 1: Create Development VPC and Subnets
echo "${COLOR_GREEN}${COLOR_BOLD}Task 1: Creating Development VPC and Subnets...${COLOR_RESET}"
gcloud compute networks create griffin-dev-vpc --subnet-mode=custom
gcloud compute networks subnets create griffin-dev-wp --network=griffin-dev-vpc --region=$REGION --range=192.168.16.0/20
gcloud compute networks subnets create griffin-dev-mgmt --network=griffin-dev-vpc --region=$REGION --range=192.168.32.0/20

# Task 2: Create Production VPC using Deployment Manager
echo "${COLOR_GREEN}${COLOR_BOLD}Task 2: Creating Production VPC...${COLOR_RESET}"
gsutil cp -r gs://cloud-training/gsp321/dm .
sed -i "s/SET_REGION/$REGION/g" dm/prod-network.yaml
gcloud deployment-manager deployments create prod-network --config=dm/prod-network.yaml

# Task 3: Create Bastion Host
echo "${COLOR_GREEN}${COLOR_BOLD}Task 3: Creating Bastion Host...${COLOR_RESET}"
gcloud compute instances create bastion \
  --network-interface=network=griffin-dev-vpc,subnet=griffin-dev-mgmt \
  --network-interface=network=griffin-prod-vpc,subnet=griffin-prod-mgmt \
  --tags=allow-ssh --zone=$ZONE
gcloud compute firewall-rules create allow-ssh-dev --allow=tcp:22 --network=griffin-dev-vpc --target-tags=allow-ssh
gcloud compute firewall-rules create allow-ssh-prod --allow=tcp:22 --network=griffin-prod-vpc --target-tags=allow-ssh

# Task 4: Create and Configure Cloud SQL Instance
echo "${COLOR_GREEN}${COLOR_BOLD}Task 4: Creating Cloud SQL Instance...${COLOR_RESET}"
gcloud sql instances create griffin-dev-db --database-version=MYSQL_5_7 --region=$REGION --root-password='secure_password'
gcloud sql databases create wordpress --instance=griffin-dev-db
gcloud sql users create wp_user --instance=griffin-dev-db --password='stormwind_rules'

# Task 5: Create Kubernetes Cluster
echo "${COLOR_GREEN}${COLOR_BOLD}Task 5: Creating Kubernetes Cluster...${COLOR_RESET}"
gcloud container clusters create griffin-dev \
  --network=griffin-dev-vpc \
  --subnetwork=griffin-dev-wp \
  --machine-type=e2-standard-4 \
  --num-nodes=2 \
  --zone=$ZONE
gcloud container clusters get-credentials griffin-dev --zone=$ZONE

# Task 6: Prepare Kubernetes Cluster with Secrets and Volumes
echo "${COLOR_GREEN}${COLOR_BOLD}Task 6: Preparing Kubernetes Cluster...${COLOR_RESET}"
cd ~/

gsutil cp -r gs://cloud-training/gsp321/wp-k8s .
cat > wp-k8s/wp-env.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wordpress-pv-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: v1
kind: Secret
metadata:
  name: wp-db-secret
type: Opaque
stringData:
  username: wp_user
  password: stormwind_rules
EOF

cd wp-k8s

kubectl apply -f wp-k8s/wp-env.yaml

gcloud iam service-accounts keys create key.json \
    --iam-account=cloud-sql-proxy@$GOOGLE_CLOUD_PROJECT.iam.gserviceaccount.com
kubectl create secret generic cloudsql-instance-credentials --from-file=key.json

# Task 7: Create WordPress Deployment
echo "${COLOR_GREEN}${COLOR_BOLD}Task 7: Deploying WordPress...${COLOR_RESET}"
INSTANCE_CONN_NAME=$(gcloud sql instances describe griffin-dev-db --format='value(connectionName)')
cat > wp-k8s/wp-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      containers:
      - image: wordpress
        name: wordpress
        env:
        - name: WORDPRESS_DB_HOST
          value: 127.0.0.1:3306
        - name: WORDPRESS_DB_USER
          valueFrom:
            secretKeyRef:
              name: wp-db-secret
              key: username
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: wp-db-secret
              key: password
        volumeMounts:
        - name: wordpress-pv-storage
          mountPath: /var/www/html
      - image: gcr.io/cloudsql-docker/gce-proxy:1.33.2
        name: cloudsql-proxy
        command: ["/cloud_sql_proxy", "-instances=$INSTANCE_CONN_NAME=tcp:3306", "-credential_file=/secrets/cloudsql/key.json"]
        volumeMounts:
        - name: cloudsql-instance-credentials
          mountPath: /secrets/cloudsql
          readOnly: true
      volumes:
      - name: wordpress-pv-storage
        persistentVolumeClaim:
          claimName: wordpress-pv-claim
      - name: cloudsql-instance-credentials
        secret:
          secretName: cloudsql-instance-credentials
EOF

kubectl apply -f wp-k8s/wp-deployment.yaml
kubectl apply -f wp-k8s/wp-service.yaml

# Task 8: Enable Monitoring
echo "${COLOR_GREEN}${COLOR_BOLD}Task 8: Setting up Uptime Monitoring...${COLOR_RESET}"
gcloud monitoring uptime-checks create http wordpress-check \
    --host=YOUR-WORDPRESS-LB-IP --path="/"

# Task 9: Grant Editor Access to Engineer
echo "${COLOR_GREEN}${COLOR_BOLD}Task 9: Granting Access to Additional Engineer...${COLOR_RESET}"
ENGINEER_EMAIL=" "
gcloud projects add-iam-policy-binding $GOOGLE_CLOUD_PROJECT \
    --member="user:$ENGINEER_EMAIL" --role="roles/editor"

# Script Completion
echo "${COLOR_GREEN}${COLOR_BOLD}Script execution completed!${COLOR_RESET}"

#!/bin/bash
# Define color variables
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BG_BLACK=$(tput setab 0)
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)
BG_WHITE=$(tput setab 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)

#----------------------------------------------------start--------------------------------------------------#

# Define environmental variables
export IAP_NET_TAG=""
export INT_NET_TAG=" "
export HTTP_NET_TAG=" "
export ZONE="us-east4-b"
export PROJECT_ID=" "  
export IAP_SOURCE_RANGE=""
export INTERNAL_SOURCE_RANGE=""

# Start the script
echo "${YELLOW}${BOLD}Starting${RESET}" "${GREEN}${BOLD}Execution${RESET}"

# Delete overly permissive firewall rules
gcloud compute firewall-rules delete open-access --quiet

# Start the bastion host
gcloud compute instances start bastion \
    --project=$PROJECT_ID \
    --zone=$ZONE

# Create a firewall rule for SSH ingress via IAP
gcloud compute firewall-rules create ssh-ingress \
    --allow=tcp:22 \
    --source-ranges=$IAP_SOURCE_RANGE \
    --target-tags=$IAP_NET_TAG \
    --network=acme-vpc

# Add the IAP network tag to the bastion instance
gcloud compute instances add-tags bastion \
    --tags=$IAP_NET_TAG \
    --zone=$ZONE

# Create a firewall rule for HTTP ingress to juice-shop
gcloud compute firewall-rules create http-ingress \
    --allow=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=$HTTP_NET_TAG \
    --network=acme-vpc

# Add the HTTP network tag to the juice-shop instance
gcloud compute instances add-tags juice-shop \
    --tags=$HTTP_NET_TAG \
    --zone=$ZONE

# Create a firewall rule for internal SSH ingress from acme-mgmt-subnet
gcloud compute firewall-rules create internal-ssh-ingress \
    --allow=tcp:22 \
    --source-ranges=$INTERNAL_SOURCE_RANGE \
    --target-tags=$INT_NET_TAG \
    --network=acme-vpc

# Add the internal SSH network tag to the juice-shop instance
gcloud compute instances add-tags juice-shop \
    --tags=$INT_NET_TAG \
    --zone=$ZONE

# Sleep for 30 seconds to ensure everything is set up
sleep 30

# Prepare a script to connect from bastion to juice-shop
cat > prepare_disk.sh <<'EOF_END'

export ZONE=$(gcloud compute instances list juice-shop --format 'csv[no-heading](zone)')

gcloud compute ssh juice-shop --internal-ip --zone=$ZONE --quiet

EOF_END

# Copy the script to bastion
gcloud compute scp prepare_disk.sh bastion:/tmp \
    --project=$PROJECT_ID \
    --zone=$ZONE \
    --quiet

# SSH into bastion and execute the prepare_disk.sh script
gcloud compute ssh bastion \
    --project=$PROJECT_ID \
    --zone=$ZONE \
    --quiet --command="bash /tmp/prepare_disk.sh"

# End of script
echo "${RED}${BOLD}Congratulations${RESET}" "${WHITE}${BOLD}for${RESET}" "${GREEN}${BOLD}Completing the Lab !!!${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#


#RUn this portion of the code differently

gcloud compute ssh bastion \
    --project=<your_project_id> \
    --zone=us-east4-b \
    --tunnel-through-iap

#TO get internal IP for SSH

gcloud compute instances describe juice-shop \
    --project=<your_project_id> \
    --zone=us-east4-b \
    --format='get(networkInterfaces[0].networkIP)'

# SSH into juiceshop
ssh <internal_ip>

###########################
# Setup
###########################
# Documentation
# https://github.com/vmware-tanzu/velero-plugin-for-microsoft-azure
# https://velero.io/docs/v1.1.0/azure-config/

# Install "client" velero on Ubuntu or WSL
wget https://github.com/vmware-tanzu/velero/releases/download/v1.3.2/velero-v1.3.2-linux-amd64.tar.gz
tar -xvf velero-v1.3.2-linux-amd64.tar.gz
cp velero /usr/bin/velero
chmod a+x /usr/bin/velero

#Install Azure tools
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash 

# Connect to the Tenant/Sub
az login

#Define the new AKS cluster name, this will be used to set all the variables below
# ClusterName must be in LOWER case, maybe with number but without special character
ClusterName=yournewaksclustername
ClusterResourceGroup=$ClusterName
ClusterLocation=westeurope
BLOB_CONTAINER=$ClusterName
AZURE_BACKUP_RESOURCE_GROUP=Velero_Backups_$ClusterName
AZURE_STORAGE_ACCOUNT_ID=$ClusterName 

#Create AKS resource group and cluster
az group create --name $ClusterResourceGroup --location $ClusterLocation
az aks create --resource-group $ClusterResourceGroup --name $ClusterName --node-count 1 --enable-addons monitoring --generate-ssh-keys

###########################
# Install Velero
###########################
#Connect to the AKS CLuster
az aks get-credentials --resource-group $ClusterResourceGroup --name $ClusterName

# Resource Group, specify a new resource group name for backup location and a new storage account name
az group create -n $AZURE_BACKUP_RESOURCE_GROUP --location $ClusterLocation

# Create the storage account in the resource group
az storage account create \
    --name $AZURE_STORAGE_ACCOUNT_ID \
    --resource-group $AZURE_BACKUP_RESOURCE_GROUP \
    --sku Standard_GRS \
    --encryption-services blob \
    --https-only true \
    --kind BlobStorage \
    --access-tier Hot

# Create the Blob --> Error with the below AZ command since an Azure update in 2020, create manually via the portal, see explaination below
#az storage container create -n $BLOB_CONTAINER --public-access off --account-name $AZURE_STORAGE_ACCOUNT_ID
## Manually create the Blob --> Go to the portal --> storage account $ClusterName  -> Blob Service -> Containers -> +Container $BLOB_CONTAINER Private access level

#Get the MC_xyz resource group that correspond to the AKS cluster
az group list --query '[].{ ResourceGroup: name, Location:location }' | grep -i MC_$ClusterName
#Specify the resource group MC_xyz_xyz_location that you get with the previous command
AZURE_RESOURCE_GROUP=MC_xyz_xyz_location
AZURE_SUBSCRIPTION_ID=`az account list --query '[?isDefault].id' -o tsv`
AZURE_TENANT_ID=`az account list --query '[?isDefault].tenantId' -o tsv`
AZURE_CLIENT_ID=`az ad sp list --display-name velero --query '[0].appId' -o tsv`
# Warning : this command will create a new rbac with the name --name
AZURE_CLIENT_SECRET=`az ad sp create-for-rbac --name velero --role "Contributor" --query 'password' -o tsv`

#Create credential file
cat << EOF  > ./credentials-velero
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID}
AZURE_TENANT_ID=${AZURE_TENANT_ID}
AZURE_CLIENT_ID=${AZURE_CLIENT_ID}
AZURE_CLIENT_SECRET=${AZURE_CLIENT_SECRET}
AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}
EOF

# Dry-run
velero install \
    --provider azure \
    --plugins velero/velero-plugin-for-microsoft-azure:v1.1.1 \
    --bucket $BLOB_CONTAINER \
    --secret-file ./credentials-velero \
    --backup-location-config resourceGroup=$AZURE_BACKUP_RESOURCE_GROUP,storageAccount=$AZURE_STORAGE_ACCOUNT_ID \
    --snapshot-location-config apiTimeout=5m \
    --use-restic \
    --dry-run -o yaml

# Create deployment and restic StateFulSet
velero install \
    --provider azure \
    --plugins velero/velero-plugin-for-microsoft-azure:v1.1.1 \
    --bucket $BLOB_CONTAINER \
    --secret-file ./credentials-velero \
    --backup-location-config resourceGroup=$AZURE_BACKUP_RESOURCE_GROUP,storageAccount=$AZURE_STORAGE_ACCOUNT_ID \
    --snapshot-location-config apiTimeout=5m \
    --use-restic

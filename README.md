We need to automate the deployment of cluster in Azure to host some workloads. Sadly, these workloads are not stateless and we need to backup them....
We have some experience with velero backup to AWS S3 buckets, so let try to use it with an Azure AKS cluster and Blob.

You will fin all the command and code in this repo :  [https://github.com/cisel-dev/aks-velero-demo](Link) 

Azure cli and Velero client are needed, here an example on how to install them on Ubuntu (or WSL)

```
# Install "client" velero on Ubuntu or WSL
wget https://github.com/vmware-tanzu/velero/releases/download/v1.3.2/velero-v1.3.2-linux-amd64.tar.gz
tar -xvf velero-v1.3.2-linux-amd64.tar.gz
cp velero /usr/bin/velero
chmod a+x /usr/bin/velero

#Install Azure tools
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash 
```

Create an AKS cluster with a single node
```
# Connect to the Tenant/Sub
az login

# Define the new AKS cluster name, this will be used to set all the variables below
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
```
Wait a little, to give the cluster time to be available.
We will now setup the prerequisites before the deployment of Velero in the cluster
```
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
```
Manually create the Blob in Azure
```
# Create the Blob --> Error with the below AZ command since an Azure update in 2020, create manually via the portal, see explaination below
#az storage container create -n $BLOB_CONTAINER --public-access off --account-name $AZURE_STORAGE_ACCOUNT_ID
Manually create the Blob --> Go to the portal --> storage account $ClusterName  -> Blob Service -> Containers -> +Container $BLOB_CONTAINER Private access level
```
Create the credentials for Velero to access the storage on Azure
```
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
```

Now we have all that we need to deploy Velero in the AKS cluster
I advise you to first make a dry-run to test if the configuration is good.
```
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
```

If you are satisfied with the status of the dry-run, you can now deploy Velero
```

# Create deployment and restic StateFulSet
velero install \
    --provider azure \
    --plugins velero/velero-plugin-for-microsoft-azure:v1.1.1 \
    --bucket $BLOB_CONTAINER \
    --secret-file ./credentials-velero \
    --backup-location-config resourceGroup=$AZURE_BACKUP_RESOURCE_GROUP,storageAccount=$AZURE_STORAGE_ACCOUNT_ID \
    --snapshot-location-config apiTimeout=5m \
    --use-restic
```

Test that velero can access the Blob
```
velero get backup
```

Do a very simple backup and restore test.

We deploy a statefulset with a PVC
```
kubectl apply -f https://raw.githubusercontent.com/cisel-dev/aks-velero-demo/main/nginx-sf.yaml
````

Annotate the pod with the volume that we want to backup
```
# Annotations
kubectl -n demo01 annotate pod/web-0 backup.velero.io/backup-volumes=www
```

Let's create some data in our pod volume
```
# Create Data
kubectl -n demo01 exec -it web-0 /bin/bash
echo TEST1 > /usr/share/nginx/html/test1
echo TEST2 > /usr/share/nginx/html/test2
```
Create a backup of the namespace demo01
```
velero backup create demo01-backup01 --include-namespaces demo01
velero backup describe demo01-backup01 --details
velero get backup
```

Delete the namespace demo01
```
kubectl delete ns demo01
```

Restore from the previous backup
```
velero restore create --from-backup demo01-backup01
```

Check if the data of the PV are restored
```
kubectl exec -it web-0 /bin/bash
cat /usr/share/nginx/html/test3
cat /usr/share/nginx/html/test4
```

If everything is working on your side, you can now imagin to use velero to backup your critical data to Azure Blob!


#### Documentation
 [https://github.com/vmware-tanzu/velero-plugin-for-microsoft-azure](Link) 
 [https://velero.io/docs/v1.1.0/azure-config/](Link) 

Feel free to contact us directly if you have any question at cloud@cisel.ch
[https://www.cisel.ch](Link) 

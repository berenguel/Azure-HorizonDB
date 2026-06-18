// Azure HorizonDB intro demo - single cluster.
// Preview resource provider Microsoft.HorizonDb, API 2026-01-20-preview.
// Compile to ARM JSON with:  az bicep build --file infra/main.bicep --outfile infra/azuredeploy.json

@minLength(3)
@maxLength(63)
@description('Cluster name. Lowercase letters, numbers and hyphens only.')
param clusterName string = 'horizon-${uniqueString(resourceGroup().id)}'

@minLength(1)
@maxLength(63)
@description('Admin login name.')
param administratorLogin string = 'pgadmin'

@minLength(8)
@maxLength(128)
@secure()
@description('Admin password (8-128 chars).')
param administratorLoginPassword string

@minValue(1)
@maxValue(96)
@description('vCores per compute replica.')
param vCores int = 2

@description('PostgreSQL major version.')
param pgVersion string = '17'

@minValue(1)
@description('Number of replicas. Use at least 2 for zonal resilience and to enable the reader endpoint + failover parts of the demo.')
param replicaCount int = 2

@allowed([ 'BestEffort', 'Strict' ])
@description('How replicas are placed across availability zones.')
param zonePlacementPolicy string = 'Strict'

resource cluster 'Microsoft.HorizonDb/clusters@2026-01-20-preview' = {
  name: clusterName
  location: resourceGroup().location
  properties: {
    createMode: 'Create'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    vCores: vCores
    version: pgVersion
    replicaCount: replicaCount
    zonePlacementPolicy: zonePlacementPolicy
  }
}

output clusterName string = cluster.name
output clusterResourceId string = cluster.id
output nextStep string = 'Copy the read/write and reader endpoints from the portal Overview / Replicas page into .env, then run scripts/02-load-data.sh'

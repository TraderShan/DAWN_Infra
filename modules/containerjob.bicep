// Reusable Azure Container Apps Job. Used for:
//   - the overnight batch (scheduled, ~5am) that detects signals, ranks, composes the
//     brief, and writes artifacts to Cosmos;
//   - one-off / manual data jobs (seed stubs, load OneLake, index AI Search).
// Jobs run in the same internal environment, so they reach the private data tier over
// the VNet with the shared managed identity.

param location string
param tags object
param name string
param environmentId string
param uamiId string
param acrLoginServer string
param image string
param appInsightsConnectionString string

@description('Job trigger: Schedule (cron) or Manual (run on demand / from CI).')
@allowed([
  'Schedule'
  'Manual'
])
param triggerType string = 'Manual'

@description('Cron expression (UTC) for scheduled jobs. Default 09:00 UTC ~= 5am US Eastern (DST-dependent).')
param cronExpression string = '0 9 * * *'

@description('Max time (seconds) a replica may run before it is terminated.')
param replicaTimeout int = 3600

param cpu string = '0.5'
param memory string = '1Gi'
param extraEnv array = []

var baseEnv = [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
]

var scheduleConfig = triggerType == 'Schedule' ? {
  scheduleTriggerConfig: {
    cronExpression: cronExpression
    parallelism: 1
    replicaCompletionCount: 1
  }
} : {
  manualTriggerConfig: {
    parallelism: 1
    replicaCompletionCount: 1
  }
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: union({
      triggerType: triggerType
      replicaTimeout: replicaTimeout
      replicaRetryLimit: 1
      registries: [
        {
          server: acrLoginServer
          identity: uamiId
        }
      ]
    }, scheduleConfig)
    template: {
      containers: [
        {
          name: name
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: concat(baseEnv, extraEnv)
        }
      ]
    }
  }
}

output id string = job.id
output name string = job.name

// @ts-check

const local = process.env.NODE_ENV === 'production' ? 'prod' : 'local'

/** @type {import('../src/types.ts').DatabaseQueryConfig} */
export default {
  defaults: {
    defaultInstance: 'local-postgres',
    limit: 50,
    maxLimit: 1000,
    permissionLevel: 'readonly',
    outputFormat: 'text',
    redactFields: ['password', 'uri', 'url', 'token'],
    allowedActions: {
      postgres: ['sql'],
      mysql: ['sql'],
      sqlite: ['sql'],
      mongodb: ['list-collections', 'count', 'find'],
      redis: ['ping', 'info', 'scan', 'type', 'ttl', 'get', 'hget', 'lrange'],
      milvus: ['list-collections', 'describe-collection', 'query', 'search'],
    },
  },
  instances: [
    {
      id: 'local-postgres',
      type: 'postgres',
      environment: local,
      host: 'localhost',
      port: 5432,
      username: process.env.DB_LOCAL_POSTGRES_USER,
      password: process.env.DB_LOCAL_POSTGRES_PASSWORD,
      defaultDatabase: 'app',
      readonly: true,
      databases: [
        {
          name: 'app',
          schemas: ['public'],
          defaultSchema: 'public',
        },
      ],
    },
    {
      id: 'local-mongo',
      type: 'mongodb',
      environment: local,
      uri: `mongodb://${process.env.DB_LOCAL_MONGO_USER}:${process.env.DB_LOCAL_MONGO_PASSWORD}@localhost:27017`,
      defaultDatabase: 'app',
      readonly: true,
      databases: [
        {
          name: 'app',
          collections: ['users', 'orders'],
          defaultCollection: 'users',
        },
      ],
    },
  ],
}

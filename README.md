# go-migrate-action

A custom GitHub Action to build and run a Docker container for Go migrations in a Private
Cloud SQL GCP environment. It utilizes a provided GCP VM machine as a bastion, middleman, instance,
to connect to a Private IP Cloud SQL instance and execute database migrations.

**Note**: The bastion VM must be running Google Cloud Proxy script to connect to the Cloud SQL instance.
The documentation on Cloud SQL Proxy is [here](https://cloud.google.com/sql/docs/mysql/sql-proxy#install).

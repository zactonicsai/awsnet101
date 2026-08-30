# AWS RDS PostgreSQL Keycloak Snapshot Restore Tutorial

## Safely Create a New Keycloak Database from an Existing RDS Snapshot

This tutorial explains how to make a **new copy of a Keycloak PostgreSQL database** using an Amazon RDS snapshot.

The goal is:

```text
Original Keycloak RDS
        |
        | Create Snapshot
        v
RDS Snapshot
        |
        | Restore
        v
New RDS PostgreSQL Instance
        |
        | Rename database
        v
New Keycloak Test Database
```

The original database stays in place.

For example:

```text
ORIGINAL

RDS Instance:
keycloak-prod

Database:
keycloak


              SNAPSHOT
                  |
                  v


NEW COPY

RDS Instance:
keycloak-test-copy

Database:
keycloak_test
```

The important idea is:

> We copy the database. We do not rename, delete, or modify the original database.

Amazon RDS restores a snapshot into a **new DB instance**. It cannot restore the snapshot over an existing DB instance. An RDS snapshot also represents the entire DB instance storage, not just one PostgreSQL database inside it.

---

# 1. What We Are Building

Assume the current Keycloak system looks like this:

```text
Keycloak Production
        |
        v
postgres-dev.xxxxx.us-east-1.rds.amazonaws.com
        |
        v
PostgreSQL
        |
        +-- keycloak
```

We want:

```text
                    +----------------------+
                    | Production Keycloak  |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    | Original RDS         |
                    | keycloak-prod        |
                    | DB = keycloak        |
                    +----------+-----------+
                               |
                            Snapshot
                               |
                               v
                    +----------------------+
                    | RDS Snapshot         |
                    +----------+-----------+
                               |
                            Restore
                               |
                               v
                    +----------------------+
                    | NEW RDS              |
                    | keycloak-test-copy   |
                    | DB = keycloak        |
                    +----------+-----------+
                               |
                          Rename DB
                               |
                               v
                    +----------------------+
                    | NEW RDS              |
                    | keycloak-test-copy   |
                    | DB = keycloak_test   |
                    +----------------------+
```

At the end:

```text
Production:
keycloak-prod
└── keycloak

Test Copy:
keycloak-test-copy
└── keycloak_test
```

They are now separate RDS systems.

Changes made to:

```text
keycloak_test
```

will not change:

```text
keycloak
```

on the original RDS instance.

---

# 2. Why This Is Safer

A Keycloak database contains important information such as:

* realms
* users
* groups
* roles
* clients
* client configuration
* identity provider configuration
* authentication flows
* credentials
* client secrets
* realm settings
* some session-related information
* configuration used by Keycloak

Because of this, treat a Keycloak database snapshot like a sensitive backup.

Do not casually:

```text
copy it
email it
make it public
share it
upload it to an unsecured system
```

AWS encryption at rest can cover the DB storage, logs, backups, and snapshots for an encrypted RDS instance.

---

# 3. Very Important Safety Rule

## Never point your test Keycloak at the production database.

Bad:

```text
Test Keycloak
      |
      v
Production RDS
```

Better:

```text
Production Keycloak
      |
      v
Production RDS


Test Keycloak
      |
      v
Restored Test RDS
```

This gives you isolation.

If something goes wrong with the test system, production remains separate.

---

# 4. Example Names Used in This Tutorial

We will use these example names.

| Item                  | Name                          |
| --------------------- | ----------------------------- |
| Original RDS instance | `keycloak-prod`               |
| Original database     | `keycloak`                    |
| Snapshot              | `keycloak-prod-safe-20260830` |
| New RDS instance      | `keycloak-test-copy`          |
| New database          | `keycloak_test`               |
| PostgreSQL port       | `5432`                        |
| AWS Region            | `us-east-1`                   |

Your names may be different.

Replace the examples with your actual values.

---

# 5. Tools Needed

You should have:

```text
AWS CLI
Terraform
psql
AWS credentials
Network access to RDS
```

Check AWS CLI:

```bash
aws --version
```

Check Terraform:

```bash
terraform version
```

Check PostgreSQL client:

```bash
psql --version
```

You should also confirm your AWS login:

```bash
aws sts get-caller-identity
```

Example:

```json
{
  "UserId": "...",
  "Account": "123456789012",
  "Arn": "arn:aws:iam::123456789012:user/example"
}
```

This is important.

You do not want to accidentally create the copy in the wrong AWS account.

---

# 6. Step 1 — Find the Original Keycloak RDS

Before doing anything, inspect the existing RDS instance.

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-prod
```

For a shorter view:

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-prod \
  --query "DBInstances[0].[DBInstanceIdentifier,Engine,EngineVersion,DBInstanceStatus,Endpoint.Address,DBSubnetGroup.DBSubnetGroupName,VpcSecurityGroups[*].VpcSecurityGroupId]" \
  --output json
```

You want to verify:

```text
RDS name
PostgreSQL version
Status
Endpoint
Subnet group
Security groups
```

The database should normally show:

```text
available
```

AWS requires an RDS DB instance to be in an appropriate available state before a manual snapshot can be created.

---

# 7. Step 2 — Record the Production Configuration

Before making the copy, save important information.

Run:

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-prod \
  --output json > keycloak-prod-before-restore.json
```

This gives you a record.

Think of this like taking a picture of the system before changing anything.

Keep track of:

```text
DB instance identifier
Engine
Engine version
Subnet group
Security groups
Parameter group
Storage
Encryption
KMS key
Public/private setting
Master username
Endpoint
```

You can inspect the master username:

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-prod \
  --query "DBInstances[0].MasterUsername" \
  --output text
```

Example:

```text
rcsuper
```

---

# 8. Step 3 — Find the Actual Keycloak Database Name

Do not guess.

Connect to PostgreSQL.

Example:

```bash
PGSSLMODE=require psql \
  -h ORIGINAL-RDS-ENDPOINT \
  -p 5432 \
  -U rcsuper \
  -d postgres
```

List databases:

```sql
\l
```

You might see:

```text
postgres
keycloak
rdsadmin
template0
template1
```

Your Keycloak database might be:

```text
keycloak
```

or:

```text
appdb
```

or another name.

Record the real value.

For this tutorial:

```text
OLD DATABASE = keycloak
NEW DATABASE = keycloak_test
```

---

# 9. Step 4 — Verify Keycloak Is Actually Using That Database

Look at your Keycloak configuration.

Modern Keycloak supports PostgreSQL and allows the database settings to be supplied with options such as:

```text
db
db-url
db-url-host
db-url-database
db-username
db-password
```

The current Keycloak documentation lists PostgreSQL 18 among its supported PostgreSQL versions.

For Docker, you might have:

```yaml
environment:
  KC_DB: postgres
  KC_DB_URL_HOST: postgres-dev.example.us-east-1.rds.amazonaws.com
  KC_DB_URL_PORT: 5432
  KC_DB_URL_DATABASE: keycloak
  KC_DB_USERNAME: keycloak
  KC_DB_PASSWORD: secret
```

Or perhaps:

```yaml
environment:
  KC_DB: postgres
  KC_DB_URL: jdbc:postgresql://postgres-dev.example.us-east-1.rds.amazonaws.com:5432/keycloak
  KC_DB_USERNAME: keycloak
  KC_DB_PASSWORD: secret
```

Write down:

```text
Host
Port
Database
Username
SSL settings
```

---

# 10. Step 5 — Decide Whether You Need to Stop Production Keycloak

For many snapshot operations, PostgreSQL and RDS can handle a running transactional database.

However, if you need an exact and easily understood copy at a known point in time, a safer maintenance procedure is:

```text
1. Stop users from making changes.
2. Stop or scale down Keycloak.
3. Take the snapshot.
4. Wait for snapshot completion.
5. Start production Keycloak again.
```

This is especially useful before:

```text
major upgrades
migration testing
schema testing
disaster recovery tests
Keycloak version upgrades
```

For Kubernetes you might temporarily scale down:

```bash
kubectl scale deployment keycloak --replicas=0 -n keycloak
```

Verify:

```bash
kubectl get pods -n keycloak
```

For Docker Compose:

```bash
docker compose stop keycloak
```

Do **not** stop the RDS database itself.

You are only trying to stop application writes for a clean testing checkpoint.

---

# 11. Step 6 — Create a Manual RDS Snapshot

Create the snapshot:

```bash
aws rds create-db-snapshot \
  --db-instance-identifier keycloak-prod \
  --db-snapshot-identifier keycloak-prod-safe-20260830
```

AWS's documented CLI command for a manual RDS snapshot uses the source DB instance identifier and a new snapshot identifier.

Check it:

```bash
aws rds describe-db-snapshots \
  --db-snapshot-identifier keycloak-prod-safe-20260830
```

You will initially see something like:

```text
creating
```

---

# 12. Step 7 — Wait Until the Snapshot Is Ready

Do not restore from it until AWS says:

```text
available
```

Use the AWS waiter:

```bash
aws rds wait db-snapshot-available \
  --db-snapshot-identifier keycloak-prod-safe-20260830
```

The AWS CLI provides this waiter specifically to poll until the RDS snapshot becomes available.

Then verify:

```bash
aws rds describe-db-snapshots \
  --db-snapshot-identifier keycloak-prod-safe-20260830 \
  --query "DBSnapshots[0].[DBSnapshotIdentifier,Status,Engine,EngineVersion,Encrypted]" \
  --output table
```

Example:

```text
------------------------------------------------
|             DescribeDBSnapshots              |
+----------------------------------------------+
| keycloak-prod-safe-20260830                  |
| available                                    |
| postgres                                     |
| 18.x                                         |
| True                                         |
+----------------------------------------------+
```

---

# 13. Step 8 — Restart Production Keycloak

If you stopped production Keycloak, restart it now.

Kubernetes:

```bash
kubectl scale deployment keycloak --replicas=2 -n keycloak
```

Then:

```bash
kubectl get pods -n keycloak
```

Docker Compose:

```bash
docker compose start keycloak
```

Verify production is healthy before continuing.

At this point:

```text
Production Keycloak = running

Production RDS = unchanged

Snapshot = safely created
```

---

# 14. Step 9 — Understand What Restore Does

This is very important.

RDS does **not** take the snapshot and overwrite your production database.

Instead:

```text
Snapshot
   |
   v
NEW RDS Instance
```

AWS documentation states that restoring a DB snapshot creates a new DB instance; a snapshot cannot simply be restored into an already-existing DB instance.

For example:

```text
Original:

keycloak-prod
```

remains:

```text
keycloak-prod
```

The restored system becomes:

```text
keycloak-test-copy
```

---

# 15. Step 10 — Restore the Snapshot with AWS CLI

A basic restore looks like:

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier keycloak-test-copy \
  --db-snapshot-identifier keycloak-prod-safe-20260830 \
  --db-instance-class db.t3.micro
```

AWS documents `restore-db-instance-from-db-snapshot` for creating the new RDS instance.

However, for a real Keycloak environment, I recommend explicitly selecting the networking.

Example:

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier keycloak-test-copy \
  --db-snapshot-identifier keycloak-prod-safe-20260830 \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name zpostgres-subnet-group \
  --vpc-security-group-ids sg-0123456789abcdef0 \
  --publicly-accessible
```

For an internal production-style environment, use:

```bash
--no-publicly-accessible
```

instead.

---

# 16. Important — Do Not Try to Change the Internal PostgreSQL Database Name During Restore

This is a common misunderstanding.

These are two different things:

```text
RDS INSTANCE NAME
```

and:

```text
POSTGRESQL DATABASE NAME
```

For example:

```text
RDS instance:
keycloak-test-copy

PostgreSQL database:
keycloak
```

During snapshot restore, AWS lets us change the new RDS **instance identifier**.

For example:

```text
keycloak-prod
```

becomes:

```text
keycloak-test-copy
```

But the contents of the snapshot are restored as they existed.

So inside the new copy you initially still have:

```text
keycloak
```

We rename that database later using PostgreSQL.

---

# 17. Terraform Version

Here is a simple one-file Terraform configuration.

Create:

```text
main.tf
```

Use:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}


# ============================================================
# SNAPSHOT TO RESTORE
# ============================================================

variable "snapshot_identifier" {
  description = "Existing Keycloak RDS snapshot"
  type        = string

  default = "keycloak-prod-safe-20260830"
}


# ============================================================
# NEW RDS INSTANCE NAME
#
# This MUST be different from production.
# ============================================================

variable "new_instance_identifier" {
  description = "New restored Keycloak RDS instance"
  type        = string

  default = "keycloak-test-copy"
}


# ============================================================
# EXISTING RDS SUBNET GROUP
# ============================================================

variable "db_subnet_group_name" {
  description = "Subnet group for the restored RDS"
  type        = string

  default = "zpostgres-subnet-group"
}


# ============================================================
# EXISTING SECURITY GROUP
#
# Replace with your real security group ID.
# ============================================================

variable "security_group_ids" {
  description = "Security groups for restored Keycloak RDS"
  type        = list(string)

  default = [
    "sg-0123456789abcdef0"
  ]
}


# ============================================================
# RESTORE NEW RDS FROM SNAPSHOT
# ============================================================

resource "aws_db_instance" "keycloak_copy" {

  # ----------------------------------------------------------
  # NEW RDS INSTANCE NAME
  #
  # This does NOT change production.
  # ----------------------------------------------------------

  identifier = var.new_instance_identifier


  # ----------------------------------------------------------
  # SNAPSHOT
  # ----------------------------------------------------------

  snapshot_identifier = var.snapshot_identifier


  # ----------------------------------------------------------
  # SMALL DEV / TEST INSTANCE
  # ----------------------------------------------------------

  instance_class = "db.t3.micro"


  # ----------------------------------------------------------
  # NETWORK
  # ----------------------------------------------------------

  db_subnet_group_name = var.db_subnet_group_name

  vpc_security_group_ids = var.security_group_ids


  # ----------------------------------------------------------
  # PUBLIC ACCESS
  #
  # DEV ONLY.
  #
  # For normal corporate environments use false.
  # ----------------------------------------------------------

  publicly_accessible = true


  # ----------------------------------------------------------
  # DEVELOPMENT COPY SETTINGS
  # ----------------------------------------------------------

  multi_az = false

  deletion_protection = false

  skip_final_snapshot = true

  apply_immediately = true


  tags = {
    Name        = "keycloak-test-copy"
    Environment = "test"
    Application = "keycloak"
    Source      = "snapshot"
  }
}


# ============================================================
# OUTPUT NEW ENDPOINT
# ============================================================

output "new_keycloak_database_host" {
  description = "New RDS endpoint"

  value = aws_db_instance.keycloak_copy.address
}


output "new_keycloak_database_port" {
  value = aws_db_instance.keycloak_copy.port
}


output "new_rds_instance_identifier" {
  value = aws_db_instance.keycloak_copy.identifier
}
```

---

# 18. Notice What Is NOT in the Terraform Restore

We deliberately do not have:

```hcl
db_name = "keycloak_test"
```

and we do not try to create a brand-new master identity during snapshot restoration.

The snapshot already contains the database state.

Think of the snapshot like a photocopy:

```text
Original database:

keycloak
```

Snapshot restores:

```text
keycloak
```

We rename it afterward.

---

# 19. Run Terraform

Initialize:

```bash
terraform init
```

Format:

```bash
terraform fmt
```

Validate:

```bash
terraform validate
```

Plan:

```bash
terraform plan
```

STOP HERE AND READ THE PLAN.

Make sure Terraform says it is creating:

```text
keycloak-test-copy
```

and **not deleting or replacing**:

```text
keycloak-prod
```

Then apply:

```bash
terraform apply
```

Enter:

```text
yes
```

---

# 20. Step 11 — Wait for the New RDS Instance

Check:

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-test-copy \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text
```

At first:

```text
creating
```

Eventually:

```text
available
```

Or use:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier keycloak-test-copy
```

---

# 21. Step 12 — Get the NEW Endpoint

Terraform:

```bash
terraform output new_keycloak_database_host
```

Or AWS CLI:

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-test-copy \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

Example:

```text
keycloak-test-copy.abc123.us-east-1.rds.amazonaws.com
```

This is important.

You should now have TWO different endpoints.

Example:

```text
PRODUCTION

keycloak-prod.aaa111.us-east-1.rds.amazonaws.com


TEST

keycloak-test-copy.bbb222.us-east-1.rds.amazonaws.com
```

Write both down.

Do not mix them up.

---

# 22. Step 13 — Put Big Labels on the Systems

A useful operational habit is to create a table.

| Environment | RDS                                      | Database        |
| ----------- | ---------------------------------------- | --------------- |
| PROD        | `keycloak-prod...rds.amazonaws.com`      | `keycloak`      |
| TEST        | `keycloak-test-copy...rds.amazonaws.com` | `keycloak_test` |

Before typing a destructive SQL command, look at this table.

---

# 23. Step 14 — Verify the NEW RDS Before Renaming Anything

Connect only to the new server.

```bash
PGSSLMODE=require psql \
  -h keycloak-test-copy.abc123.us-east-1.rds.amazonaws.com \
  -p 5432 \
  -U rcsuper \
  -d postgres
```

Then immediately ask PostgreSQL:

```sql
SELECT inet_server_addr();
```

And:

```sql
SELECT current_database();
```

And:

```sql
SELECT current_user;
```

List databases:

```sql
\l
```

You should see:

```text
keycloak
postgres
template0
template1
...
```

---

# 24. Extra Safety Check

Before renaming anything, run:

```sql
SELECT
    current_database(),
    current_user,
    inet_server_addr(),
    inet_server_port();
```

Make absolutely sure you are on:

```text
keycloak-test-copy
```

and **not** production.

---

# 25. Step 15 — Verify the Keycloak Data Exists

Connect to the copied database:

```bash
PGSSLMODE=require psql \
  -h keycloak-test-copy.abc123.us-east-1.rds.amazonaws.com \
  -p 5432 \
  -U rcsuper \
  -d keycloak
```

List tables:

```sql
\dt
```

You should see many Keycloak tables.

For example:

```text
realm
user_entity
client
role_attribute
credential
user_role_mapping
```

Check realms:

```sql
SELECT id, name
FROM realm
ORDER BY name;
```

You might see:

```text
master
myrealm
VIP
```

Check a few counts:

```sql
SELECT COUNT(*)
FROM realm;
```

```sql
SELECT COUNT(*)
FROM user_entity;
```

```sql
SELECT COUNT(*)
FROM client;
```

Do not update anything yet.

We are only checking.

---

# 26. Step 16 — Check Who Owns the Database

Before renaming it:

```sql
SELECT
    datname,
    pg_catalog.pg_get_userbyid(datdba) AS owner
FROM pg_database
WHERE datname = 'keycloak';
```

Example:

```text
 datname  | owner
----------+----------
 keycloak | rcsuper
```

or perhaps:

```text
keycloak | keycloak
```

The database owner normally needs sufficient privileges to rename the database.

---

# 27. Step 17 — Disconnect from `keycloak`

You cannot safely rename the database while connected to that same database.

Exit:

```sql
\q
```

Reconnect to:

```text
postgres
```

not:

```text
keycloak
```

Command:

```bash
PGSSLMODE=require psql \
  -h keycloak-test-copy.abc123.us-east-1.rds.amazonaws.com \
  -p 5432 \
  -U rcsuper \
  -d postgres
```

---

# 28. Step 18 — Make Sure Keycloak Is NOT Connected to the New Copy

This is another major safety rule.

Do **not** start the cloned Keycloak yet.

Check database connections:

```sql
SELECT
    pid,
    datname,
    usename,
    client_addr,
    application_name
FROM pg_stat_activity
WHERE datname = 'keycloak';
```

Ideally there should be no Keycloak application connected.

---

# 29. Step 19 — Terminate Any Connections to the Copied Database

On the **NEW RDS only**:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'keycloak'
  AND pid <> pg_backend_pid();
```

Again:

> Make absolutely sure this is the test RDS endpoint.

---

# 30. Step 20 — Rename the Copied Database

Now run:

```sql
ALTER DATABASE keycloak
RENAME TO keycloak_test;
```

PostgreSQL officially supports database renaming with:

```text
ALTER DATABASE old_name RENAME TO new_name
```

and database-level changes require appropriate ownership or privileges.

---

# 31. Step 21 — Verify the Rename

Run:

```sql
\l
```

You should now see:

```text
keycloak_test
```

and no longer:

```text
keycloak
```

on this restored copy.

Remember:

Production still has:

```text
keycloak
```

Test now has:

```text
keycloak_test
```

---

# 32. Step 22 — Test Connecting to the New Database

Exit:

```sql
\q
```

Then:

```bash
PGSSLMODE=require psql \
  -h keycloak-test-copy.abc123.us-east-1.rds.amazonaws.com \
  -p 5432 \
  -U rcsuper \
  -d keycloak_test
```

Test:

```sql
SELECT current_database();
```

Expected:

```text
keycloak_test
```

Check realms again:

```sql
SELECT id, name
FROM realm
ORDER BY name;
```

---

# 33. Step 23 — Test Important Keycloak Tables

Examples:

```sql
SELECT COUNT(*) AS realms
FROM realm;
```

```sql
SELECT COUNT(*) AS users
FROM user_entity;
```

```sql
SELECT COUNT(*) AS clients
FROM client;
```

You can compare these counts with production.

For example:

```text
PRODUCTION

realms = 4
users  = 1250
clients = 31


RESTORED COPY

realms = 4
users  = 1250
clients = 31
```

The counts do not have to be your only verification, but they are a simple sanity check.

---

# 34. Step 24 — Create a Different Database Password if Desired

A snapshot restore may retain database credentials from the source snapshot.

For a long-lived test environment, it is better to give the test environment different secrets.

For the RDS master password, you can modify the new RDS instance:

```bash
aws rds modify-db-instance \
  --db-instance-identifier keycloak-test-copy \
  --master-user-password 'NEW-TEST-PASSWORD-HERE' \
  --apply-immediately
```

Do this only to:

```text
keycloak-test-copy
```

Never accidentally run it against:

```text
keycloak-prod
```

---

# 35. Keycloak Usually Should Have Its Own Database User

A better design is:

```text
RDS master user
     |
     | DBA work
     v

Database


Keycloak application user
     |
     | Application access
     v

keycloak_test
```

For example:

```text
Master:
rcsuper

Application:
keycloak_app
```

Keycloak should generally not run using your RDS master account.

---

# 36. Step 25 — Configure the TEST Keycloak

Now change your test Keycloak configuration.

Do NOT copy the production endpoint blindly.

Production might have:

```yaml
KC_DB: postgres
KC_DB_URL_HOST: keycloak-prod.aaa111.us-east-1.rds.amazonaws.com
KC_DB_URL_PORT: 5432
KC_DB_URL_DATABASE: keycloak
KC_DB_USERNAME: keycloak_app
```

Test should use:

```yaml
KC_DB: postgres
KC_DB_URL_HOST: keycloak-test-copy.bbb222.us-east-1.rds.amazonaws.com
KC_DB_URL_PORT: 5432
KC_DB_URL_DATABASE: keycloak_test
KC_DB_USERNAME: keycloak_app
```

Keycloak's database configuration supports separate host, database, username, and password settings.

---

# 37. Full JDBC URL Option

You can instead use:

```yaml
KC_DB: postgres

KC_DB_URL: jdbc:postgresql://keycloak-test-copy.bbb222.us-east-1.rds.amazonaws.com:5432/keycloak_test?sslmode=require

KC_DB_USERNAME: keycloak_app

KC_DB_PASSWORD: CHANGE_ME
```

Important gotcha:

If you set the full:

```text
KC_DB_URL
```

Keycloak uses that JDBC URL, so separate database URL pieces such as the database name configuration are not used in the same way. The Keycloak documentation specifically describes the full JDBC URL as an override for the default connection settings.

---

# 38. Docker Compose Example

A test Keycloak service might look like:

```yaml
services:

  keycloak-test:

    image: quay.io/keycloak/keycloak:latest

    container_name: keycloak-test

    command:
      - start

    environment:

      KC_DB: postgres

      KC_DB_URL: jdbc:postgresql://keycloak-test-copy.bbb222.us-east-1.rds.amazonaws.com:5432/keycloak_test?sslmode=require

      KC_DB_USERNAME: keycloak_app

      KC_DB_PASSWORD: CHANGE_ME

      KC_HOSTNAME: https://keycloak-test.example.com

    ports:

      - "8081:8080"
```

Do not use:

```text
keycloak.company.com
```

for both production and test.

Use something separate:

```text
Production:
keycloak.company.com

Test:
keycloak-test.company.com
```

---

# 39. Kubernetes Example

Example Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-test-db
  namespace: keycloak-test
type: Opaque
stringData:
  username: keycloak_app
  password: CHANGE_ME
```

Example deployment environment:

```yaml
env:

  - name: KC_DB
    value: postgres

  - name: KC_DB_URL
    value: jdbc:postgresql://keycloak-test-copy.bbb222.us-east-1.rds.amazonaws.com:5432/keycloak_test?sslmode=require

  - name: KC_DB_USERNAME
    valueFrom:
      secretKeyRef:
        name: keycloak-test-db
        key: username

  - name: KC_DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: keycloak-test-db
        key: password
```

---

# 40. Very Important Keycloak Clone Safety Checks

A Keycloak database clone can contain production configuration.

Before exposing the cloned Keycloak to users, inspect these areas.

## 40.1 Hostname

Production:

```text
https://login.company.com
```

Test:

```text
https://login-test.company.com
```

Do not let the test clone pretend to be production.

---

# 41. Client Redirect URLs

A copied Keycloak client might contain:

```text
https://production-app.company.com/*
```

For test, you may need:

```text
https://test-app.company.com/*
```

Review Keycloak:

```text
Realm
   |
   +-- Clients
          |
          +-- Valid Redirect URIs
          +-- Web Origins
          +-- Root URL
          +-- Home URL
```

This is extremely important.

---

# 42. Identity Providers

Your copied database may contain settings for:

```text
SAML
OIDC
LDAP
Active Directory
Entra ID
Google
GitHub
other identity providers
```

Do not assume the cloned configuration is safe.

For example:

```text
Test Keycloak
     |
     X
     |
Production LDAP
```

may be something you do **not** want.

Review every external connection.

---

# 43. SMTP / Email

A copied Keycloak realm can contain SMTP settings.

That means a test Keycloak could possibly send messages using production settings.

Before testing password reset or email verification:

```text
CHECK SMTP SETTINGS
```

Prefer:

```text
test SMTP
mail catcher
disabled email
sandbox email system
```

instead of production SMTP.

---

# 44. User Credentials

Remember:

The restored database may contain actual user records and credential-related data.

Treat the test database as sensitive.

Do not:

```text
open port 5432 to the world unless required for a lab
give everyone the database password
put passwords in Git
put passwords directly in Terraform for production
publish the snapshot
```

---

# 45. Network Recommendation

For a quick temporary lab you might use:

```hcl
ingress {
  from_port = 5432
  to_port   = 5432
  protocol  = "tcp"

  cidr_blocks = [
    "0.0.0.0/0"
  ]
}
```

That means:

```text
ANY INTERNET IP
       |
       | TCP 5432
       v
PostgreSQL
```

It is much safer to use:

```hcl
cidr_blocks = [
  "68.32.112.68/32"
]
```

or, better yet, keep the RDS database private:

```hcl
publicly_accessible = false
```

and connect from:

```text
EKS
EC2
VPN
corporate network
SSM host
```

inside the VPC.

---

# 46. Keep SSL Enabled

For RDS PostgreSQL, prefer encrypted database connections.

Use:

```text
sslmode=require
```

Example:

```bash
PGSSLMODE=require psql \
  -h NEW-ENDPOINT \
  -U keycloak_app \
  -d keycloak_test
```

Keycloak's current database documentation also recommends securing PostgreSQL connections using TLS and server certificate verification where practical.

---

# 47. Step 26 — Start the TEST Keycloak

Only after confirming:

```text
New RDS endpoint          ✅
New database name         ✅
Database login            ✅
Test hostname             ✅
Test redirect URLs        ✅
SMTP checked              ✅
Identity providers checked✅
LDAP checked              ✅
Network checked           ✅
Production endpoint absent✅
```

start Keycloak.

Docker:

```bash
docker compose up -d keycloak-test
```

Kubernetes:

```bash
kubectl scale deployment keycloak \
  --replicas=1 \
  -n keycloak-test
```

---

# 48. Step 27 — Watch Keycloak Logs

Docker:

```bash
docker logs -f keycloak-test
```

Kubernetes:

```bash
kubectl logs \
  -f deployment/keycloak \
  -n keycloak-test
```

Look for database errors such as:

```text
password authentication failed
```

```text
database does not exist
```

```text
connection refused
```

```text
SSL error
```

```text
timeout
```

or schema migration problems.

---

# 49. Confirm the Test Keycloak Is Using the Correct Database

From PostgreSQL:

```sql
SELECT
    datname,
    usename,
    client_addr,
    application_name
FROM pg_stat_activity
WHERE datname = 'keycloak_test';
```

You should see Keycloak connections to:

```text
keycloak_test
```

You should NOT see your test Keycloak connected to the production database.

---

# 50. Test Keycloak

Suggested simple tests:

```text
1. Open test Keycloak URL.

2. Log in to the admin console.

3. Verify realms exist.

4. Verify users exist.

5. Verify groups exist.

6. Verify clients exist.

7. Verify roles exist.

8. Test a test-user login.

9. Verify production was not changed.

10. Check Keycloak logs.

11. Check PostgreSQL logs.

12. Check RDS metrics.
```

---

# 51. Compare Production and Test

Production query:

```sql
SELECT COUNT(*) FROM realm;
SELECT COUNT(*) FROM user_entity;
SELECT COUNT(*) FROM client;
```

Test query:

```sql
SELECT COUNT(*) FROM realm;
SELECT COUNT(*) FROM user_entity;
SELECT COUNT(*) FROM client;
```

Make a simple table:

| Check   | Production |  Test |
| ------- | ---------: | ----: |
| Realms  |          4 |     4 |
| Users   |      1,250 | 1,250 |
| Clients |         31 |    31 |

This provides a simple sanity check.

---

# 52. Important PostgreSQL 18 Note

Current Keycloak documentation lists PostgreSQL 18 as a supported PostgreSQL version.

Still, before upgrading Keycloak itself, check the compatibility matrix for the exact:

```text
Keycloak version
PostgreSQL version
JDBC driver
```

you are using.

A database clone like the one in this tutorial is an excellent place to test upgrades safely.

---

# 53. Using This Clone for a Keycloak Upgrade Test

A safe upgrade flow is:

```text
Production Keycloak
        |
        v
Production PostgreSQL
        |
      Snapshot
        |
        v
Test PostgreSQL Copy
        |
        v
Test Keycloak
        |
        v
Upgrade Keycloak
        |
        v
Run Tests
```

This is much safer than first testing a major upgrade directly on production.

---

# 54. Recommended Upgrade Test Checklist

Before starting upgraded Keycloak:

```text
[ ] Snapshot exists

[ ] New RDS exists

[ ] Production RDS still exists

[ ] Test database renamed

[ ] Test endpoint verified

[ ] Test hostname changed

[ ] SMTP checked

[ ] LDAP checked

[ ] SAML providers checked

[ ] OIDC providers checked

[ ] Redirect URLs checked

[ ] Database credentials checked

[ ] Backup retained
```

Then start the new Keycloak version.

---

# 55. Rollback Is Easy

If the test fails:

```text
DO NOT TOUCH PRODUCTION.
```

Simply stop the test Keycloak.

Then fix it or destroy the test RDS.

Production continues using:

```text
keycloak-prod
        |
        v
keycloak
```

---

# 56. Safely Delete the Test RDS

First verify its name:

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-test-copy \
  --query "DBInstances[0].[DBInstanceIdentifier,Endpoint.Address]" \
  --output table
```

Make sure it says:

```text
keycloak-test-copy
```

NOT:

```text
keycloak-prod
```

For a throwaway test copy:

```bash
aws rds delete-db-instance \
  --db-instance-identifier keycloak-test-copy \
  --skip-final-snapshot
```

For an important test system, take another final snapshot instead of skipping it.

---

# 57. Terraform Destroy

If the restored RDS is controlled by its own Terraform directory:

```bash
terraform plan -destroy
```

Read the plan.

Make sure Terraform plans to delete:

```text
keycloak-test-copy
```

and nothing production-related.

Then:

```bash
terraform destroy
```

---

# 58. Do Not Put Production and Test in the Same Terraform State Unless Necessary

A safer repository design is:

```text
terraform/
│
├── production/
│   └── keycloak-rds/
│
└── test/
    └── keycloak-rds-copy/
```

Then the test Terraform state only knows about:

```text
keycloak-test-copy
```

This reduces the chance of accidentally destroying production.

---

# 59. Suggested Project Structure

```text
keycloak-rds-clone/
│
├── README.md
│
├── terraform/
│   │
│   ├── main.tf
│   └── terraform.tfvars
│
├── scripts/
│   │
│   ├── 01-check-production.sh
│   ├── 02-create-snapshot.sh
│   ├── 03-check-snapshot.sh
│   ├── 04-verify-copy.sh
│   └── 05-test-database.sh
│
└── sql/
    │
    ├── check-keycloak.sql
    └── rename-database.sql
```

---

# 60. Example `rename-database.sql`

```sql
-- ==========================================================
-- IMPORTANT:
--
-- Run this ONLY against the RESTORED TEST RDS.
-- ==========================================================


-- Show what server/database/user we are connected to.

SELECT
    current_database(),
    current_user,
    inet_server_addr(),
    inet_server_port();


-- Show existing databases.

SELECT datname
FROM pg_database
ORDER BY datname;


-- Terminate connections to the copied Keycloak database.

SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'keycloak'
  AND pid <> pg_backend_pid();


-- Rename ONLY the copied database.

ALTER DATABASE keycloak
RENAME TO keycloak_test;


-- Verify.

SELECT datname
FROM pg_database
ORDER BY datname;
```

Run:

```bash
PGSSLMODE=require psql \
  -h NEW-RDS-ENDPOINT \
  -U rcsuper \
  -d postgres \
  -f rename-database.sql
```

---

# 61. Simple End-to-End Command Summary

## Check production

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-prod
```

## Create snapshot

```bash
aws rds create-db-snapshot \
  --db-instance-identifier keycloak-prod \
  --db-snapshot-identifier keycloak-prod-safe-20260830
```

## Wait for snapshot

```bash
aws rds wait db-snapshot-available \
  --db-snapshot-identifier keycloak-prod-safe-20260830
```

## Restore new RDS

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier keycloak-test-copy \
  --db-snapshot-identifier keycloak-prod-safe-20260830 \
  --db-instance-class db.t3.micro
```

## Wait for new RDS

```bash
aws rds wait db-instance-available \
  --db-instance-identifier keycloak-test-copy
```

## Get endpoint

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-test-copy \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

## Connect

```bash
PGSSLMODE=require psql \
  -h NEW-ENDPOINT \
  -U rcsuper \
  -d postgres
```

## Rename database

```sql
ALTER DATABASE keycloak
RENAME TO keycloak_test;
```

## Configure test Keycloak

```text
KC_DB=postgres

KC_DB_URL_HOST=NEW-RDS-ENDPOINT

KC_DB_URL_DATABASE=keycloak_test
```

## Start test Keycloak

```bash
docker compose up -d keycloak-test
```

---

# 62. Troubleshooting

## Problem: `password authentication failed`

Example:

```text
FATAL: password authentication failed for user "rcsuper"
```

This tells you:

```text
DNS              probably works
Network          probably works
Port 5432        probably works
PostgreSQL       responded
Password/User    problem
```

Check the RDS master username:

```bash
aws rds describe-db-instances \
  --db-instance-identifier keycloak-test-copy \
  --query "DBInstances[0].MasterUsername" \
  --output text
```

---

# 63. Problem: `no pg_hba.conf entry ... no encryption`

Use SSL:

```bash
PGSSLMODE=require psql \
  -h NEW-ENDPOINT \
  -p 5432 \
  -U rcsuper \
  -d keycloak_test
```

Do not try to manually edit:

```text
pg_hba.conf
```

on Amazon RDS as if it were a self-managed PostgreSQL EC2 server.

---

# 64. Problem: Connection Timeout

Example:

```text
connection timed out
```

Check:

```text
Security Group
Subnet
Route Table
Public/private setting
VPN
Firewall
Port 5432
```

Inspect the security group:

```bash
aws ec2 describe-security-groups \
  --group-ids sg-0123456789abcdef0
```

---

# 65. Problem: Database Does Not Exist

Example:

```text
FATAL: database "keycloak_test" does not exist
```

Connect to:

```text
postgres
```

and list databases:

```sql
\l
```

Maybe you have not renamed it yet.

It may still be:

```text
keycloak
```

---

# 66. Problem: Cannot Rename Database

If you see a message saying the database is being accessed by other users:

```sql
SELECT
    pid,
    usename,
    client_addr
FROM pg_stat_activity
WHERE datname = 'keycloak';
```

Terminate connections on the **test copy**:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'keycloak'
  AND pid <> pg_backend_pid();
```

Then:

```sql
ALTER DATABASE keycloak
RENAME TO keycloak_test;
```

---

# 67. Problem: Keycloak Starts Modifying the Database Before You Are Ready

Stop Keycloak.

Docker:

```bash
docker compose stop keycloak-test
```

Kubernetes:

```bash
kubectl scale deployment keycloak \
  --replicas=0 \
  -n keycloak-test
```

Do your database work first.

Then restart it.

This is especially important when testing a **newer Keycloak version**, because Keycloak may perform database schema changes during startup.

---

# 68. The Most Important Safety Rule for Upgrades

Never do this:

```text
NEWER KEYCLOAK VERSION
        |
        v
PRODUCTION DATABASE
```

just to see whether it works.

A safer approach is:

```text
Production DB
     |
  Snapshot
     |
     v
Test DB
     |
     v
New Keycloak
```

Test first.

---

# 69. Safe Production-to-Test Workflow

The complete workflow is:

```text
STEP 1
Verify production
        |
        v
STEP 2
Record configuration
        |
        v
STEP 3
Reduce application writes if needed
        |
        v
STEP 4
Create snapshot
        |
        v
STEP 5
Wait for snapshot
        |
        v
STEP 6
Return production to normal
        |
        v
STEP 7
Restore NEW RDS
        |
        v
STEP 8
Verify NEW endpoint
        |
        v
STEP 9
Connect to NEW RDS
        |
        v
STEP 10
Verify Keycloak data
        |
        v
STEP 11
Rename copied database
        |
        v
STEP 12
Change test credentials if desired
        |
        v
STEP 13
Review external integrations
        |
        v
STEP 14
Configure test Keycloak
        |
        v
STEP 15
Start test Keycloak
        |
        v
STEP 16
Test
```

---

# 70. Final Architecture

```text
                    AWS
                     |
          +----------+----------+
          |                     |
          |                     |
          v                     v

+-------------------+   +----------------------+
| Production RDS    |   | Test RDS             |
|                   |   |                      |
| keycloak-prod     |   | keycloak-test-copy   |
|                   |   |                      |
| DB: keycloak      |   | DB: keycloak_test    |
+---------+---------+   +----------+-----------+
          ^                        ^
          |                        |
          |                        |
+---------+---------+   +----------+-----------+
| Production        |   | Test Keycloak        |
| Keycloak          |   |                      |
|                   |   | New hostname         |
+-------------------+   +----------------------+
```

There is no database connection between the production Keycloak and test RDS.

There is no database connection between test Keycloak and production RDS.

That separation is exactly what we want.

---

# 71. Final Safety Checklist

Before snapshot:

```text
[ ] Correct AWS account
[ ] Correct AWS region
[ ] Correct production RDS name
[ ] Production healthy
[ ] Current settings recorded
```

Before restore:

```text
[ ] Snapshot status = available
[ ] New RDS name is different
[ ] Correct VPC
[ ] Correct subnet group
[ ] Correct security group
```

Before renaming:

```text
[ ] Connected to NEW RDS
[ ] Endpoint verified
[ ] Connected to postgres database
[ ] Production endpoint is NOT being used
[ ] Test Keycloak is stopped
```

Before starting test Keycloak:

```text
[ ] Database renamed to keycloak_test
[ ] New RDS endpoint configured
[ ] New hostname configured
[ ] SMTP reviewed
[ ] LDAP reviewed
[ ] Identity providers reviewed
[ ] Redirect URIs reviewed
[ ] Client URLs reviewed
[ ] SSL enabled
[ ] Database credentials verified
```

Before deletion:

```text
[ ] Confirm RDS name
[ ] Confirm endpoint
[ ] Confirm it says TEST
[ ] Confirm production RDS is untouched
[ ] Create final snapshot if needed
```

---

# 72. Easy Way to Remember the Process

Think of an RDS snapshot like making a photocopy of a school notebook.

You start with:

```text
ORIGINAL NOTEBOOK
```

You make:

```text
PHOTOCOPY
```

Then you put the photocopy into a new binder:

```text
NEW RDS INSTANCE
```

Then you change the label on the copied notebook:

```text
keycloak
     |
     v
keycloak_test
```

You never erase the original notebook.

That is the safest mental model:

```text
SNAPSHOT
   =
COPY

RESTORE
   =
NEW SERVER

RENAME DATABASE
   =
CHANGE THE LABEL INSIDE THE COPY

ORIGINAL
   =
UNCHANGED
```

---

# 73. Recommended Final Naming

A clear naming system makes mistakes less likely.

Production:

```text
RDS:
keycloak-prod

Database:
keycloak

DNS:
keycloak.company.com
```

Test:

```text
RDS:
keycloak-test-copy

Database:
keycloak_test

DNS:
keycloak-test.company.com
```

Snapshot:

```text
keycloak-prod-safe-20260830
```

This makes it obvious which system you are working on.

---

# 74. Final Recommendation

For a Keycloak snapshot restore, use this rule:

> Restore first, verify second, rename third, configure Keycloak fourth, and start Keycloak last.

Do not start the cloned Keycloak immediately after restoring the database.

First verify:

```text
RDS endpoint
database
user
network
SSL
hostname
SMTP
LDAP
OIDC/SAML
client URLs
```

Then allow Keycloak to connect.

This gives you a safe test environment while leaving the original Keycloak database unchanged.

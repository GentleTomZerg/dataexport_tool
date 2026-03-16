# Data Exporter

We need to implement a shell-version data exporter, there are several things we need to consider.

## Database Profile Reader

We need a module to provide functions to read different database profile
The properties config file and the related keys should be provided
Help me think about the design

## Crypto

The Database password should be encoded and saved in a file with naming conventions like ip_port_username.pwd

Also, when the sql executor module needs to connect to the database, we need to use this pwd file

## Export SQL Construct

The User can maintain a properties file or some better version of config, please correct me
The use could define the export info like: database profile name, tablename, columns, filter condition(how to design this part?), the export file name, etc.

## SQL Executor

The executor will connect to db according to the profile and execute the Constructed sql, and output them as a file

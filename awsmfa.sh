#!/bin/bash

# This only needs to be set if in your non-ephemeral AWS config you use a source profile other than "default".
# Source profile is the profile with your actual long lived API keys
SOURCE_PROFILE_NAME=

# This is the ARN of the IAM role that you want to assume by default
DEFAULT_ASSUMED_ROLE_ARN=

# This is an optional descriptive name of the IAM role that you want to assume by default
DEFAULT_ASSUMED_ROLE_NAME=

# Session duration
DURATION=129600

if [ -n "$SOURCE_PROFILE_NAME" ]; then
    profile_argument="--profile $SOURCE_PROFILE_NAME"
fi

# Fetch the ARN of the MFA device from the source profile
MFA_SERIAL=$(aws configure get mfa_serial $profile_argument)

token=$1              # Required argument
assumed_role_arn=$2   # Optional unless no DEFAULT_ASSUMED_ROLE_ARN is set
assumed_role_name=$3  # Optional

unset AWS_SHARED_CREDENTIALS_FILE
unset AWS_CONFIG_FILE
unset AWS_DEFAULT_PROFILE

cred_file=~/.aws/ephemeral-credentials
config_file=~/.aws/ephemeral-config

if [ -z "$token" ]; then
  echo "Please pass the 6 digit MFA token as the first argument"
  exit 1
fi

if [ -z "$MFA_SERIAL" ]; then
  echo -e "Unable to determine the ARN of the MFA device from "
  test -n "$SOURCE_PROFILE_NAME" && echo "profile ${SOURCE_PROFILE_NAME}" || echo "the default profile."
  exit 1
fi

if [ -z "$assumed_role_arn" ]; then assumed_role_arn="$DEFAULT_ASSUMED_ROLE_ARN"; fi
if [ -z "$assumed_role_arn" ]; then
  echo "No assumed role ARN was passed on the command line and no DEFAULT_ASSUMED_ROLE_ARN is configured in the tool."
  echo "Either pass an ARN on the command line or set a DEFAULT_ASSUMED_ROLE_ARN in the tool"
  exit 1
fi

if [ -z "$assumed_role_name" ]; then assumed_role_name="$DEFAULT_ASSUMED_ROLE_NAME"; fi
if [ -z "$assumed_role_name" ]; then
  IFS=':' read -ra arn <<< "$assumed_role_arn"
  assumed_role_name="${arn[4]}-${arn[5]#role/}"
fi

if ! grep "^\[profile ${assumed_role_name}\]$" "$config_file" >/dev/null 2>&1; then
  echo "[profile ${assumed_role_name}]" >> "$config_file"
fi

if ! sts=( $(
  aws sts get-session-token \
  ${profile_argument} \
  --serial-number "$MFA_SERIAL" \
  --token-code "$token" \
  --duration-seconds "$DURATION" \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text
) ); then
  exit 1
fi

AWS_SHARED_CREDENTIALS_FILE="$cred_file" AWS_CONFIG_FILE="$config_file" aws configure set profile.${assumed_role_name}.source_profile default
AWS_SHARED_CREDENTIALS_FILE="$cred_file" AWS_CONFIG_FILE="$config_file" aws configure set aws_access_key_id ${sts[0]} --profile default
AWS_SHARED_CREDENTIALS_FILE="$cred_file" AWS_CONFIG_FILE="$config_file" aws configure set aws_secret_access_key ${sts[1]} --profile default
AWS_SHARED_CREDENTIALS_FILE="$cred_file" AWS_CONFIG_FILE="$config_file" aws configure set aws_session_token ${sts[2]} --profile default
AWS_SHARED_CREDENTIALS_FILE="$cred_file" AWS_CONFIG_FILE="$config_file" aws configure set profile.${assumed_role_name}.role_arn ${assumed_role_arn}

echo "export AWS_SHARED_CREDENTIALS_FILE=\"$cred_file\""
echo "export AWS_CONFIG_FILE=\"$config_file\""
echo "export AWS_DEFAULT_PROFILE=\"$assumed_role_name\""


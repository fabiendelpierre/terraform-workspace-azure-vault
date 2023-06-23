#!/bin/bash

# Set the timezone
timedatectl set-timezone "${timezone}"

# Prepare to install packages
apt-get update

# Prerequisites
apt-get install -y jq unzip ca-certificates curl apt-transport-https lsb-release python3-pip

# Install Azure CLI
# # Install apt repo for Azure CLI
# curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
# AZ_REPO=$(lsb_release -cs)
# echo "deb [arch=${arch}] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | tee /etc/apt/sources.list.d/azure-cli.list

# # Refresh apt cache after adding repositories
# apt-get update
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Vault
echo $(pwd)
vault_zip_file="vault_${vault_version}_linux_${arch}.zip"
vault_checksum_file="vault_${vault_version}_SHA256SUMS"
curl -s https://releases.hashicorp.com/vault/${vault_version}/$vault_zip_file -o $vault_zip_file
curl -s https://releases.hashicorp.com/vault/${vault_version}/$vault_checksum_file -o $vault_checksum_file

sha256sum --status --ignore-missing --check $vault_checksum_file
if [[ "$?" == "0" ]];
then
    vault_root_path=/opt/vault
    vault_config_path=$vault_root_path/conf
    vault_config_file=$vault_config_path/vault.hcl
    vault_data_path=$vault_root_path/data
    vault_bin_path=$vault_root_path/bin
    vault_bin=$vault_bin_path/vault
    letsencrypt_certs_path=/etc/letsencrypt/live
    vault_tls_path=$vault_root_path/tls # vault.${dns_zone_name}
    vault_tls_cert_path=$vault_tls_path/fullchain.pem
    vault_tls_private_key_path=$vault_tls_path/privkey.pem

    unzip $vault_zip_file
    rm -f $vault_zip_file $vault_checksum_file

    groupadd -r vault
    useradd -r -g vault -d $vault_root_path -s /usr/sbin/nologin vault
    mkdir -p $vault_config_path $vault_data_path $vault_bin_path $vault_tls_path
    mv vault /usr/bin/
    ln -s /usr/bin/vault $vault_bin

    PRIV_IP=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d'/' -f1)
    cat << EOF | tee $vault_config_file
listener "tcp" {
  address = "127.0.0.1:8200"
  cluster_address = "127.0.0.1:8201"
  tls_disable = 1
}

listener "tcp" {
  address = "$PRIV_IP:8200"
  cluster_address = "$PRIV_IP:8201"
  tls_cert_file = "$vault_tls_cert_path"
  tls_key_file = "$vault_tls_private_key_path"
}

storage "raft" {
  path = "$vault_data_path"
}

seal "azurekeyvault" {
  tenant_id = "${azure_tenant_id}"
  vault_name = "${key_vault_name}"
  key_name = "${key_vault_key_name}"
}

api_addr = "https://vault.${dns_zone_name}"
cluster_addr = "https://$PRIV_IP:8201"
ui = true
disable_mlock = true
EOF

    # setcap 'cap_ipc_lock=+ep cap_net_bind_service=+ep' /usr/bin/vault
    cat << EOF | tee /usr/lib/systemd/system/vault.service
[Unit]
Description="HashiCorp Vault - A tool for managing secrets" Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target ConditionFileNotEmpty=$vault_config_file StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/bin/vault server -config=$vault_config_file ExecReload=/bin/kill --signal HUP MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitIntervalSec=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF
    sed -i -e 's/MAINPID/\$MAINPID/' /usr/lib/systemd/system/vault.service
    systemctl daemon-reload

    # Install certbot + Azure DNS plugin
    certbot_config_home=/opt/certbot
    certbot_config_file=$certbot_config_home/azure.ini
    pip3 install certbot certbot-dns-azure
    mkdir -p $certbot_config_home
    cat << EOF | tee $certbot_config_file
dns_azure_msi_client_id = ${msi_client_id}

dns_azure_zone1 = ${dns_zone_name}:${dns_zone_resource_group_id}
EOF

    if "${acme_staging}" == "true"
    then
      ACME_STAGING="--staging"
    else
      ACME_STAGING=""
    fi

    chmod 600 $certbot_config_file
    az login --identity -u ${msi_id}
    certbot certonly $ACME_STAGING \
      --authenticator dns-azure \
      --preferred-challenges dns \
      --noninteractive \
      --agree-tos \
      --dns-azure-config $certbot_config_file \
      -m "${certbot_contact_email}" \
      -d vault.${dns_zone_name}

    cat << EOF | tee /etc/letsencrypt/renewal-hooks/deploy/vault_cert.sh
#!/bin/bash
cp -f $letsencrypt_certs_path/vault.${dns_zone_name}/fullchain.pem $vault_tls_cert_path
cp -f $letsencrypt_certs_path/vault.${dns_zone_name}/privkey.pem $vault_tls_private_key_path
chmod 640 $vault_tls_cert_path $vault_tls_private_key_path
chown root:vault $vault_tls_cert_path $vault_tls_private_key_path
systemctl reload-or-restart vault
EOF
    chmod 755 /etc/letsencrypt/renewal-hooks/deploy/vault_cert.sh

    cp $letsencrypt_certs_path/vault.${dns_zone_name}/fullchain.pem $vault_tls_cert_path
    cp $letsencrypt_certs_path/vault.${dns_zone_name}/privkey.pem $vault_tls_private_key_path

    chown -R root:vault $vault_root_path # $letsencrypt_certs_path
    chmod 750 $vault_root_path $vault_config_path $vault_bin_path $vault_tls_path # $letsencrypt_certs_path
    chmod 770 $vault_data_path
    chmod 640 $vault_tls_cert_path $vault_tls_private_key_path $vault_config_file

    systemctl start vault
    sleep 10

    # Reusable function to check if a secret exists in Azure Key Vault
    secret_exists () {
      local vault_name=$1
      local secret_name=$2
      if az keyvault secret show --vault-name $1 --name $2 2>&1 | grep file-encoding >/dev/null
      then
        retval=0
      else
        retval=1
      fi
      return "$retval"
    }

    # Set the names of some Key Vault secrets
    kv_secret_name_prefix=$(echo vault.${dns_zone_name} | tr "." "-")
    # kv_secret_cert_fullchain="$kv_secret_name_prefix-cert-fullchain"
    # kv_secret_cert_privkey="$kv_secret_name_prefix-cert-private-key"

    # Initialize Vault
    # Check if Vault is already initialized
    # Since we're on a new node, this should always return false
    vault_endpoint="http://127.0.0.1:8200"
    init_check=$(curl -s "$vault_endpoint/v1/sys/init?initialized=true" | jq .initialized)

    if [[ "$init_check" == "false" ]]
    then
        if secret_exists "${key_vault_name}" "$kv_secret_name_prefix-is-initialized" == 0
        then
            # Do nothing
            echo "A Key Vault secret already exists, suggesting an instance of Vault was already initialized using the same Key Vault"
            exit 1
        else
            # Initialize Vault since it doesn't appear to be initialized
            initResult=$($vault_bin operator init -recovery-shares ${recovery_keys} -recovery-threshold ${recovery_threshold} -address="$vault_endpoint" -format=json)
            # Now Vault should be initialized and unsealed
            postInitChecks=$(curl -s $vault_endpoint/v1/sys/health)
            isInitialized=$(echo $postInitChecks | jq .initialized)
            isSealed=$(echo $postInitChecks | jq .sealed)

            if [[ "$isInitialized" == "true" ]] && [[ "$isSealed" == "false" ]]
            then
                echo "Vault is now initialized and unsealed as expected"
                # Create a secret to indicate that Vault is now initialized
                az keyvault secret set --name $kv_secret_name_prefix-is-initialized --vault-name ${key_vault_name} --value "true"

                # Store secrets in a temp file for testing purposes
                # echo -n $initResult | jq . > /tmp/keys
                # Parse the init output into the individual components we want
                recoveryKey1=$(echo -n $initResult | jq -r '.recovery_keys_b64[0]')
                # recoveryKey2=$(echo -n $initResult | jq -r '.recovery_keys_b64[1]')
                # recoveryKey3=$(echo -n $initResult | jq -r '.recovery_keys_b64[2]')
                # recoveryKey4=$(echo -n $initResult | jq -r '.recovery_keys_b64[3]')
                # recoveryKey5=$(echo -n $initResult | jq -r '.recovery_keys_b64[4]')
                rootToken=$(echo -n $initResult | jq -r '.root_token')

                # Write the secrets to Azure Key Vault
                # Recovery key 1
                if secret_exists "${key_vault_name}" "$kv_secret_name_prefix-recovery-key-1" == 0
                then
                    echo "Secret $kv_secret_name_prefix-recovery-key-1 already exists, skipping Key Vault upload step..."
                else
                    az keyvault secret set --name $kv_secret_name_prefix-recovery-key-1 --vault-name ${key_vault_name} --value "$recoveryKey1"
                fi

                # Root token
                if secret_exists "${key_vault_name}" "$kv_secret_name_prefix-initial-root-token" == 0
                then
                    echo "Secret $kv_secret_name_prefix-initial-root-token already exists, skipping Key Vault upload step..."
                else
                    az keyvault secret set --name $kv_secret_name_prefix-initial-root-token --vault-name ${key_vault_name} --value "$rootToken"
                fi

                # Clear the shell variables from memory to be extra safe
                # rm -f /tmp/keys
                unset VAULT_TOKEN initResult recoveryKey1 recoveryKey2 recoveryKey3 recoveryKey4 recoveryKey5 rootToken
            else
                echo "Vault is either not initialized, or is sealed, something went wrong. Aborting."
                exit 1
            fi
        fi
    fi
else
    echo 'Vault zip file checksum DOES NOT match expected checksum, aborting...';
    exit 1
fi

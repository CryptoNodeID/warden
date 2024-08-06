#!/bin/bash
CHAIN_NAME=wardenprotocol
DAEMON_NAME=wardend
DAEMON_HOME=$HOME/.warden
INSTALLATION_DIR=$(dirname "$(realpath "$0")")
CHAIN_ID='buenavista-1'
DENOM='uward'
GENESIS="https://snapshot.cryptonode.id/warden-testnet/genesis.json"
SEEDS=""
PEERS="85abfb1a10ef88d37277e7462830890ff2f7a1ac@sentry1.cryptonode.id:24656,400195374c9bde32385a4398719ba3f529066569@sentry2.cryptonode.id:24656,92ba004ac4bcd5afbd46bc494ec906579d1f5c1d@52.30.124.80:26656,ed5781ea586d802b580fdc3515d75026262f4b9d@54.171.21.98:26656"
GOPATH=$HOME/go

# Pre-requisites
cd ${INSTALLATION_DIR}
if ! grep -q "export GOPATH=" ~/.profile; then
    echo "export GOPATH=$HOME/go" >> ~/.profile
    source ~/.profile
fi
if ! grep -q "export PATH=.*:/usr/local/go/bin" ~/.profile; then
    echo "export PATH=$PATH:/usr/local/go/bin" >> ~/.profile
    source ~/.profile
fi
if ! grep -q "export PATH=.*$GOPATH/bin" ~/.profile; then
    echo "export PATH=$PATH:$GOPATH/bin" >> ~/.profile
    source ~/.profile
fi
GO_VERSION=$(go version 2>/dev/null | grep -oP 'go1\.22\.0')
if [ -z "$(echo "$GO_VERSION" | grep -E 'go1\.22\.0')" ]; then
    echo "Go is not installed or not version 1.22.0. Installing Go 1.22.0..."
    wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz
    sudo rm -rf $(which go)
    sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz
    rm go1.22.0.linux-amd64.tar.gz
else
    echo "Go version 1.22.0 is already installed."
fi
sudo apt -qy install curl git jq lz4 build-essential unzip
rm -rf ${CHAIN_NAME}
rm -rf ${DAEMON_HOME}
mkdir -p ${INSTALLATION_DIR}/bin
mkdir -p ${DAEMON_HOME}/cosmovisor/genesis/bin
mkdir -p ${DAEMON_HOME}/cosmovisor/upgrades
if ! command -v cosmovisor &> /dev/null; then
    wget https://github.com/cosmos/cosmos-sdk/releases/download/cosmovisor%2Fv1.5.0/cosmovisor-v1.5.0-linux-amd64.tar.gz
    tar -xvzf cosmovisor-v1.5.0-linux-amd64.tar.gz
    rm cosmovisor-v1.5.0-linux-amd64.tar.gz
    mv cosmovisor /usr/local/bin/cosmovisor
    cp ${INSTALLATION_DIR}/bin/cosmovisor /usr/local/bin/cosmovisor -f
fi

# Download and install Binary
wget https://github.com/warden-protocol/wardenprotocol/releases/download/v0.3.2/wardend_Linux_x86_64.zip
unzip wardend_Linux_x86_64.zip
rm -rf wardend_Linux_x86_64.zip
mv ${DAEMON_NAME} ${INSTALLATION_DIR}/bin

# Copy binary to cosmovisor
cp ${INSTALLATION_DIR}/bin/${DAEMON_NAME} ${DAEMON_HOME}/cosmovisor/genesis/bin/
sudo ln -s ${DAEMON_HOME}/cosmovisor/genesis ${DAEMON_HOME}/cosmovisor/current -f
sudo ln -s ${DAEMON_HOME}/cosmovisor/current/bin/${DAEMON_NAME} /usr/local/bin/${DAEMON_NAME} -f

read -p "Enter validator key name: " VALIDATOR_KEY_NAME
if [ -z "$VALIDATOR_KEY_NAME" ]; then
    echo "Error: No validator key name provided."
    exit 1
fi

${DAEMON_NAME} version
read -p "Do you want to recover wallet? [y/N]: " RECOVER
RECOVER=$(echo "$RECOVER" | tr '[:upper:]' '[:lower:]')
if [[ "$RECOVER" == "y" || "$RECOVER" == "yes" ]]; then
    ${DAEMON_NAME} keys add $VALIDATOR_KEY_NAME --recover
else
    ${DAEMON_NAME} keys add $VALIDATOR_KEY_NAME
fi
${DAEMON_NAME} init $VALIDATOR_KEY_NAME --chain-id=$CHAIN_ID
${DAEMON_NAME} keys list
if ! grep -q 'export WALLET='${VALIDATOR_KEY_NAME} ~/.profile; then
    echo "export WALLET=${VALIDATOR_KEY_NAME}" >> ~/.profile
fi

wget ${GENESIS} -O ${DAEMON_HOME}/config/genesis.json
wget "https://raw.githubusercontent.com/111STAVR111/props/main/Warden/addrbook.json" -O ${DAEMON_HOME}/config/addrbook.json 

sed -i 's/minimum-gas-prices *=.*/minimum-gas-prices = "0.0025'$DENOM'"/' ${DAEMON_HOME}/config/app.toml
sed -i \
  -e 's|^pruning *=.*|pruning = "custom"|' \
  -e 's|^pruning-keep-recent *=.*|pruning-keep-recent = "100"|' \
  -e 's|^pruning-keep-every *=.*|pruning-keep-every = "0"|' \
  -e 's|^pruning-interval *=.*|pruning-interval = "10"|' \
  ${DAEMON_HOME}/config/app.toml

# Setup for Validator Info
read -p "Enter identity (leave blank for default 'CryptoNode.ID guide'): " INPUT_IDENTITY
INPUT_IDENTITY=${INPUT_IDENTITY:-"CryptoNode.ID guide"}
read -p "Enter website (leave blank for default 'https://cryptonode.id'): " INPUT_WEBSITE
INPUT_WEBSITE=${INPUT_WEBSITE:-"https://cryptonode.id"}
read -p "Enter your email (leave blank for default 't.me/CryptoNodeID'): " INPUT_EMAIL
INPUT_EMAIL=${INPUT_EMAIL:-"t.me/CryptoNodeID"}
read -p "Enter details (leave blank for default 'created using cryptonode.id helper'): " INPUT_DETAILS
INPUT_DETAILS=${INPUT_DETAILS:-"created using cryptonode.id helper"}

# Helper scripts
cd ${INSTALLATION_DIR}
rm -rf list_keys.sh check_balance.sh create_validator.sh unjail_validator.sh check_validator.sh start_side.sh check_log.sh
echo "${DAEMON_NAME} keys list" > list_keys.sh && chmod +x list_keys.sh
echo "${DAEMON_NAME} q bank balances $(${DAEMON_NAME} keys show $VALIDATOR_KEY_NAME -a)" > check_balance.sh && chmod +x check_balance.sh
read -p "Do you want to use custom port number prefix (y/N)? " use_custom_port
if [[ "$use_custom_port" =~ ^[Yy](es)?$ ]]; then
    read -p "Enter port number prefix (max 2 digits, not exceeding 50): " port_prefix
    while [[ "$port_prefix" =~ [^0-9] || ${#port_prefix} -gt 2 || $port_prefix -gt 50 ]]; do
        read -p "Invalid input, enter port number prefix (max 2 digits, not exceeding 50): " port_prefix
    done
    sed -i.bak -e "s%:26656%:${port_prefix}656%g;" ${DAEMON_HOME}/config/client.toml
    sed -i.bak -e "s%:1317%:${port_prefix}317%g; s%:8080%:${port_prefix}080%g; s%:9090%:${port_prefix}090%g; s%:9091%:${port_prefix}091%g; s%:8545%:${port_prefix}545%g; s%:8546%:${port_prefix}546%g; s%:6065%:${port_prefix}065%g" ${DAEMON_HOME}/config/app.toml
    sed -i.bak -e "s%:26658%:${port_prefix}658%g; s%:26657%:${port_prefix}657%g; s%:6060%:${port_prefix}060%g; s%:26656%:${port_prefix}656%g; s%:26660%:${port_prefix}660%g" ${DAEMON_HOME}/config/config.toml
fi

sed -i.bak \
        -e "/^[[:space:]]*seeds =/ s/=.*/= \"$SEEDS\"/" \
        -e "s/^[[:space:]]*persistent_peers *=.*/persistent_peers = \"$PEERS\"/" \
        ${DAEMON_HOME}/config/config.toml

tee validator.json > /dev/null <<EOF
{
    "pubkey": $(${DAEMON_NAME} comet show-validator),
    "amount": "1000000${DENOM}",
    "moniker": "$VALIDATOR_KEY_NAME",
    "identity": "$INPUT_IDENTITY",
    "website": "$INPUT_WEBSITE",
    "security": "$INPUT_EMAIL",
    "details": "$INPUT_DETAILS",
    "commission-rate": "0.1",
    "commission-max-rate": "0.2",
    "commission-max-change-rate": "0.01",
    "min-self-delegation": "1"
}
EOF
tee create_validator.sh > /dev/null <<EOF
#!/bin/bash
${DAEMON_NAME} tx staking create-validator ./validator.json \
    --from=${VALIDATOR_KEY_NAME} \
    --chain-id=${CHAIN_ID} \
    --fees=500${DENOM}
EOF
chmod +x create_validator.sh
tee claim_faucet.sh > /dev/null <<EOF
#!/bin/bash
curl -XPOST -d '{"address": "\$(${DAEMON_NAME} keys show $VALIDATOR_KEY_NAME -a)"}' https://faucet.buenavista.wardenprotocol.org
EOF
chmod +x claim_faucet.sh
tee unjail_validator.sh > /dev/null <<EOF
#!/bin/bash
${DAEMON_NAME} tx slashing unjail \
 --from=$VALIDATOR_KEY_NAME \
 --chain-id="$CHAIN_ID" \
 --fees=500${DENOM}
EOF
chmod +x unjail_validator.sh
tee check_validator.sh > /dev/null <<EOF
#!/bin/bash
${DAEMON_NAME} query comet-validator-set | grep "\$(${DAEMON_NAME} comet show-address)"
EOF
chmod +x check_validator.sh
tee start_${DAEMON_NAME}.sh > /dev/null <<EOF
sudo systemctl daemon-reload
sudo systemctl enable ${DAEMON_NAME}
sudo systemctl restart ${DAEMON_NAME}
EOF
chmod +x start_${DAEMON_NAME}.sh
tee check_log.sh > /dev/null <<EOF
sudo journalctl -u ${DAEMON_NAME} -f
EOF
chmod +x check_log.sh

sudo tee /etc/systemd/system/${DAEMON_NAME}.service > /dev/null <<EOF
[Unit]
Description=${CHAIN_NAME} daemon
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=always
RestartSec=3
LimitNOFILE=infinity

Environment="DAEMON_NAME=${DAEMON_NAME}"
Environment="DAEMON_HOME=${DAEMON_HOME}"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"

[Install]
WantedBy=multi-user.target
EOF
if ! grep -q 'export DAEMON_NAME=' $HOME/.profile; then
    echo "export DAEMON_NAME=${DAEMON_NAME}" >> $HOME/.profile
fi
if ! grep -q 'export DAEMON_HOME=' $HOME/.profile; then
    echo "export DAEMON_HOME=${DAEMON_HOME}" >> $HOME/.profile
fi
if ! grep -q 'export DAEMON_RESTART_AFTER_UPGRADE=' $HOME/.profile; then
    echo "export DAEMON_RESTART_AFTER_UPGRADE=true" >> $HOME/.profile
fi
if ! grep -q 'export DAEMON_ALLOW_DOWNLOAD_BINARIES=' $HOME/.profile; then
    echo "export DAEMON_ALLOW_DOWNLOAD_BINARIES=false" >> $HOME/.profile
fi
if ! grep -q 'export CHAIN_ID=' $HOME/.profile; then
    echo "export CHAIN_ID=${CHAIN_ID}" >> $HOME/.profile
fi
source $HOME/.profile

sudo systemctl daemon-reload
read -p "Do you want to enable the ${DAEMON_NAME} service? (y/N): " ENABLE_SERVICE
if [[ "$ENABLE_SERVICE" =~ ^[Yy](es)?$ ]]; then
    sudo systemctl enable ${DAEMON_NAME}.service
else
    echo "Skipping enabling ${DAEMON_NAME} service."
fi
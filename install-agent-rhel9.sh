#!/bin/bash
DEVOPS_URL=$1
PAT_TOKEN=$2
VM_NAME=$3
AGENT_COUNT=$4
AGENT_POOL=$5

# Instalace závislostí pro RHEL 9
sudo dnf update -y
sudo dnf install -y curl unzip libicu

# Stažení agenta
curl -L https://vstsagentpackage.azureedge.net/agent/4.251.0/vsts-agent-linux-x64-4.251.0.tar.gz -o agent.tar.gz

# Instalace a konfigurace více agentů
for i in $(seq 1 $AGENT_COUNT); do
  AGENT_NAME="${VM_NAME}-agent${i}"
  mkdir "myagent${i}" && cd "myagent${i}"
  tar -xzf ../agent.tar.gz

  # Konfigurace agenta s PAT
  ./config.sh --unattended \
    --url "$DEVOPS_URL" \
    --auth pat \
    --token "$PAT_TOKEN" \
    --pool "$AGENT_POOL" \ 
    --agent "$AGENT_NAME" \
    --acceptTeeEula

  # Registrování agenta jako služby
  sudo ./svc.sh install
  sudo ./svc.sh start
  cd ..
done

# Úklid
rm agent.tar.gz
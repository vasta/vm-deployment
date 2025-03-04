#!/bin/bash
DEVOPS_URL=$1
PAT_TOKEN=$2
VM_NAME=$3
AGENT_COUNT=$4
AGENT_POOL=$5
AGENT_USER="azagent"

# Instalace závislostí pro RHEL 9
sudo dnf update -y
sudo dnf install -y curl unzip libicu

# Vytvoření uživatele azagent, pokud ještě neexistuje
if ! id "$AGENT_USER" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "$AGENT_USER"
  echo "Uživatel $AGENT_USER vytvořen"
else
  echo "Uživatel $AGENT_USER již existuje"
fi


# Stažení agenta
curl -L https://vstsagentpackage.azureedge.net/agent/4.251.0/vsts-agent-linux-x64-4.251.0.tar.gz -o agent.tar.gz

# Instalace a konfigurace více agentů
for i in $(seq 1 $AGENT_COUNT); do
  AGENT_NAME="${VM_NAME}-agent-0${i}"
  AGENT_DIR="/home/$AGENT_USER/myagent${i}"

  # Vytvoření adresáře pro agenta a nastavení vlastníka
  sudo mkdir -p "$AGENT_DIR"
  sudo chown "$AGENT_USER:$AGENT_USER" "$AGENT_DIR"

  # Kopie a rozbalení agenta jako azagent
  sudo -u "$AGENT_USER" bash -c "cd $AGENT_DIR && cp /tmp/agent.tar.gz . && tar -xzf agent.tar.gz"

  # Konfigurace agenta jako azagent
  sudo -u "$AGENT_USER" bash -c "cd $AGENT_DIR && ./config.sh --unattended \
    --url "$DEVOPS_URL" \
    --auth pat \
    --token "$PAT_TOKEN" \
    --pool "$AGENT_POOL" \
    --agent "$AGENT_NAME" \
    --acceptTeeEula"

  # Registrování agenta jako služby
  sudo bash -c "cd $AGENT_DIR && ./svc.sh install $AGENT_USER"
  sudo bash -c "cd $AGENT_DIR && ./svc.sh start"
  cd ..
done

# Úklid
sudo rm agent.tar.gz

#!/bin/bash
DEVOPS_URL=$1
PAT_TOKEN=$2
VM_NAME=$3
AGENT_COUNT=$4
AGENT_POOL=$5
BASE_DIR="/opt/devops-agents"  # Pevně daná cesta pro instalaci agentů
LOG_FILE="/var/log/install-agents.log"

echo "$(date) - Starting script" | sudo tee -a "$LOG_FILE"

# Instalace závislostí pro RHEL 9
sudo dnf update -y 2>&1 | sudo tee -a "$LOG_FILE"
sudo dnf install -y curl unzip libicu 2>&1 | sudo tee -a "$LOG_FILE"

# Stažení agenta do dočasného adresáře
echo "$(date) - Stahování agenta" | sudo tee -a "$LOG_FILE"
curl -L https://vstsagentpackage.azureedge.net/agent/4.251.0/vsts-agent-linux-x64-4.251.0.tar.gz -o /tmp/agent.tar.gz 2>&1 | sudo tee -a "$LOG_FILE"
if [ $? -ne 0 ] || [ ! -f "/tmp/agent.tar.gz" ]; then
  echo "$(date) - Chyba: Stažení agenta selhalo nebo soubor nenalezen" | sudo tee -a "$LOG_FILE"
  exit 1
fi
echo "$(date) - Agent úspěšně stažen: $(ls -l /tmp/agent.tar.gz)" | sudo tee -a "$LOG_FILE"

# Zajistit, že soubor je čitelný
sudo chmod 644 /tmp/agent.tar.gz 2>&1 | sudo tee -a "$LOG_FILE"

# Instalace a konfigurace více agentů
for i in $(seq 1 $AGENT_COUNT); do
  AGENT_NAME="${VM_NAME}-agent${i}"
  AGENT_DIR="${BASE_DIR}/myagent${i}"

  echo "$(date) - Instalace agenta $AGENT_NAME do $AGENT_DIR" | sudo tee -a "$LOG_FILE"

  # Vytvoření adresáře
  sudo mkdir -p "$AGENT_DIR" 2>&1 | sudo tee -a "$LOG_FILE"
  echo "$(date) - Adresář $AGENT_DIR vytvořen: $(ls -ld $AGENT_DIR)" | sudo tee -a "$LOG_FILE"

  # Kopie agenta
  echo "$(date) - Kopírování agenta do $AGENT_DIR" | sudo tee -a "$LOG_FILE"
  sudo cp /tmp/agent.tar.gz "$AGENT_DIR" 2>&1 | sudo tee -a "$LOG_FILE"
  if [ $? -ne 0 ] || [ ! -f "$AGENT_DIR/agent.tar.gz" ]; then
    echo "$(date) - Chyba: agent.tar.gz nebyl zkopírován do $AGENT_DIR" | sudo tee -a "$LOG_FILE"
    echo "$(date) - Oprávnění /tmp/agent.tar.gz: $(ls -l /tmp/agent.tar.gz)" | sudo tee -a "$LOG_FILE"
    echo "$(date) - Oprávnění $AGENT_DIR: $(ls -ld $AGENT_DIR)" | sudo tee -a "$LOG_FILE"
    exit 1
  fi
  echo "$(date) - Agent úspěšně zkopírován: $(ls -l $AGENT_DIR/agent.tar.gz)" | sudo tee -a "$LOG_FILE"

  # Vyčištění adresáře před rozbalením (kromě agent.tar.gz)
  echo "$(date) - Čištění $AGENT_DIR před rozbalením" | sudo tee -a "$LOG_FILE"
  sudo find "$AGENT_DIR" -type f ! -name 'agent.tar.gz' -delete 2>&1 | sudo tee -a "$LOG_FILE"
  sudo find "$AGENT_DIR" -type d ! -path "$AGENT_DIR" -delete 2>&1 | sudo tee -a "$LOG_FILE"

  # Rozbalení agenta
  echo "$(date) - Rozbalování agenta v $AGENT_DIR" | sudo tee -a "$LOG_FILE"
  sudo bash -c "cd $AGENT_DIR && tar -xzf $AGENT_DIR/agent.tar.gz" 2>&1 | sudo tee -a "$LOG_FILE"
  if [ $? -ne 0 ] || [ ! -f "$AGENT_DIR/svc.sh" ]; then
    echo "$(date) - Chyba: Rozbalení selhalo nebo svc.sh nenalezen v $AGENT_DIR" | sudo tee -a "$LOG_FILE"
    echo "$(date) - Obsah $AGENT_DIR po rozbalení: $(ls -l $AGENT_DIR)" | sudo tee -a "$LOG_FILE"
    echo "$(date) - Kontrola integrity archivu: $(tar -tzf $AGENT_DIR/agent.tar.gz | grep svc.sh)" | sudo tee -a "$LOG_FILE"
    exit 1
  fi
  echo "$(date) - Agent úspěšně rozbalen v $AGENT_DIR" | sudo tee -a "$LOG_FILE"

  # Konfigurace agenta
  sudo bash -c "cd $AGENT_DIR && ./config.sh --unattended \
    --url '$DEVOPS_URL' \
    --auth pat \
    --token '$PAT_TOKEN' \
    --pool '$AGENT_POOL' \
    --agent '$AGENT_NAME' \
    --acceptTeeEula" 2>&1 | sudo tee -a "$LOG_FILE"

  # Instalace a spuštění služby
  sudo bash -c "cd $AGENT_DIR && ./svc.sh install" 2>&1 | sudo tee -a "$LOG_FILE"
  sudo bash -c "cd $AGENT_DIR && ./svc.sh start" 2>&1 | sudo tee -a "$LOG_FILE"
done

# Úklid
sudo rm /tmp/agent.tar.gz 2>&1 | sudo tee -a "$LOG_FILE"
echo "$(date) - Script completed" | sudo tee -a "$LOG_FILE"
